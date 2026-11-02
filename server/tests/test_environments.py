import json
from pathlib import Path
import tempfile
import unittest
import http.client
import threading
from scripts.environment_config import read_profile
from server.store import Store
from server.app import create_server


class EnvironmentTest(unittest.TestCase):
    def test_http_rejects_mismatched_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            server = create_server(Store(Path(directory)/'test.db', environment='test'), port=0)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port)
            try:
                connection.request('GET', '/api/health', headers={'X-QPark-Environment': 'demo'})
                response = connection.getresponse()
                self.assertEqual(response.status, 409)
                response.read()
                connection.request('GET', '/api/health', headers={'X-QPark-Environment': 'test'})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read())['environment'], 'test')
            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_database_cannot_be_opened_as_other_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'demo.db'
            Store(path)
            with self.assertRaises(ValueError):
                Store(path, environment='test')
            test = Store(Path(directory)/'test.db', environment='test')
            self.assertEqual(test.dispatch('GET','/api/health')['environment'],'test')

    def test_cloud_test_requires_different_demo_project(self):
        with tempfile.TemporaryDirectory() as directory:
            demo, test = Path(directory)/'demo.json', Path(directory)/'test.json'
            demo.write_text(json.dumps({'QPARK_ENV':'demo','SUPABASE_URL':'https://demo.supabase.co'}))
            values = {'QPARK_ENV':'test','SUPABASE_URL':'https://demo.supabase.co','SUPABASE_PUBLISHABLE_KEY':'public-test-key'}
            test.write_text(json.dumps(values))
            with self.assertRaises(ValueError): read_profile(test,'test')
            with self.assertRaises(ValueError): read_profile(test,'test',demo)
            values['SUPABASE_URL']='https://test.supabase.co'
            test.write_text(json.dumps(values))
            self.assertEqual(read_profile(test,'test',demo)['QPARK_ENV'],'test')
