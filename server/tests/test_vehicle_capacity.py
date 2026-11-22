import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from server.store import Store, uid
from server.rules import RuleError


class VehicleCapacityTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.store = Store(Path(temp.name)/'capacity.db')
        self.admin = self.store.dispatch('POST', '/api/login', {'username': 'admin', 'password': 'admin123'})['token']
        self.staff = self.store.dispatch('POST', '/api/login', {'username': 'petugas', 'password': 'petugas123'})['token']
        self.store.dispatch('POST', '/api/admin/settings', dict(car_capacity=1, motor_capacity=1, car_rate=7000, motor_rate=2000), self.admin)

    def entry(self, plate, kind):
        return self.store.dispatch('POST', '/api/officer/entry', dict(plate=plate, vehicle_type=kind, verified=True, image_source='manual', operation_key=uid('op')), self.staff, customer_key='')

    def test_each_category_has_its_own_last_slot_under_concurrency(self):
        def attempt(item):
            try:
                return self.entry(*item)['session']['vehicle_type']
            except RuleError as error:
                self.assertEqual(error.code, 'full')
                return None
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(attempt, [(f'R{i}', 'MOBIL' if i % 2 else 'MOTOR') for i in range(8)]))
        self.assertEqual(results.count('MOBIL'), 1)
        self.assertEqual(results.count('MOTOR'), 1)
        cap = self.store.dispatch('GET', '/api/capacity', customer_key='')
        self.assertEqual(cap['categories']['MOTOR']['available'], 0)
        self.assertEqual(cap['categories']['MOBIL']['available'], 0)

    def test_saved_category_automatic_and_cannot_change_while_parked(self):
        body = dict(plate='B123', vehicle_type='MOTOR')
        self.store.dispatch('POST', '/api/customer/vehicle-type', body, customer_key='a'*48)
        self.assertEqual(self.entry('B123', 'MOBIL')['session']['vehicle_type'], 'MOTOR')
        self.assertEqual(self.entry('B456', 'MOBIL')['session']['vehicle_type'], 'MOBIL')
        with self.assertRaises(RuleError):
            self.store.dispatch('POST', '/api/customer/vehicle-type', dict(plate='B123', vehicle_type='MOBIL'), customer_key='a'*48)
        with self.assertRaises(RuleError):
            self.store.dispatch('POST', '/api/admin/settings', dict(car_capacity=1, motor_capacity=0, car_rate=7000, motor_rate=2000), self.admin)
        other = self.store.dispatch('GET', '/api/customer/vehicle-types', customer_key='b'*48)
        self.assertEqual(other['vehicle_types'], {})

    def test_zero_capacity_closes_both_categories_without_breaking_analytics(self):
        self.store.dispatch('POST', '/api/admin/settings', dict(car_capacity=0, motor_capacity=0, car_rate=7000, motor_rate=2000), self.admin)
        now = self.store.clock()
        self.store.clock = lambda: now + 60
        self.assertTrue(self.store.dispatch('GET', '/api/capacity')['full'])
        self.store.dispatch('GET', '/api/admin/analytics', token=self.admin)
        with self.assertRaises(RuleError):
            self.entry('CLOSED1', 'MOTOR')
