import concurrent.futures
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from server.store import Store,uid
from server.rules import RuleError,charge,plate

class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'q.db';self.now=1800000000.0
        self.store=Store(self.path,lambda:self.now)
        self.store.add_officer('operator_uji','Testing123!')
        self.token=self.call('login',username='operator_uji',password='Testing123!')['token']
    def call(self,path,**data):
        return self.store.dispatch('POST','/api/'+path,data,self.token if hasattr(self,'token') else '')
    def get(self,path):return self.store.dispatch('GET','/api/'+path,token=self.token)
    def enter(self,p='B123AB',key=None):
        return self.call('officer/entry',plate=p,verified=True,image_readable=True,image_source='test_photo',operation_key=key or uid('op'))['session']
    def invoice(self,s):return self.call('invoice',session_id=s['id'])['invoice']
    def pay(self,i,outcome='SUCCESS',key=None):
        return self.call('payment',invoice_id=i['id'],outcome=outcome,operation_key=key or uid('op'))
    def paid(self):
        s=self.enter();return self.pay(self.invoice(s))['session']
    def authorize(self,s,key=None):
        return self.call('officer/authorize',qr=s['exit_qr'],plate=s['plate'],verified=True,operation_key=key or uid('op'))['session']
    def finish(self,s,path='complete',key=None):
        return self.call('officer/'+path,session_id=s['id'],authorization_id=s['authorization']['id'],passed=True,operation_key=key or uid('op'))['session']
    def rows(self,table):
        with self.store.connection() as db:return [dict(r) for r in db.execute('SELECT * FROM '+table)]
    def test_AT02_11_rules(self):
        self.assertEqual(plate('b 123 ab'),'B123AB')
        for bad in ('','  ','B-123','中文'):
            with self.assertRaises(RuleError):plate(bad)
        for seconds,total in [(0,7000),(1800,7000),(4200,7000),(6000,7000),(7199,7000),(7200,14000),(10799,14000)]:self.assertEqual(charge(seconds)[1],total)
        with self.assertRaises(RuleError):charge(-1)
    def test_AT03_06_10_ticket_retry(self):
        self.assertIsNone(self.get('ticket?plate=B123AB')['session'])
        key=uid('op');s=self.enter(key=key)
        self.assertEqual(s['id'],self.enter(key=key)['id'])
        self.assertEqual(s['id'],self.get('ticket?plate=b%20123%20ab')['session']['id'])
        with self.assertRaises(RuleError):self.enter()
        self.assertEqual(self.get('capacity')['occupied'],1)
    def test_AT04_05_28_auth(self):
        with self.assertRaises(RuleError):self.call('login',username='operator_uji',password='bad')
        for p in ('/api/officer/monitor','/api/officer/entry'):
            with self.assertRaises(RuleError):self.store.dispatch('GET' if 'monitor' in p else 'POST',p,{})
        self.call('logout')
        with self.assertRaises(RuleError):self.get('officer/monitor')
    def test_AT07_verification(self):
        for extra in ({'verified':False},{'image_readable':False},{'image_source':'missing'}):
            d=dict(plate='B123AB',verified=True,image_readable=True,image_source='test_photo',operation_key=uid('op'));d.update(extra)
            with self.assertRaises(RuleError):self.call('officer/entry',**d)
        self.assertEqual(self.get('capacity')['occupied'],0)
    def test_AT08_full(self):
        for n in range(20):self.enter('B'+str(n))
        with self.assertRaises(RuleError):self.enter('B21')
        self.assertEqual(self.get('capacity')['available'],0)
    def test_AT09_100_last_slot_races(self):
        for n in range(19):self.enter('A'+str(n))
        def attempt(p):
            try:return self.enter(p)
            except RuleError:return None
        for n in range(100):
            with concurrent.futures.ThreadPoolExecutor(2) as ex:
                results=list(ex.map(attempt,[f'B{n}',f'C{n}']))
            self.assertEqual(sum(x is not None for x in results),1)
            self.assertEqual(self.get('capacity')['occupied'],20)
            winner=next(x for x in results if x)
            paid=self.pay(self.invoice(winner))['session'];self.finish(self.authorize(paid))
            self.assertEqual(self.get('capacity')['available'],1)
    def test_AT12_13_snapshot(self):
        s=self.enter();self.now+=7140;i=self.invoice(s);self.now+=120
        self.assertEqual(self.pay(i)['session']['amount_paid'],7000)
        s2=self.enter('B234AB');i2=self.invoice(s2);self.now+=300
        with self.assertRaises(RuleError):self.pay(i2)
        self.assertNotEqual(self.invoice(s2)['id'],i2['id'])
    def test_AT14_concurrent_invoice(self):
        s=self.enter()
        with concurrent.futures.ThreadPoolExecutor(10) as ex:res=list(ex.map(lambda _:self.invoice(s),range(10)))
        self.assertEqual(len({i['id'] for i in res}),1)
    def test_AT15_attempts(self):
        s=self.enter();i=self.invoice(s)
        for outcome in ('PENDING','FAILED'):
            r=self.pay(i,outcome);self.assertIsNone(r['session']['window'])
        r=self.pay(i);self.assertEqual(r['session']['window']['deadline'],self.now+900)
    def test_AT16_100_parallel_pay_retries(self):
        s=self.enter();i=self.invoice(s)
        with concurrent.futures.ThreadPoolExecutor(10) as ex:res=list(ex.map(lambda _:self.pay(i),range(100)))
        self.assertEqual(len({r['attempt_id'] for r in res}),1)
        self.assertEqual(len(self.rows('windows')),1)
        deadline=res[0]['session']['window']['deadline'];self.now+=60
        self.assertEqual(self.pay(i)['session']['window']['deadline'],deadline)
    def test_AT17_18_20_penalty_rotation(self):
        s=self.paid();old=s['exit_qr'];self.now+=901
        for _ in range(10):self.get('ticket?plate=B123AB')
        p=self.invoice(s);self.assertEqual(p['amount'],7000)
        self.now+=5000;self.assertEqual(self.invoice(s)['id'],p['id'])
        new=self.pay(p)['session'];self.assertEqual(new['window']['deadline'],self.now+900)
        self.assertNotEqual(new['exit_qr'],old)
        with self.assertRaisesRegex(RuleError,'versi lama'):self.call('officer/scan',qr=old)
        self.now+=901;self.assertNotEqual(self.invoice(new)['id'],p['id'])
        self.assertEqual(len([i for i in self.rows('invoices') if i['kind']=='PENALTY']),2)
    def test_AT21_wrong_plate(self):
        s=self.paid()
        with self.assertRaises(RuleError):self.call('officer/authorize',qr=s['exit_qr'],plate='B9999',verified=True,operation_key=uid('op'))
        with self.assertRaises(RuleError):self.call('officer/authorize',qr=s['exit_qr'],plate=s['plate'],verified=False,operation_key=uid('op'))
    def test_AT22_deadline_boundaries(self):
        for n,offset in enumerate((-1,0,1)):
            s=self.enter('D'+str(n));s=self.pay(self.invoice(s))['session'];self.now=s['window']['deadline']+offset
            if offset>0:
                with self.assertRaises(RuleError):self.authorize(s)
            else:self.assertEqual(self.authorize(s)['state'],'EXIT_AUTHORIZED')
    def test_AT23_24_complete_once(self):
        s=self.authorize(self.paid());self.assertEqual(self.get('capacity')['occupied'],1)
        self.now+=119;key=uid('op');done=self.finish(s,key=key)
        self.assertEqual(done['state'],'COMPLETED');self.assertIsNone(done['exit_qr'])
        self.finish(s,key=key);self.finish(s)
        self.assertEqual(self.get('capacity')['available'],20)
        with self.assertRaisesRegex(RuleError,'selesai'):self.call('officer/scan',qr=s['exit_qr'])
    def test_AT25_authorization_boundary(self):
        s=self.paid();self.now=s['window']['deadline'];a=self.authorize(s);self.now+=120
        with self.assertRaises(RuleError):self.finish(a)
        current=self.get('ticket?plate=B123AB')['session'];self.assertEqual(current['state'],'IN_AREA')
        self.assertEqual(self.get('capacity')['occupied'],1)
        self.assertEqual(len([i for i in current['invoices'] if i['kind']=='PENALTY']),1)
    def test_AT25_cancel(self):
        a=self.authorize(self.paid());self.finish(a,'cancel')
        self.assertEqual(self.get('capacity')['occupied'],1)
        self.assertEqual(self.get('ticket?plate=B123AB')['session']['state'],'IN_AREA')
    def test_AT26_parallel_authorize(self):
        s=self.paid()
        with concurrent.futures.ThreadPoolExecutor(10) as ex:res=list(ex.map(lambda _:self.authorize(s),range(10)))
        self.assertEqual(len({r['authorization']['id'] for r in res}),1)
    def test_AT27_invalid_tokens(self):
        s=self.enter();self.assertIsNone(s['exit_qr'])
        for token in ('random','QPP.invoice','QPX.unknown'):
            with self.assertRaises(RuleError):self.call('officer/scan',qr=token)
        paid=self.pay(self.invoice(s))['session'];self.now+=901
        with self.assertRaisesRegex(RuleError,'habis'):self.call('officer/scan',qr=paid['exit_qr'])
    def test_AT31_audit_no_secret(self):
        s=self.paid();self.finish(self.authorize(s));self.call('logout')
        audit=json.dumps(self.rows('audit'))
        for forbidden in (self.token,s['exit_qr'],'Testing123!'):self.assertNotIn(forbidden,audit)
        for event in ('ENTRY','LOGIN','LOGOUT','INVOICE_CREATED','PAYMENT_SUCCESS','AUTHORIZE','EXIT'):self.assertIn(event,audit)
    def test_AT34_restart_restore(self):
        s=self.paid();snapshot=Path(self.tmp.name)/'backup.db'
        with self.store.connection() as source:
            target=sqlite3.connect(snapshot);source.backup(target);target.close()
        restarted=Store(self.path,lambda:self.now);restored=Store(snapshot,lambda:self.now)
        for store in (restarted,restored):
            r=store.dispatch('GET','/api/ticket?plate=B123AB')['session']
            self.assertEqual(r['id'],s['id']);self.assertEqual(r['exit_qr'],s['exit_qr'])
    def test_AT39_server_session_max8h(self):
        self.now+=8*3600
        with self.assertRaises(RuleError):self.get('officer/monitor')
    def test_AT40_authorized_past_deadline(self):
        s=self.paid();self.now=s['window']['deadline'];a=self.authorize(s);self.now+=119
        done=self.finish(a);self.assertEqual(done['amount_paid'],7000)
        self.assertFalse(any(i['kind']=='PENALTY' for i in done['invoices']))
    def test_simulator_can_be_disabled(self):
        s=self.enter();i=self.invoice(s);self.store.simulation=False
        with self.assertRaisesRegex(RuleError,'dinonaktifkan'):self.pay(i)
        self.assertEqual(len(self.rows('windows')),0)
    def test_idempotency_payload_collision(self):
        key=uid('op');self.enter(key=key)
        with self.assertRaisesRegex(RuleError,'permintaan berbeda'):self.enter('OTHER',key=key)

if __name__=='__main__':unittest.main()
