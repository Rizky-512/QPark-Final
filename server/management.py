"""Admin, history and manual checkout added to the existing QR workflow."""
import json
import secrets
from datetime import datetime, timezone, timedelta
from .rules import RuleError, plate, WINDOW_SECONDS, AUTH_SECONDS

class ManagementMixin:
    def migrate_v4(self, db):
        from .store import uid, password_hash
        db.execute('BEGIN IMMEDIATE')
        for table, columns in {
            'officers': {'role': "TEXT NOT NULL DEFAULT 'PETUGAS'"},
            'sessions': {'vehicle_type': "TEXT NOT NULL DEFAULT 'MOBIL'", 'hourly_rate': 'INTEGER NOT NULL DEFAULT 7000'},
            'invoices': {'payment_method': 'TEXT', 'received': 'INTEGER', 'change_amount': 'INTEGER', 'paid_by': 'TEXT'},
        }.items():
            present={x['name'] for x in db.execute('PRAGMA table_info('+table+')')}
            for name, definition in columns.items():
                if name not in present:db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')
        db.execute("INSERT OR IGNORE INTO metadata VALUES('parking_settings',?)",(json.dumps({'capacity':20,'car_rate':7000,'motor_rate':2000}),))
        # Explicit v4 demo-account reset, once only; preserves all parking transactions.
        if not db.execute('SELECT 1 FROM migrations WHERE version=2').fetchone():
            for username,password,role in [('admin','admin123','ADMIN'),('petugas','petugas123','PETUGAS')]:
                salt=secrets.token_hex(16);hashed=password_hash(password,salt)
                old=db.execute('SELECT id FROM officers WHERE username=?',(username,)).fetchone()
                if old:
                    db.execute('UPDATE officers SET password_hash=?,salt=?,active=1,role=? WHERE id=?',(hashed,salt,role,old['id']))
                    db.execute('UPDATE logins SET revoked=1 WHERE officer_id=?',(old['id'],))
                else:db.execute('INSERT INTO officers(id,username,password_hash,salt,active,role) VALUES(?,?,?,?,1,?)',(uid('OFF'),username,hashed,salt,role))
            db.execute("UPDATE invoices SET payment_method='QR_SIMULASI' WHERE state='PAID' AND payment_method IS NULL")
            db.execute('INSERT INTO migrations VALUES(2,?)',(self.clock(),))
        values=self.settings(db)
        if 'car_capacity' not in values:
            used={kind:db.execute("SELECT count(*) FROM sessions WHERE state!='COMPLETED' AND vehicle_type=?",(kind,)).fetchone()[0] for kind in ('MOBIL','MOTOR')}
            values['car_capacity']=max(used['MOBIL'],values['capacity']//2)
            values['motor_capacity']=max(used['MOTOR'],values['capacity']-values['car_capacity'])
            values['capacity']=values['car_capacity']+values['motor_capacity']
            db.execute("UPDATE metadata SET value=? WHERE key='parking_settings'",(json.dumps(values),))
        db.commit()

    def settings(self, db, location_id='LOC-DEFAULT'):
        import sqlite3
        try:
            row = db.execute('SELECT * FROM locations WHERE id=?', (location_id,)).fetchone()
        except sqlite3.OperationalError:
            row = None
        if row:
            return {
                'location_id': row['id'],
                'name': row['name'],
                'address': row['address'],
                'car_capacity': row['car_capacity'],
                'motor_capacity': row['motor_capacity'],
                'capacity': row['car_capacity'] + row['motor_capacity'],
                'car_rate': row['car_rate'],
                'motor_rate': row['motor_rate'],
            }
        return json.loads(db.execute("SELECT value FROM metadata WHERE key='parking_settings'").fetchone()[0])

    def settle(self, db, inv, outcome, key, actor, method, now, received=None):
        from .store import uid,digest
        aid=uid('PAY');sid=inv['session_id']
        db.execute('INSERT INTO attempts VALUES(?,?,?,?,?)',(aid,inv['id'],key,outcome,now))
        if outcome=='SUCCESS':
            db.execute("UPDATE invoices SET state='PAID',paid_at=?,payment_method=?,received=?,change_amount=?,paid_by=? WHERE id=?",(now,method,received,received-inv['amount'] if received is not None else None,actor,inv['id']))
            w=self._window(db,sid);seq=1 if not w else w['sequence']+1;wid=uid('WIN')
            db.execute('INSERT INTO windows VALUES(?,?,?,?,?,?,?)',(wid,sid,inv['id'],seq,now,now+WINDOW_SECONDS,digest(self.qr(wid))))
        self.audit(db,'PAYMENT_'+outcome,inv['id'],actor,now,method)
        return {'session_id':sid,'invoice_id':inv['id'],'outcome':outcome,'attempt_id':aid,'paid_at':now if outcome=='SUCCESS' else None}

    def history(self,db,query,now,public=False,owner=None,location_id=None):
        conditions=[];params=[]
        def arg(k,default=''):return query.get(k,[default])[0]
        if public:
            conditions.append('s.plate=?');params.append(plate(arg('plate')))
            if owner is not None:
                conditions.append('EXISTS(SELECT 1 FROM customer_links c WHERE c.session_id=s.id AND c.owner=?)');params.append(owner)
        elif arg('q'):
            conditions.append('instr(s.plate,?)>0');params.append(arg('q').upper().replace(' ',''))
        if location_id:
            conditions.append('s.location_id=?');params.append(location_id)
        if arg('vehicle'):
            if arg('vehicle') not in ('MOBIL','MOTOR'):raise RuleError('Jenis kendaraan tidak valid.','vehicle',400)
            conditions.append('s.vehicle_type=?');params.append(arg('vehicle'))
        if arg('method'):
            if arg('method') not in ('MANUAL','QR_SIMULASI','EWALLET'):raise RuleError('Metode tidak valid.','method',400)
            conditions.append("EXISTS(SELECT 1 FROM invoices i WHERE i.session_id=s.id AND i.payment_method=? AND i.state='PAID')");params.append(arg('method'))
        try:
            offset=max(0,int(arg('offset','0')))
            for key,op,extra in [('from','>=',0),('to','<',1)]:
                if arg(key):
                    dt=datetime.strptime(arg(key),'%Y-%m-%d').replace(tzinfo=timezone(timedelta(hours=7)))+timedelta(days=extra)
                    conditions.append('s.entered_at'+op+'?');params.append(dt.timestamp())
        except ValueError:raise RuleError('Tanggal atau halaman tidak valid.','filter',400)
        where=' WHERE '+' AND '.join(conditions) if conditions else ''
        total=db.execute('SELECT count(*) FROM sessions s'+where,params).fetchone()[0]
        rows=db.execute('SELECT s.id FROM sessions s'+where+' ORDER BY s.entered_at DESC,s.id DESC LIMIT 50 OFFSET ?',(*params,offset)).fetchall()
        revenue=db.execute("SELECT COALESCE(sum(i.amount),0) FROM invoices i WHERE i.state='PAID' AND i.session_id IN (SELECT s.id FROM sessions s"+where+')',params).fetchone()[0]
        return {'sessions':[self._view(db,x['id'],now,False) for x in rows],'total':total,'offset':offset,'revenue':revenue}

    def extra_dispatch(self,db,method,path,query,data,token,now):
        from .store import uid,password_hash
        from .locations_wallet import DEFAULT_LOCATION_ID, get_location
        if method=='GET' and path=='/api/history':return self.history(db,query,now,True)
        if path.startswith('/api/admin/'):
            officer=self._officer_row(db,token,now)
            actor=officer['id']
            if officer['role'] not in ('ADMIN','SUPERADMIN'):
                raise RuleError('Hanya pengelola atau superadmin yang dapat mengelola akun dan pengaturan.','forbidden',403)
            if method=='GET' and path=='/api/admin/analytics':
                from .analytics import parking_analytics
                loc_id=self._location_for_staff(officer, query.get('location_id',[''])[0] or None)
                return parking_analytics(self,db,query,now,location_id=loc_id)
            if path=='/api/admin/settings':
                req_loc=(query.get('location_id',[''])[0] or None) if method=='GET' else data.get('location_id')
                loc_id=self._location_for_staff(officer, req_loc)
                get_location(db, loc_id)
                if method=='GET':return {'settings':self.settings(db, loc_id)}
                if method=='POST':
                    values={k:data.get(k) for k in ('car_capacity','motor_capacity','car_rate','motor_rate')}
                    if any(type(v) is not int or v<(0 if k.endswith('capacity') else 1) or v>1000000 for k,v in values.items()):
                        raise RuleError('Isi kapasitas 0-1.000.000 dan tarif 1-1.000.000.', 'settings',400)
                    for kind,key in [('MOBIL','car_capacity'),('MOTOR','motor_capacity')]:
                        occupied=db.execute("SELECT count(*) FROM sessions WHERE state!='COMPLETED' AND vehicle_type=? AND location_id=?",(kind,loc_id)).fetchone()[0]
                        if values[key]<occupied:raise RuleError('Kapasitas '+kind+' tidak boleh di bawah jumlah kendaraan aktif.','capacity')
                    values['capacity']=values['car_capacity']+values['motor_capacity']
                    db.execute('UPDATE locations SET car_capacity=?,motor_capacity=?,car_rate=?,motor_rate=? WHERE id=?',
                               (values['car_capacity'],values['motor_capacity'],values['car_rate'],values['motor_rate'],loc_id))
                    if loc_id==DEFAULT_LOCATION_ID:
                        db.execute("UPDATE metadata SET value=? WHERE key='parking_settings'",(json.dumps(values),))
                    self.audit(db,'SETTINGS_CHANGED',loc_id,actor,now,json.dumps(values),location_id=loc_id)
                    return {'settings':self.settings(db, loc_id)}
            if path=='/api/admin/users':
                if method=='GET':
                    if officer['role']=='SUPERADMIN':
                        rows=db.execute('''SELECT o.id,o.username,o.role,o.active,o.location_id,l.name location_name
                                           FROM officers o LEFT JOIN locations l ON l.id=o.location_id ORDER BY o.username''').fetchall()
                    else:
                        loc_id=self._location_for_staff(officer)
                        rows=db.execute('''SELECT o.id,o.username,o.role,o.active,o.location_id,l.name location_name
                                           FROM officers o LEFT JOIN locations l ON l.id=o.location_id
                                           WHERE o.location_id=? AND o.role!='SUPERADMIN' ORDER BY o.username''',(loc_id,)).fetchall()
                    return {'users':[dict(x) for x in rows]}
                if method=='POST':
                    def update_user():
                        username=data.get('username','');password=data.get('password','');role=data.get('role','PETUGAS')
                        allowed_roles=('SUPERADMIN','ADMIN','PETUGAS') if officer['role']=='SUPERADMIN' else ('ADMIN','PETUGAS')
                        if not isinstance(username,str) or not username.strip() or len(username)>40 or role not in allowed_roles:
                            raise RuleError('Username atau peran tidak valid.','user',400)
                        if not isinstance(password,str) or (password and len(password)<8):
                            raise RuleError('Password minimum delapan karakter.','password',400)
                        target_loc=None if role=='SUPERADMIN' else self._location_for_staff(officer, data.get('location_id'))
                        if target_loc is not None:
                            get_location(db, target_loc)
                        old=db.execute('SELECT * FROM officers WHERE username=?',(username.strip().lower(),)).fetchone()
                        if old and officer['role']!='SUPERADMIN' and (old['role']=='SUPERADMIN' or old['location_id']!=officer['location_id']):
                            raise RuleError('Akun tersebut milik lokasi lain atau superadmin.','forbidden',403)
                        active=data.get('active',True)
                        if type(active) is not bool:raise RuleError('Status akun tidak valid.','user',400)
                        if old and old['id']==actor and (not active or role!=officer['role']):
                            raise RuleError('Pengelola tidak dapat menonaktifkan atau menurunkan perannya sendiri.','self_change')
                        if not old and not password:raise RuleError('Password akun baru wajib diisi.','password',400)
                        oid=old['id'] if old else uid('OFF')
                        if old:
                            db.execute('UPDATE officers SET role=?,active=?,location_id=? WHERE id=?',(role,int(active),target_loc,oid))
                        else:
                            db.execute('INSERT INTO officers(id,username,password_hash,salt,active,role,location_id) VALUES(?,?,?,?,?,?,?)',(oid,username.strip().lower(),'','',int(active),role,target_loc))
                        if password:
                            salt=secrets.token_hex(16);db.execute('UPDATE officers SET password_hash=?,salt=? WHERE id=?',(password_hash(password,salt),salt,oid))
                        if old and (password or not active or role!=old['role'] or target_loc!=old['location_id']):
                            db.execute('UPDATE logins SET revoked=1 WHERE officer_id=?',(oid,))
                        self.audit(db,'USER_UPDATED',oid,actor,now,role,location_id=target_loc)
                        return {'updated':True}
                    return self._operation(db,'user_update',data,actor,now,update_user)
        if path in ('/api/officer/history','/api/officer/manual-quote','/api/officer/manual-pay'):
            officer=self._officer_row(db,token,now)
            actor=officer['id']
            if method=='GET' and path=='/api/officer/history':
                req_loc=query.get('location_id',[''])[0] or None
                loc_id=None if (officer['role']=='SUPERADMIN' and not req_loc) else self._location_for_staff(officer, req_loc)
                return self.history(db,query,now,location_id=loc_id)
            if method=='POST' and path=='/api/officer/manual-quote':
                s=self._session(db,data.get('session_id'))
                self._check_session_location(officer, s)
                return self._dispatch(db,'POST','/api/invoice',data,token,now)
            if method=='POST' and path=='/api/officer/manual-pay':
                def pay_manual():
                    sid=data.get('session_id');s=self._session(db,sid)
                    self._check_session_location(officer, s)
                    if s['state']=='COMPLETED':raise RuleError('Kendaraan sudah keluar.','completed')
                    if data.get('verified') is not True or plate(data.get('plate'))!=s['plate']:raise RuleError('Cocokkan nopol dan verifikasi kendaraan.','verification',400)
                    inv=db.execute("SELECT * FROM invoices WHERE id=? AND session_id=?",(data.get('invoice_id'),sid)).fetchone() if data.get('invoice_id') else None
                    expected=data.get('expected_amount');received=data.get('received')
                    if type(expected) is not int or type(received) is not int or received<0 or received>1000000000:raise RuleError('Nominal uang tidak valid.','money',400)
                    if inv:
                        if inv['state']!='PENDING' or (inv['expires_at'] is not None and now>=inv['expires_at']):raise RuleError('Tagihan berubah, sudah dibayar, atau kedaluwarsa. Muat ulang sebelum menerima uang.','requote')
                        if inv['amount']!=expected or received<expected:raise RuleError('Uang kurang atau tagihan berubah.','money',400)
                    else:
                        w=self._window(db,sid)
                        due=db.execute("SELECT 1 FROM invoices WHERE session_id=? AND state='PENDING'",(sid,)).fetchone()
                        if expected!=0 or received!=0 or not w or (now>w['deadline'] and s['state']!='EXIT_AUTHORIZED') or due:raise RuleError('Muat ulang tagihan sebelum mengizinkan keluar.','requote')
                    if inv:self.settle(db,inv,'SUCCESS',data['operation_key'],actor,'MANUAL',now,received)
                    existing=db.execute("SELECT id FROM authorizations WHERE session_id=? AND state='ACTIVE'",(sid,)).fetchone()
                    if existing:return {'session_id':sid,'authorization_id':existing['id']}
                    w=self._window(db,sid);aid=uid('AUTH')
                    db.execute("INSERT INTO authorizations VALUES(?,?,?,?,?,?,'ACTIVE')",(aid,sid,w['id'],actor,now,now+AUTH_SECONDS))
                    db.execute("UPDATE sessions SET state='EXIT_AUTHORIZED' WHERE id=?",(sid,))
                    self.audit(db,'MANUAL_AUTHORIZE',sid,actor,now)
                    return {'session_id':sid,'authorization_id':aid}
                return self._operation(db,'manual_pay',data,actor,now,pay_manual)
        return None
