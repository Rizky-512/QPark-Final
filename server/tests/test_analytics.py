import json
import tempfile
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path
from server.store import Store, uid
from server.rules import RuleError

WIB=timezone(timedelta(hours=7))
def ts(day,hour=0,minute=0):
    return datetime(2026,10,day,hour,minute,tzinfo=WIB).timestamp()

class AnalyticsTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.now=ts(15,12);self.s=Store(Path(self.tmp.name)/'test.db',lambda:self.now)
        self.admin=self.s.dispatch('POST','/api/login',{'username':'admin','password':'admin123'})['token']
        self.officer=self.s.dispatch('POST','/api/login',{'username':'petugas','password':'petugas123'})['token']
        with self.s.connection() as db:
            db.execute('UPDATE migrations SET applied_at=?',(ts(10),))
            self.actor=db.execute("SELECT id FROM officers WHERE username='admin'").fetchone()[0]
    def session(self,enter,exit=None,kind='MOBIL',state=None):
        sid=uid('QP')
        with self.s.connection() as db:
            db.execute('INSERT INTO sessions(id,plate,entered_at,entered_by,state,exited_at,vehicle_type,hourly_rate) VALUES(?,?,?,?,?,?,?,7000)',(sid,sid,enter,self.actor,state or ('COMPLETED' if exit is not None else 'IN_AREA'),exit,kind))
        return sid
    def report(self,start='2026-10-14',end='2026-10-14',token=None):
        return self.s.dispatch('GET',f'/api/admin/analytics?from={start}&to={end}',token=self.admin if token is None else token)
    def test_access_admin_only(self):
        for token,status in [('',401),(self.officer,403)]:
            with self.assertRaises(RuleError) as cm:self.report(token=token)
            self.assertEqual(cm.exception.status,status)
    def test_known_arrivals_durations_occupancy(self):
        self.session(ts(14,8),ts(14,9));self.session(ts(14,8,30),ts(14,10,30),'MOTOR')
        self.session(ts(13,23),ts(14,1));self.session(ts(14,20))
        r=self.report()
        self.assertEqual((r['arrivals'],r['completed_count'],r['excluded_active_count']),(3,2,1))
        self.assertEqual((r['mean_minutes'],r['median_minutes']),(90,90))
        self.assertEqual(r['vehicles'],{'MOBIL':2,'MOTOR':1})
        self.assertAlmostEqual(r['occupancy_pct'],8/24/20*100,places=3)
        self.assertEqual(r['hourly'][8]['arrivals'],2)
        self.assertEqual(r['peak_occupied'],2)
        self.assertEqual(r['busiest']['day'],2)
    def test_capacity_changes_are_time_weighted(self):
        self.session(ts(14),ts(15))
        with self.s.connection() as db:
            self.s.audit(db,'SETTINGS_CHANGED','parking',self.actor,ts(14,12),json.dumps({'capacity':10}))
            db.execute("UPDATE metadata SET value=? WHERE key='parking_settings'",(json.dumps({'capacity':10,'car_rate':7000,'motor_rate':2000}),))
        self.assertEqual(self.report()['occupancy_pct'],7.5)
    def test_payments_use_paid_time_and_ignore_unpaid(self):
        sid=self.session(ts(13),ts(14,2))
        with self.s.connection() as db:
            for state,kind,method,paid in [('PAID','BASE','MANUAL',ts(14,1)),('PAID','PENALTY','QR_SIMULASI',ts(14,2)),('EXPIRED','PENALTY','QR_SIMULASI',None),('PAID','PENALTY','MANUAL',ts(15,1))]:
                db.execute('INSERT INTO invoices(id,session_id,kind,amount,hours,duration,issued_at,state,paid_at,payment_method) VALUES(?,?,?,7000,1,1,?,?,?,?)',(uid('INV'),sid,kind,ts(13),state,paid,method))
        r=self.report()
        self.assertEqual(r['arrivals'],0)
        self.assertEqual(r['payments'],{'QR_SIMULASI':{'count':1,'amount':7000},'MANUAL':{'count':1,'amount':7000}})
    def test_empty_and_unobserved(self):
        r=self.report();self.assertEqual(r['occupancy_pct'],0);self.assertIsNone(r['mean_minutes']);self.assertIsNone(r['busiest'])
        r=self.report('2026-10-01','2026-10-02');self.assertIsNone(r['occupancy_pct']);self.assertTrue(all(x['occupancy_pct'] is None for x in r['daily']))
    def test_partial_day_and_overnight(self):
        self.session(ts(14,23),ts(15,2))
        r=self.report('2026-10-15','2026-10-15')
        self.assertEqual(r['daily'][0]['observed_hours'],12)
        self.assertAlmostEqual(r['occupancy_pct'],2/12/20*100,places=3)
        self.assertIsNone(r['hourly'][12]['occupancy_pct'])
    def test_mean_median_differ_and_zero_duration_valid(self):
        for i,minutes in enumerate([0,30,180]):self.session(ts(14,8+i),ts(14,8+i)+minutes*60)
        r=self.report();self.assertEqual((r['mean_minutes'],r['median_minutes']),(70,30))
    def test_invalid_periods(self):
        for a,b in [('bad','2026-10-14'),('2026-10-15','2026-10-14'),('2026-10-14','2026-10-16'),('2020-01-01','2026-10-15')]:
            with self.assertRaises(RuleError) as cm:self.report(a,b)
            self.assertEqual(cm.exception.status,400)
    def test_authorized_exit_still_occupies(self):
        self.session(ts(14),state='EXIT_AUTHORIZED')
        self.assertEqual(self.report()['occupancy_pct'],5)
