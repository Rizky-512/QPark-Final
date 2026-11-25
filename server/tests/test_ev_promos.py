import tempfile
import unittest
from pathlib import Path
from server.rules import RuleError
from server.store import Store, uid


class EvAndPromosTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.now = 1800000000.0
        self.s = Store(Path(self.tmp.name) / 'v6.db', lambda: self.now)
        self.pengelola_a = self.s.dispatch('POST', '/api/login', {'username': 'admin', 'password': 'admin123'})['token']
        self.petugas_a = self.s.dispatch('POST', '/api/login', {'username': 'petugas', 'password': 'petugas123'})['token']
        self.pengelola_b = self.s.dispatch('POST', '/api/login', {'username': 'pengelola_b', 'password': 'pengelola123'})['token']
        self.ckey = 'b' * 48

    def test_ev_booking_requires_registered_blue_plate_and_respects_capacity(self):
        # Register regular non-EV car plate.
        self.s.dispatch(
            'POST', '/api/customer/vehicle-type',
            {'plate': 'B100REG', 'vehicle_type': 'MOBIL', 'is_ev': False},
            customer_key=self.ckey,
        )
        # Attempt EV booking with non-blue plate -> rejected.
        with self.assertRaises(RuleError) as ctx:
            self.s.dispatch(
                'POST', '/api/ev/book',
                {'location_id': 'LOC-DEFAULT', 'plate': 'B100REG', 'duration_hours': 2, 'operation_key': uid('op')},
                customer_key=self.ckey,
            )
        self.assertEqual(ctx.exception.code, 'ev_plate_required')

        # Register blue EV plate.
        self.s.dispatch(
            'POST', '/api/customer/vehicle-type',
            {'plate': 'B200EV', 'vehicle_type': 'MOBIL', 'is_ev': True},
            customer_key=self.ckey,
        )
        types = self.s.dispatch('GET', '/api/customer/vehicle-types', customer_key=self.ckey)
        self.assertTrue(types['ev_plates']['B200EV'])
        self.assertFalse(types['ev_plates']['B100REG'])

        # Pengelola A reduces EV capacity to 1.
        self.s.dispatch(
            'POST', '/api/admin/settings',
            {'car_capacity': 10, 'motor_capacity': 10, 'car_rate': 7000, 'motor_rate': 2000, 'ev_capacity': 1, 'ev_rate': 12000},
            token=self.pengelola_a,
        )

        # Book EV succeeds and consumes the 1 slot.
        booked = self.s.dispatch(
            'POST', '/api/ev/book',
            {'location_id': 'LOC-DEFAULT', 'plate': 'B200EV', 'duration_hours': 2, 'operation_key': uid('op')},
            customer_key=self.ckey,
        )
        self.assertEqual(booked['booking']['estimated_cost'], 24000)
        cap = self.s.dispatch('GET', '/api/capacity')
        self.assertEqual(cap['ev']['occupied'], 1)
        self.assertEqual(cap['ev']['available'], 0)
        self.assertTrue(cap['ev']['full'])

        # Pengelola A cannot drop ev_capacity below active bookings (1).
        with self.assertRaises(RuleError):
            self.s.dispatch(
                'POST', '/api/admin/settings',
                {'car_capacity': 10, 'motor_capacity': 10, 'car_rate': 7000, 'motor_rate': 2000, 'ev_capacity': 0, 'ev_rate': 12000},
                token=self.pengelola_a,
            )

        # Cancel booking frees slot immediately.
        self.s.dispatch(
            'POST', '/api/ev/cancel',
            {'booking_id': booked['booking']['id'], 'operation_key': uid('op')},
            customer_key=self.ckey,
        )
        self.assertEqual(self.s.dispatch('GET', '/api/capacity')['ev']['available'], 1)

    def test_time_gated_promos_and_wallet_discount(self):
        # Pengelola A creates an active promo & a future (not yet valid) promo.
        active_p = self.s.dispatch(
            'POST', '/api/admin/promos',
            {
                'title': 'Flash Diskon 50%',
                'description': 'Berlaku 2 jam',
                'code': 'FLASH50',
                'discount_type': 'PERCENT',
                'discount_value': 50,
                'starts_at': self.now - 60,
                'ends_at': self.now + 7200,
                'active': True,
                'operation_key': uid('op'),
            },
            token=self.pengelola_a,
        )['promo']
        future_p = self.s.dispatch(
            'POST', '/api/admin/promos',
            {
                'title': 'Promo Besok',
                'description': 'Belum mulai',
                'code': 'BESOK',
                'discount_type': 'FIXED',
                'discount_value': 3000,
                'starts_at': self.now + 86400,
                'ends_at': self.now + 172800,
                'active': True,
                'operation_key': uid('op'),
            },
            token=self.pengelola_a,
        )['promo']

        # Public GET /api/promos shows only currently active time-gated promos.
        pub_ids = [p['id'] for p in self.s.dispatch('GET', '/api/promos')['promos']]
        self.assertIn(active_p['id'], pub_ids)
        self.assertNotIn(future_p['id'], pub_ids)

        # Pengelola B cannot edit Pengelola A's promo.
        with self.assertRaises(RuleError):
            self.s.dispatch(
                'POST', '/api/admin/promos',
                {
                    'id': active_p['id'],
                    'title': 'Hijack',
                    'discount_type': 'PERCENT',
                    'discount_value': 90,
                    'starts_at': self.now - 60,
                    'ends_at': self.now + 7200,
                    'active': True,
                    'operation_key': uid('op'),
                },
                token=self.pengelola_b,
            )

        # Customer tops up 10,000 and pays a 7,000 car bill with 50% promo -> pays 3,500!
        self.s.dispatch('POST', '/api/wallet/topup', {'amount': 10000, 'operation_key': uid('op')}, customer_key=self.ckey)
        sess = self.s.dispatch(
            'POST', '/api/officer/entry',
            {'plate': 'B777PRM', 'vehicle_type': 'MOBIL', 'verified': True, 'image_source': 'manual', 'operation_key': uid('op')},
            token=self.petugas_a,
        )['session']
        inv = self.s.dispatch('POST', '/api/officer/manual-quote', {'session_id': sess['id']}, token=self.petugas_a)['invoice']
        paid = self.s.dispatch(
            'POST', '/api/wallet/pay',
            {'invoice_id': inv['id'], 'promo_id': active_p['id'], 'operation_key': uid('op')},
            customer_key=self.ckey,
        )
        self.assertEqual(paid['discount'], 3500)
        self.assertEqual(paid['payable'], 3500)
        self.assertEqual(paid['balance'], 6500)


if __name__ == '__main__':
    unittest.main()
