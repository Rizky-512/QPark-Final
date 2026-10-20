"""Transactional SQLite repository. One connection/transaction per API request."""
from contextlib import contextmanager
from pathlib import Path
import hashlib
import hmac
import json
import secrets
import sqlite3
import time
import uuid
from .management import ManagementMixin
from .rules import (RuleError, plate, charge, CAPACITY, RATE, QUOTE_SECONDS,
                    WINDOW_SECONDS, AUTH_SECONDS, LOGIN_SECONDS)

def uid(prefix):
    return prefix + '-' + uuid.uuid4().hex

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def password_hash(password, salt):
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 310000).hex()

class Store(ManagementMixin):
    def __init__(self, path, clock=time.time, simulation=True):
        self.path, self.clock = str(path), clock
        self.simulation = simulation
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.executescript(Path(__file__).with_name('schema.sql').read_text())
            db.execute('INSERT OR IGNORE INTO migrations VALUES(1,?)', (self.clock(),))
            db.execute('INSERT OR IGNORE INTO metadata VALUES(?,?)', ('qr_secret', secrets.token_hex(32)))
            self.migrate_v4(db)
            self.secret = bytes.fromhex(db.execute("SELECT value FROM metadata WHERE key='qr_secret'").fetchone()[0])

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA busy_timeout=10000')
        try:
            yield db
        finally:
            db.close()

    def has_officers(self):
        with self.connection() as db:
            return db.execute('SELECT count(*) FROM officers').fetchone()[0] > 0

    def add_officer(self, username, password, role='PETUGAS'):
        if len(password) < 8 or not username.strip():
            raise RuleError('Username wajib diisi dan password minimum 8 karakter.')
        salt = secrets.token_hex(16)
        with self.connection() as db:
            db.execute('INSERT INTO officers(id,username,password_hash,salt,active,role) VALUES(?,?,?,?,1,?)',
                       (uid('OFF'), username.strip().lower(), password_hash(password, salt), salt, role))

    def audit(self, db, event, entity, actor, now, result='OK'):
        db.execute('INSERT INTO audit VALUES(?,?,?,?,?,?)',
                   (uid('AUD'), entity, event, actor, now, result))

    def _officer(self, db, token, now):
        found = db.execute('''SELECT o.* FROM logins l JOIN officers o ON o.id=l.officer_id
                              WHERE l.digest=? AND l.revoked=0 AND l.expires_at>? AND o.active=1''',
                           (digest(token), now)).fetchone()
        if not found:
            raise RuleError('Sesi petugas tidak sah atau telah berakhir. Login kembali.', 'unauthorized', 401)
        return found['id']

    def qr(self, window_id):
        # Secret never leaves server. Persist only digest, rederive for authorized ticket lookup.
        return 'QPX.' + window_id + '.' + hmac.new(self.secret, window_id.encode(), hashlib.sha256).hexdigest()

    def _session(self, db, session_id):
        found = db.execute('SELECT * FROM sessions WHERE id=?', (session_id,)).fetchone()
        if not found:
            raise RuleError('Sesi parkir tidak ditemukan.', 'not_found', 404)
        return dict(found)

    def _window(self, db, sid):
        row = db.execute('SELECT * FROM windows WHERE session_id=? ORDER BY sequence DESC LIMIT 1', (sid,)).fetchone()
        return dict(row) if row else None

    def _maintain(self, db, now):
        for a in db.execute("SELECT * FROM authorizations WHERE state='ACTIVE' AND expires_at<=?", (now,)).fetchall():
            db.execute("UPDATE authorizations SET state='EXPIRED' WHERE id=?", (a['id'],))
            db.execute("UPDATE sessions SET state='IN_AREA' WHERE id=? AND state='EXIT_AUTHORIZED'", (a['session_id'],))
            self.audit(db, 'AUTH_EXPIRED', a['id'], 'SYSTEM', now)
        db.execute("UPDATE invoices SET state='EXPIRED' WHERE kind='BASE' AND state='PENDING' AND expires_at<=?", (now,))
        for s in db.execute("SELECT * FROM sessions WHERE state='IN_AREA'").fetchall():
            w = self._window(db, s['id'])
            if w and now > w['deadline']:
                exists = db.execute('SELECT id FROM invoices WHERE window_id=?', (w['id'],)).fetchone()
                if not exists:
                    invoice_id = uid('INV')
                    db.execute('INSERT INTO invoices(id,session_id,kind,amount,hours,duration,issued_at,expires_at,state,window_id,paid_at) VALUES(?,?,?,?,?,?,?,?,?,?,NULL)',
                               (invoice_id, s['id'], 'PENALTY', s['hourly_rate'], 1, 0, now, None, 'PENDING', w['id']))
                    self.audit(db, 'PENALTY_CREATED', invoice_id, 'SYSTEM', now)

    def _view(self, db, sid, now, include_qr=True):
        s = self._session(db, sid)
        w = self._window(db, sid)
        invoices = [dict(x) for x in db.execute('SELECT * FROM invoices WHERE session_id=? ORDER BY issued_at,id', (sid,))]
        auth = db.execute("SELECT * FROM authorizations WHERE session_id=? AND state='ACTIVE'", (sid,)).fetchone()
        s.update(invoices=invoices, window=None, authorization=dict(auth) if auth else None,
                 server_time=now, amount_paid=sum(i['amount'] for i in invoices if i['state']=='PAID'))
        s['duration_seconds'] = max(0, (s['exited_at'] or now) - s['entered_at'])
        s['window_status'] = 'NONE' if not w else ('CONSUMED' if s['state']=='COMPLETED' else ('VALID' if now <= w['deadline'] or auth else 'EXPIRED'))
        if w:
            s['window'] = {k:v for k,v in w.items() if k!='token_digest'}
        if s['state']=='COMPLETED':
            s['payment_status']='Selesai'
        elif any(i['kind']=='PENALTY' and i['state']=='PENDING' for i in invoices):
            s['payment_status']='Tambahan belum dibayar'
        elif w:
            s['payment_status']='Lunas'
        else:
            s['payment_status']='Belum dibayar'
        s['exit_qr'] = self.qr(w['id']) if w and s['window_status']=='VALID' and include_qr else None
        return s

    def _token_window(self, db, token):
        if not isinstance(token, str) or not token.startswith('QPX.'):
            raise RuleError('QR keluar tidak dikenal. Jangan gunakan QR pembayaran.', 'invalid_qr')
        w = db.execute('SELECT * FROM windows WHERE token_digest=?', (digest(token),)).fetchone()
        if not w:
            raise RuleError('QR keluar tidak dikenal.', 'invalid_qr')
        s = self._session(db, w['session_id'])
        if s['state']=='COMPLETED':
            raise RuleError('Sesi sudah selesai; QR tidak berlaku.', 'completed')
        if self._window(db, s['id'])['id'] != w['id']:
            raise RuleError('QR versi lama. Minta QR keluar terbaru.', 'old_qr')
        return dict(w), s

    def _operation(self, db, action, data, actor, now, function):
        key = data.get('operation_key')
        if not isinstance(key, str) or len(key) < 8 or len(key) > 128:
            raise RuleError('Kunci operasi wajib 8–128 karakter.', 'operation_key', 400)
        fingerprint = digest(json.dumps(data, sort_keys=True, separators=(',', ':')))
        old = db.execute('SELECT * FROM operations WHERE key=?', (key,)).fetchone()
        if old:
            if old['action']!=action or old['actor']!=actor or old['fingerprint']!=fingerprint:
                raise RuleError('Kunci operasi telah dipakai untuk permintaan berbeda.', 'operation_conflict')
            result = json.loads(old['result'])
        else:
            result = function()
            db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?)',
                       (key, action, fingerprint, actor, json.dumps(result), now))
        result = dict(result)
        if result.get('session_id'):
            result['session'] = self._view(db, result['session_id'], now)
        return result

    def dispatch(self, method, path, data=None, token=''):
        data = {} if data is None else data
        if not isinstance(data, dict):
            raise RuleError('Payload JSON harus objek.', 'payload', 400)
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            now = self.clock()
            try:
                self._maintain(db, now)
                result = self._dispatch(db, method, path, data, token, now)
                db.commit()
                return {**result, 'server_time': now}
            except RuleError as e:
                # Maintenance/denial audit must persist even if business request is rejected.
                self.audit(db, 'REQUEST_REJECTED', path.split('?')[0], 'CLIENT', now, e.code)
                db.commit()
                raise
            except Exception:
                db.rollback()
                raise

    def _dispatch(self, db, method, path, data, token, now):
        from urllib.parse import urlsplit, parse_qs
        parts = urlsplit(path)
        path, query = parts.path, parse_qs(parts.query)
        if method=='GET' and path=='/api/health':
            return {'service':'qpark', 'version':5, 'simulation':self.simulation}
        if method=='POST' and path=='/api/login':
            username, password = data.get('username',''), data.get('password','')
            if not isinstance(username,str) or not isinstance(password,str):
                raise RuleError('Kredensial tidak valid.', 'credentials', 401)
            o = db.execute('SELECT * FROM officers WHERE username=? AND active=1', (username.strip().lower(),)).fetchone()
            salt = o['salt'] if o else '00'*16
            hashed = password_hash(password,salt)
            if not o or not hmac.compare_digest(hashed,o['password_hash']):
                raise RuleError('Nama pengguna atau kata sandi tidak valid.', 'credentials', 401)
            raw = secrets.token_urlsafe(32)
            db.execute('INSERT INTO logins VALUES(?,?,?,0)', (digest(raw),o['id'],now+LOGIN_SECONDS))
            self.audit(db,'LOGIN',o['id'],o['id'],now)
            return {'token':raw,'username':o['username'],'role':o['role'],'expires_at':now+LOGIN_SECONDS}
        if method=='POST' and path=='/api/logout':
            # Idempotent revoke even if already expired/revoked, but no leak of login details.
            login = db.execute('SELECT * FROM logins WHERE digest=?', (digest(token),)).fetchone()
            if login and not login['revoked']:
                db.execute('UPDATE logins SET revoked=1 WHERE digest=?',(digest(token),))
                self.audit(db,'LOGOUT',login['officer_id'],login['officer_id'],now)
            return {'revoked':True}
        if method=='GET' and path=='/api/capacity':
            occupied=db.execute("SELECT count(*) FROM sessions WHERE state!='COMPLETED'").fetchone()[0]
            settings=self.settings(db)
            total=settings['capacity']
            return {'total':total,'occupied':occupied,'available':max(0,total-occupied),'full':occupied>=total, 'rates':{'MOBIL':settings['car_rate'],'MOTOR':settings['motor_rate']}}
        if method=='GET' and path=='/api/ticket':
            p=plate(query.get('plate',[''])[0])
            found=db.execute("SELECT id FROM sessions WHERE plate=? AND state!='COMPLETED'",(p,)).fetchone()
            # Completed ticket only when explicitly tracking that exact previous session.
            previous=query.get('previous',[''])[0]
            if not found and previous:
                found=db.execute('SELECT id FROM sessions WHERE id=? AND plate=?',(previous,p)).fetchone()
            return {'session':self._view(db,found['id'],now) if found else None}
        if method=='POST' and path=='/api/invoice':
            sid=data.get('session_id')
            s=self._session(db,sid)
            if s['state']=='COMPLETED':raise RuleError('Sesi telah selesai.','completed')
            pending=db.execute("SELECT * FROM invoices WHERE session_id=? AND state='PENDING'",(sid,)).fetchone()
            if not pending and not self._window(db,sid):
                duration=now-s['entered_at'];hours,amount=charge(duration, s['hourly_rate']);inv=uid('INV')
                db.execute('INSERT INTO invoices(id,session_id,kind,amount,hours,duration,issued_at,expires_at,state,window_id,paid_at) VALUES(?,?,?,?,?,?,?,?,?,?,NULL)',
                           (inv,sid,'BASE',amount,hours,duration,now,now+QUOTE_SECONDS,'PENDING',None))
                self.audit(db,'INVOICE_CREATED',inv,'DRIVER',now)
                pending=db.execute('SELECT * FROM invoices WHERE id=?',(inv,)).fetchone()
            return {'invoice':dict(pending) if pending else None,'session':self._view(db,sid,now)}
        if method=='POST' and path=='/api/payment':
            if not self.simulation:
                raise RuleError('Simulator pembayaran dinonaktifkan pada server ini.', 'simulation_disabled', 403)
            def pay():
                inv=db.execute('SELECT * FROM invoices WHERE id=?',(data.get('invoice_id'),)).fetchone()
                if not inv:raise RuleError('Tagihan tidak ditemukan.','invoice',404)
                sid=inv['session_id']
                # Invoice success is globally idempotent, also for a second device/key.
                if inv['state']=='PAID':
                    a=db.execute("SELECT * FROM attempts WHERE invoice_id=? AND outcome='SUCCESS'",(inv['id'],)).fetchone()
                    return {'session_id':sid,'invoice_id':inv['id'],'outcome':'SUCCESS','attempt_id':a['id'],'paid_at':inv['paid_at']}
                if inv['state']=='EXPIRED' or (inv['expires_at'] is not None and now>=inv['expires_at']):
                    raise RuleError('Tagihan kedaluwarsa. Buka tagihan baru.','invoice_expired')
                if self._session(db,sid)['state']!='IN_AREA':raise RuleError('Sesi tidak dapat dibayar saat ini.','state')
                outcome=data.get('outcome')
                if outcome not in ('PENDING','SUCCESS','FAILED'):raise RuleError('Hasil simulasi tidak valid.','outcome',400)
                return self.settle(db, inv, outcome, data['operation_key'], 'DRIVER', 'QR_SIMULASI', now)
            return self._operation(db,'payment',data,'DRIVER',now,pay)
        extra=self.extra_dispatch(db, method, path, query, data, token, now)
        if extra is not None:return extra
        if path.startswith('/api/officer/'):
            actor=self._officer(db,token,now)
            if method=='GET' and path=='/api/officer/monitor':
                q=query.get('q',[''])[0].upper().replace(' ','')
                rows=db.execute("SELECT id FROM sessions WHERE state!='COMPLETED' AND instr(plate,?)>0 ORDER BY entered_at DESC",(q,)).fetchall()
                return {'sessions':[self._view(db,s['id'],now,False) for s in rows]}
            if method=='POST' and path=='/api/officer/entry':
                def enter():
                    p=plate(data.get('plate'))
                    if data.get('verified') is not True or not (data.get('image_source')=='manual' or (data.get('image_readable') is True and data.get('image_source') in ('test_photo','camera'))):
                        raise RuleError('Kendaraan wajib diverifikasi. Jika menggunakan gambar, pastikan gambar terbaca.','verification',400)
                    if db.execute("SELECT 1 FROM sessions WHERE plate=? AND state!='COMPLETED'",(p,)).fetchone():
                        raise RuleError('Nopol masih memiliki sesi aktif.','duplicate_plate')
                    kind=data.get('vehicle_type','MOBIL')
                    if kind not in ('MOBIL','MOTOR'):raise RuleError('Pilih Mobil atau Motor.','vehicle',400)
                    settings=self.settings(db)
                    if db.execute("SELECT count(*) FROM sessions WHERE state!='COMPLETED'").fetchone()[0]>=settings['capacity']:
                        raise RuleError('Area parkir penuh. Kendaraan ditolak.','full')
                    sid=uid('QP')
                    db.execute("INSERT INTO sessions(id,plate,entered_at,entered_by,state,vehicle_type,hourly_rate) VALUES(?,?,?,?,'IN_AREA',?,?)",(sid,p,now,actor,kind,settings['motor_rate' if kind=='MOTOR' else 'car_rate']))
                    self.audit(db,'ENTRY',sid,actor,now,data['image_source'])
                    return {'session_id':sid}
                return self._operation(db,'entry',data,actor,now,enter)
            if method=='POST' and path=='/api/officer/scan':
                w,s=self._token_window(db,data.get('qr',''))
                if s['state']!='EXIT_AUTHORIZED' and now>w['deadline']:
                    raise RuleError('Izin 15 menit habis. Lunasi tagihan tambahan sesuai tarif kendaraan.','window_expired')
                return {'session':self._view(db,s['id'],now)}
            if method=='POST' and path=='/api/officer/authorize':
                def authorize():
                    w,s=self._token_window(db,data.get('qr',''))
                    if data.get('verified') is not True or plate(data.get('plate'))!=s['plate']:
                        raise RuleError('Nopol kendaraan harus cocok dan diverifikasi petugas.','plate_mismatch')
                    existing=db.execute("SELECT id FROM authorizations WHERE session_id=? AND state='ACTIVE'",(s['id'],)).fetchone()
                    if existing:return {'session_id':s['id'],'authorization_id':existing['id']}
                    if now>w['deadline']:raise RuleError('Izin 15 menit habis. Lunasi tagihan tambahan sesuai tarif kendaraan.','window_expired')
                    aid=uid('AUTH')
                    db.execute("INSERT INTO authorizations VALUES(?,?,?,?,?,?,'ACTIVE')",(aid,s['id'],w['id'],actor,now,now+AUTH_SECONDS))
                    db.execute("UPDATE sessions SET state='EXIT_AUTHORIZED' WHERE id=?",(s['id'],))
                    self.audit(db,'AUTHORIZE',aid,actor,now)
                    return {'session_id':s['id'],'authorization_id':aid}
                return self._operation(db,'authorize',data,actor,now,authorize)
            if method=='POST' and path in ('/api/officer/complete','/api/officer/cancel'):
                complete=path.endswith('/complete')
                def finish():
                    sid=data.get('session_id');s=self._session(db,sid)
                    a=db.execute('SELECT * FROM authorizations WHERE id=? AND session_id=?',(data.get('authorization_id'),sid)).fetchone()
                    if not a:raise RuleError('Persetujuan keluar tidak ditemukan.','authorization')
                    if complete and s['state']=='COMPLETED' and a['state']=='COMPLETED':return {'session_id':sid,'authorization_id':a['id']}
                    if not complete and a['state']=='CANCELLED':return {'session_id':sid,'authorization_id':a['id']}
                    if a['state']!='ACTIVE' or now>=a['expires_at']:
                        raise RuleError('Persetujuan 120 detik sudah habis. Verifikasi ulang.','authorization_expired')
                    if complete and data.get('passed') is not True:
                        raise RuleError('Konfirmasi kendaraan benar-benar sudah lewat.','verification',400)
                    db.execute('UPDATE authorizations SET state=? WHERE id=?',('COMPLETED' if complete else 'CANCELLED',a['id']))
                    if complete:db.execute("UPDATE sessions SET state='COMPLETED',exited_at=?,exited_by=? WHERE id=?",(now,actor,sid))
                    else:db.execute("UPDATE sessions SET state='IN_AREA' WHERE id=?",(sid,))
                    self.audit(db,'EXIT' if complete else 'AUTH_CANCELLED',sid,actor,now)
                    self._maintain(db,now)
                    return {'session_id':sid,'authorization_id':a['id']}
                return self._operation(db,'complete' if complete else 'cancel',data,actor,now,finish)
        raise RuleError('Endpoint tidak ditemukan.','not_found',404)
