import concurrent.futures
import unittest
from server.tests import test_http
from server.store import uid


class CustomerAccessTest(unittest.TestCase):
    setUp = test_http.HTTPTest.setUp
    request = test_http.HTTPTest.request
    enter = test_http.HTTPTest.enter

    def test_plate_is_not_a_credential_and_history_is_scoped(self):
        session = self.enter('PRIVATE1')
        invoice = self.request('POST', '/api/invoice', {'session_id': session['id']})[1]['invoice']
        self.customer_key = 'b' * 48
        self.assertIsNone(self.request('GET', '/api/ticket?plate=PRIVATE1')[1]['session'])
        self.assertEqual(self.request('GET', '/api/history?plate=PRIVATE1')[1]['total'], 0)
        for path, body in [('/api/invoice', {'session_id': session['id']}),
                           ('/api/payment', {'invoice_id': invoice['id'], 'outcome': 'SUCCESS', 'operation_key': uid('op')})]:
            self.assertEqual(self.request('POST', path, body)[0], 403)
        # Even a real staff token does not grant customer endpoints access.
        self.assertIsNone(self.request('GET', '/api/ticket?plate=PRIVATE1', token=self.token)[1]['session'])

    def test_cannot_rebind_or_link_without_staff_verification(self):
        self.enter('OWNED1')
        self.customer_key = 'b' * 48
        code = self.request('POST', '/api/customer/code', {'plate': 'OWNED1'})[1]['code']
        data = {'plate': 'OWNED1', 'code': code, 'verified': True}
        self.assertEqual(self.request('POST', '/api/officer/link', data)[0], 401)
        self.assertEqual(self.request('POST', '/api/officer/link', {**data, 'verified': False}, self.token)[0], 400)
        self.assertEqual(self.request('POST', '/api/officer/link', data, self.token)[0], 409)

    def test_missing_identity_and_expired_code(self):
        self.enter('EXPIRE1')
        code = self.request('POST', '/api/customer/code', {'plate': 'EXPIRE1'})[1]['code']
        with self.store.connection() as db:
            db.execute('UPDATE customer_codes SET expires_at=0')
        self.assertEqual(self.request('POST', '/api/officer/link', {'plate': 'EXPIRE1', 'code': code, 'verified': True}, self.token)[0], 400)
        self.customer_key = ''
        self.assertEqual(self.request('GET', '/api/history?plate=EXPIRE1')[0], 401)

    def test_final_slot_race_only_one_entry(self):
        self.store.dispatch('POST', '/api/admin/settings', {'capacity': 1, 'car_rate': 7000, 'motor_rate': 2000},
                            self.store.dispatch('POST', '/api/login', {'username': 'admin', 'password': 'admin123'})['token'])
        def enter(i):
            return self.request('POST', '/api/officer/entry', {
                'plate': 'RACE' + str(i), 'verified': True, 'image_source': 'manual',
                'operation_key': uid('op'),
            }, self.token)[0]
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            statuses = list(pool.map(enter, range(2)))
        self.assertEqual(statuses.count(200), 1)
        self.assertEqual(self.request('GET', '/api/capacity')[1]['occupied'], 1)

    def test_diagnostic_log_does_not_expose_credentials(self):
        with self.assertLogs('qpark.requests', level='INFO') as logs:
            self.request('GET', '/api/ticket?plate=SECRETPLATE')
        output = '\n'.join(logs.output)
        self.assertIn('elapsed_ms', output)
        self.assertNotIn('SECRETPLATE', output)
        self.assertNotIn(self.customer_key, output)
        self.assertNotIn(self.token, output)
