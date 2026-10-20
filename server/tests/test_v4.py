import concurrent.futures
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from server.store import Store,uid,password_hash
from server.rules import RuleError

class RevisionTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'v4.db';self.now=1800000000.0
        self.s=Store(self.path,lambda:self.now)
        self.admin=self.post('login',username='admin',password='admin123')['token']
        self.officer=self.post('login',username='petugas',password='petugas123')['token']
    def post(self,path,token='',**data):return self.s.dispatch('POST','/api/'+path,data,token)
    def get(self,path,token=''):return self.s.dispatch('GET','/api/'+path,token=token)
    def enter(self,p='B123',kind='MOTOR'):
        return self.post('officer/entry',self.officer,plate=p,vehicle_type=kind,verified=True,image_readable=True,image_source='test_photo',operation_key=uid('op'))['session']
    def quote(self,s):return self.post('officer/manual-quote',self.officer,session_id=s['id'])['invoice']
    def manual_data(self,s,i):return dict(session_id=s['id'],invoice_id=i['id'] if i else None,expected_amount=i['amount'] if i else 0,received=10000 if i else 0,verified=True,plate=s['plate'],operation_key=uid('op'))
    def complete(self,s):return self.post('officer/complete',self.officer,session_id=s['id'],authorization_id=s['authorization']['id'],passed=True,operation_key=uid('op'))['session']
    def test_defaults_and_role_authorization(self):
        self.assertEqual(self.post('login',username='admin',password='admin123')['role'],'ADMIN')
        self.assertEqual(self.post('login',username='petugas',password='petugas123')['role'],'PETUGAS')
        for token in ['',self.officer]:
            with self.assertRaises(RuleError):self.get('admin/settings',token)
            with self.assertRaises(RuleError):self.post('admin/users',token,username='oops',password='password',operation_key=uid('op'))
        self.assertEqual(len(self.get('admin/users',self.admin)['users']),2)
    def test_manual_entry_without_camera(self):
        d=dict(plate='MANUAL1',vehicle_type='MOTOR',verified=True,image_source='manual',operation_key=uid('op'))
        self.assertEqual(self.post('officer/entry',self.officer,**d)['session']['vehicle_type'],'MOTOR')
        d.update(plate='MANUAL2',verified=False,operation_key=uid('op'))
        with self.assertRaises(RuleError):self.post('officer/entry',self.officer,**d)
    def test_motor_manual_receipt_and_complete(self):
        s=self.enter();i=self.quote(s);self.assertEqual(i['amount'],2000)
        d=self.manual_data(s,i);r=self.post('officer/manual-pay',self.officer,**d)['session']
        self.assertEqual(r['state'],'EXIT_AUTHORIZED');self.assertEqual(self.get('capacity')['occupied'],1)
        receipt=next(x for x in r['invoices'] if x['state']=='PAID')
        self.assertEqual((receipt['payment_method'],receipt['received'],receipt['change_amount']),('MANUAL',10000,8000))
        replay=self.post('officer/manual-pay',self.officer,**d)['session']
        self.assertEqual(replay['authorization']['id'],r['authorization']['id'])
        self.complete(r);self.assertEqual(self.get('capacity')['available'],20)
        h=self.get('history?plate=B123')['sessions'][0]
        self.assertEqual(h['state'],'COMPLETED');self.assertIsNone(h['exit_qr'])
    def test_insufficient_cash_verification_and_unauthorized(self):
        s=self.enter();i=self.quote(s)
        for changes in [{'received':1000},{'verified':False},{'plate':'WRONG'},{'expected_amount':1}]:
            d=self.manual_data(s,i);d.update(changes)
            with self.assertRaises(RuleError):self.post('officer/manual-pay',self.officer,**d)
        with self.assertRaises(RuleError):self.post('officer/manual-pay',**self.manual_data(s,i))
        self.assertEqual(self.get('ticket?plate=B123')['session']['amount_paid'],0)
    def test_qr_and_manual_race_one_payment(self):
        s=self.enter();i=self.quote(s)
        def manual():
            try:return self.post('officer/manual-pay',self.officer,**self.manual_data(s,i))
            except RuleError:return None
        def qr():return self.post('payment',invoice_id=i['id'],outcome='SUCCESS',operation_key=uid('op'))
        with concurrent.futures.ThreadPoolExecutor(2) as ex:
            results=[ex.submit(manual),ex.submit(qr)]
            for f in results:f.result()
        with self.s.connection() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM attempts WHERE outcome='SUCCESS'").fetchone()[0],1)
            self.assertEqual(db.execute('SELECT count(*) FROM windows').fetchone()[0],1)
        self.assertEqual(self.get('ticket?plate=B123')['session']['amount_paid'],2000)
    def test_qr_paid_manual_gate_no_second_charge(self):
        s=self.enter();i=self.quote(s);self.post('payment',invoice_id=i['id'],outcome='SUCCESS',operation_key=uid('op'))
        with self.assertRaises(RuleError):self.post('officer/manual-pay',self.officer,**self.manual_data(s,i))
        self.assertIsNone(self.quote(s));r=self.post('officer/manual-pay',self.officer,**self.manual_data(s,None))['session']
        self.assertEqual(r['amount_paid'],2000);self.complete(r)
        self.assertEqual(self.get('officer/history?method=MANUAL',self.officer)['total'],0)
    def test_penalty_uses_vehicle_snapshot_after_settings_change(self):
        motor=self.enter();car=self.enter('B456','MOBIL')
        self.post('admin/settings',self.admin,capacity=20,car_rate=8000,motor_rate=3000)
        self.assertEqual(self.quote(car)['amount'],7000)
        i=self.quote(motor);p=self.post('payment',invoice_id=i['id'],outcome='SUCCESS',operation_key=uid('op'))['session']
        self.now=p['window']['deadline']+1;i=self.quote(motor);self.assertEqual(i['amount'],2000)
        r=self.post('officer/manual-pay',self.officer,**self.manual_data(motor,i))['session'];self.assertEqual(r['amount_paid'],4000)
        newer=self.enter('B789');self.assertEqual(newer['hourly_rate'],3000)
        with self.assertRaises(RuleError):self.post('admin/settings',self.admin,capacity=1,car_rate=8000,motor_rate=3000)
    def test_history_scopes_filters_and_pagination(self):
        a=self.enter();i=self.quote(a);r=self.post('officer/manual-pay',self.officer,**self.manual_data(a,i))['session'];self.complete(r)
        self.enter('OTHER','MOBIL')
        self.assertEqual(self.get('history?plate=B123')['total'],1)
        self.assertEqual(self.get('officer/history',self.admin)['total'],2)
        self.assertEqual(self.get('officer/history?vehicle=MOTOR&method=MANUAL',self.officer)['revenue'],2000)
        self.assertEqual(self.get('officer/history?offset=50',self.officer)['sessions'],[])
        self.assertEqual(self.get('officer/history?from=2000-01-01&to=2000-01-02',self.officer)['total'],0)
        for path in ['history','officer/history','history?plate=']:
            with self.assertRaises(RuleError):self.get(path)
    def test_account_edit_revokes_and_does_not_reset_on_restart(self):
        self.post('admin/users',self.admin,username='petugas',password='newpass123',role='PETUGAS',active=True,operation_key=uid('op'))
        with self.assertRaises(RuleError):self.get('officer/history',self.officer)
        self.s=Store(self.path,lambda:self.now)
        with self.assertRaises(RuleError):self.post('login',username='petugas',password='petugas123')
        self.assertEqual(self.post('login',username='petugas',password='newpass123')['role'],'PETUGAS')
        with self.assertRaises(RuleError):self.post('admin/users',self.admin,username='admin',password='',role='PETUGAS',active=True,operation_key=uid('op'))
    def test_migrates_v3_without_losing_sessions(self):
        path=Path(self.tmp.name)/'old.db'
        db=sqlite3.connect(path);db.executescript(Path('server/schema.sql').read_text())
        db.execute('INSERT INTO migrations VALUES(1,?)',(self.now,))
        db.execute('INSERT INTO officers VALUES(?,?,?,?,1)',('old','petugas',password_hash('random123','00'*16),'00'*16))
        db.execute("INSERT INTO sessions VALUES('original','OLD123',?,'old','IN_AREA',NULL,NULL)",(self.now,));db.commit();db.close()
        migrated=Store(path,lambda:self.now)
        s=migrated.dispatch('GET','/api/ticket?plate=OLD123')['session']
        self.assertEqual((s['id'],s['vehicle_type'],s['hourly_rate']),('original','MOBIL',7000))
        self.assertEqual(migrated.dispatch('POST','/api/login',{'username':'petugas','password':'petugas123'})['role'],'PETUGAS')
    def test_manual_supported_when_qr_simulator_disabled(self):
        self.s.simulation=False;s=self.enter();i=self.quote(s)
        r=self.post('officer/manual-pay',self.officer,**self.manual_data(s,i))['session']
        self.assertEqual(r['amount_paid'],2000)

if __name__=='__main__':unittest.main()
