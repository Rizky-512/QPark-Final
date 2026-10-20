"""Independent HTTP clients exercise the public boundary (not shared local storage)."""
import concurrent.futures
import json
import statistics
import tempfile
import threading
import time
import unittest
from pathlib import Path
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from server.app import create_server
from server.store import Store,uid

class HTTPTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.store=Store(Path(self.tmp.name)/'db.sqlite')
        self.store.add_officer('operator_uji','Testing123!')
        self.server=create_server(self.store,port=0,directory=Path(self.tmp.name))
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.addCleanup(self.server.server_close);self.addCleanup(self.server.shutdown)
        self.url='http://127.0.0.1:'+str(self.server.server_port)
        self.token=self.request('POST','/api/login',{'username':'operator_uji','password':'Testing123!'})[1]['token']
    def request(self,method,path,data=None,token=None):
        req=Request(self.url+path,data=json.dumps(data).encode() if data is not None else None,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
        try:
            with urlopen(req,timeout=10) as r:return r.status,json.load(r)
        except HTTPError as e:return e.code,json.load(e)
    def enter(self,p):return self.request('POST','/api/officer/entry',{'plate':p,'verified':True,'image_readable':True,'image_source':'test_photo','operation_key':uid('op')},self.token)[1]['session']
    def test_two_independent_clients_and_auth(self):
        self.assertEqual(self.request('GET','/api/officer/monitor')[0],401)
        s=self.enter('B123AB')
        a=self.request('GET','/api/ticket?plate=B123AB')[1]['session']
        b=self.request('GET','/api/ticket?plate=B123AB')[1]['session']
        self.assertEqual(a['id'],b['id'])
        i=self.request('POST','/api/invoice',{'session_id':s['id']})[1]['invoice']
        body={'invoice_id':i['id'],'outcome':'SUCCESS','operation_key':uid('op')}
        first=self.request('POST','/api/payment',body)[1]
        # Simulate response lost: client retries the exact operation.
        second=self.request('POST','/api/payment',body)[1]
        self.assertEqual(first['attempt_id'],second['attempt_id'])
        a=self.request('GET','/api/ticket?plate=B123AB')[1]['session']
        self.assertEqual(a['payment_status'],'Lunas')
        self.assertEqual(first['session']['window']['deadline'],a['window']['deadline'])
        self.assertEqual(self.request('POST','/api/payment',{'invoice_id':'missing','outcome':'SUCCESS','operation_key':uid('op')})[0],404)
        self.request('POST','/api/logout',{},self.token)
        self.assertEqual(self.request('GET','/api/officer/monitor',token=self.token)[0],401)
    def test_100_mutations_10_clients_20_sessions(self):
        sessions=[self.enter('P'+str(i)) for i in range(20)]
        invoices=[self.request('POST','/api/invoice',{'session_id':s['id']})[1]['invoice'] for s in sessions]
        durations=[];visible=[]
        def task(n):
            i=invoices[n%20];s=sessions[n%20]
            start=time.perf_counter()
            status,result=self.request('POST','/api/payment',{'invoice_id':i['id'],'outcome':'FAILED','operation_key':uid('op')})
            elapsed=time.perf_counter()-start
            assert status==200
            check=self.request('GET','/api/ticket?plate='+s['plate'])[1]['session']
            assert check['id']==s['id']
            return elapsed,time.perf_counter()-start
        with concurrent.futures.ThreadPoolExecutor(10) as ex:
            for elapsed,seen in ex.map(task,range(100)):durations.append(elapsed);visible.append(seen)
        p95=sorted(durations)[94]
        # HTTP visibility measurement does not replace GUI polling/UAT evidence.
        self.assertLessEqual(p95,2)
        self.assertGreaterEqual(sum(t<=3 for t in visible),95)
        print('\nHTTP profile:',json.dumps({'clients':10,'sessions':20,'mutations':100,'p95_seconds':round(p95,4),'read_after_commit_within3s':sum(t<=3 for t in visible)}))
        self.assertEqual(self.request('GET','/api/capacity')[1]['occupied'],20)
    def test_malformed_requests(self):
        self.assertEqual(self.request('POST','/api/login',[])[0],400)
        self.assertEqual(self.request('POST','/api/login',{'username':[],'password':1})[0],401)
        self.assertEqual(self.request('GET','/api/missing')[0],404)

if __name__=='__main__':unittest.main()
