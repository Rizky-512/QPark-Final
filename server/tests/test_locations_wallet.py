import tempfile
import unittest
from pathlib import Path
from server.rules import RuleError
from server.store import Store, uid


class LocationsAndWalletTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.now = 1800000000.0
        self.s = Store(Path(self.tmp.name) / 'v5.db', lambda: self.now)
        self.superadmin = self.s.dispatch('POST', '/api/login', {'username': 'superadmin', 'password': 'superadmin123'})['token']
        self.pengelola_a = self.s.dispatch('POST', '/api/login', {'username': 'admin', 'password': 'admin123'})['token']
        self.petugas_a = self.s.dispatch('POST', '/api/login', {'username': 'petugas', 'password': 'petugas123'})['token']
        self.pengelola_b = self.s.dispatch('POST', '/api/login', {'username': 'pengelola_b', 'password': 'pengelola123'})['token']
        self.petugas_b = self.s.dispatch('POST', '/api/login', {'username': 'petugas_b', 'password': 'petugas123'})['token']
        self.ckey = 'a' * 48

    def test_superadmin_creates_location_and_pengelola_isolation(self):
        # Public capacity includes list of locations.
        cap = self.s.dispatch('GET', '/api/capacity')
        self.assertGreaterEqual(len(cap['locations']), 2)

        # Superadmin creates Location C.
        created = self.s.dispatch(
            'POST', '/api/admin/locations',
            {'name': 'QPark Stasiun C', 'address': 'Jl. Stasiun 9', 'car_capacity': 5, 'motor_capacity': 8,
             'car_rate': 5000, 'motor_rate': 1500, 'active': True, 'operation_key': uid('op')},
            token=self.superadmin,
        )
        loc_c = created['location']['id']
        self.assertEqual(created['location']['categories']['MOBIL']['total'], 5)

        # Superadmin creates Pengelola C for Location C.
        self.s.dispatch(
            'POST', '/api/admin/users',
            {'username': 'pengelola_c', 'password': 'password123', 'role': 'ADMIN',
             'location_id': loc_c, 'active': True, 'operation_key': uid('op')},
            token=self.superadmin,
        )
        login_c = self.s.dispatch('POST', '/api/login', {'username': 'pengelola_c', 'password': 'password123'})
        self.assertEqual(login_c['location_id'], loc_c)
        token_c = login_c['token']

        # Pengelola C can configure own location's slots.
        updated = self.s.dispatch(
            'POST', '/api/admin/settings',
            {'car_capacity': 12, 'motor_capacity': 15, 'car_rate': 5000, 'motor_rate': 1500},
            token=token_c,
        )
        self.assertEqual(updated['settings']['car_capacity'], 12)

        # Pengelola C cannot modify LOC-DEFAULT settings or create a location.
        with self.assertRaises(RuleError):
            self.s.dispatch(
                'POST', '/api/admin/settings',
                {'location_id': 'LOC-DEFAULT', 'car_capacity': 1, 'motor_capacity': 1, 'car_rate': 5000, 'motor_rate': 1500},
                token=token_c,
            )
        with self.assertRaises(RuleError):
            self.s.dispatch(
                'POST', '/api/admin/locations',
                {'name': 'Illegal', 'car_capacity': 1, 'motor_capacity': 1, 'car_rate': 1000, 'motor_rate': 1000, 'operation_key': uid('op')},
                token=token_c,
            )

        # Vehicle enters Location B; Petugas A cannot see or quote it.
        entered_b = self.s.dispatch(
            'POST', '/api/officer/entry',
            {'plate': 'B999LOC', 'vehicle_type': 'MOBIL', 'verified': True, 'image_source': 'manual', 'operation_key': uid('op')},
            token=self.petugas_b,
        )['session']
        self.assertEqual(entered_b['location_id'], 'LOC-2')
        self.assertEqual(entered_b['hourly_rate'], 6000)
        self.assertEqual(len(self.s.dispatch('GET', '/api/officer/monitor', token=self.petugas_a)['sessions']), 0)
        self.assertEqual(len(self.s.dispatch('GET', '/api/officer/monitor', token=self.petugas_b)['sessions']), 1)
        with self.assertRaises(RuleError):
            self.s.dispatch('POST', '/api/officer/manual-quote', {'session_id': entered_b['id']}, token=self.petugas_a)

    def test_wallet_topup_inspect_and_qr_pay(self):
        # Empty wallet initially.
        w = self.s.dispatch('GET', '/api/wallet', customer_key=self.ckey)
        self.assertEqual(w['balance'], 0)

        # Officer enters vehicle and generates invoice.
        session = self.s.dispatch(
            'POST', '/api/officer/entry',
            {'plate': 'D1234EW', 'vehicle_type': 'MOTOR', 'verified': True, 'image_source': 'manual', 'operation_key': uid('op')},
            token=self.petugas_a,
        )['session']
        inv = self.s.dispatch('POST', '/api/officer/manual-quote', {'session_id': session['id']}, token=self.petugas_a)['invoice']
        qr_code = f"QPP.SIMULASI.{inv['id']}"

        # Inspect works and shows balance 0 vs amount 2000.
        inspected = self.s.dispatch('POST', '/api/wallet/inspect', {'qr': qr_code}, customer_key=self.ckey)
        self.assertEqual(inspected['invoice']['amount'], 2000)
        self.assertEqual(inspected['session']['plate'], 'D1234EW')
        self.assertEqual(inspected['balance'], 0)

        # Paying with insufficient balance fails cleanly.
        with self.assertRaises(RuleError) as ctx:
            self.s.dispatch('POST', '/api/wallet/pay', {'qr': qr_code, 'operation_key': uid('op')}, customer_key=self.ckey)
        self.assertEqual(ctx.exception.code, 'insufficient_balance')

        # Top up 50,000 (idempotent).
        op_topup = uid('op')
        t1 = self.s.dispatch('POST', '/api/wallet/topup', {'amount': 50000, 'operation_key': op_topup}, customer_key=self.ckey)
        t2 = self.s.dispatch('POST', '/api/wallet/topup', {'amount': 50000, 'operation_key': op_topup}, customer_key=self.ckey)
        self.assertEqual(t1['balance'], 50000)
        self.assertEqual(t2['balance'], 50000)

        # Pay via scanned QR with E-Wallet (idempotent).
        op_pay = uid('op')
        paid = self.s.dispatch('POST', '/api/wallet/pay', {'qr': qr_code, 'operation_key': op_pay}, customer_key=self.ckey)
        self.assertEqual(paid['outcome'], 'SUCCESS')
        self.assertEqual(paid['balance'], 48000)
        self.assertEqual(paid['session']['window_status'], 'VALID')
        self.assertIsNotNone(paid['session']['exit_qr'])

        # Replay returns same result without double deduction.
        replay = self.s.dispatch('POST', '/api/wallet/pay', {'qr': qr_code, 'operation_key': op_pay}, customer_key=self.ckey)
        self.assertEqual(replay['balance'], 48000)

        # Wallet transactions reflect topup + payment.
        w2 = self.s.dispatch('GET', '/api/wallet', customer_key=self.ckey)
        self.assertEqual(w2['balance'], 48000)
        self.assertEqual([t['kind'] for t in w2['transactions']], ['PAYMENT', 'TOPUP'])

        # Customer now has linked ticket visible.
        ticket = self.s.dispatch('GET', '/api/ticket?plate=D1234EW', customer_key=self.ckey)['session']
        self.assertEqual(ticket['id'], session['id'])


if __name__ == '__main__':
    unittest.main()
