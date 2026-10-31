"""Customer authorization at the HTTP boundary; plates are never credentials."""
import re
import secrets
from urllib.parse import urlsplit, parse_qs
from .rules import RuleError, plate


class CustomerAccessMixin:
    def migrate_customer_access(self, db):
        db.executescript('''
          CREATE TABLE IF NOT EXISTS customer_links (
            session_id TEXT PRIMARY KEY REFERENCES sessions(id),
            owner TEXT NOT NULL
          );
          CREATE INDEX IF NOT EXISTS customer_links_owner ON customer_links(owner);
          CREATE TABLE IF NOT EXISTS customer_codes (
            digest TEXT PRIMARY KEY, owner TEXT NOT NULL UNIQUE,
            plate TEXT NOT NULL, expires_at REAL NOT NULL
          );
        ''')

    def customer_dispatch(self, db, method, full_path, data, token, now, key):
        from .store import digest
        parts = urlsplit(full_path)
        path, query = parts.path, parse_qs(parts.query)
        owner = 'demo:' + digest(key) if re.fullmatch(r'[a-f0-9]{48}', key or '') else None
        if path == '/api/customer/code' and method == 'POST':
            if owner is None:
                raise RuleError('Identitas perangkat diperlukan.', 'customer_identity', 401)
            p = plate(data.get('plate'))
            code = secrets.token_hex(6).upper()
            db.execute('DELETE FROM customer_codes WHERE owner=? OR expires_at<=?', (owner, now))
            db.execute('INSERT INTO customer_codes VALUES(?,?,?,?)', (digest(code), owner, p, now+900))
            return {'code': code, 'expires_at': now+900}

        # Staff must physically verify the plate before binding an unowned ticket.
        if path == '/api/officer/link' and method == 'POST':
            actor = self._officer(db, token, now)
            p = plate(data.get('plate'))
            session = db.execute("SELECT id FROM sessions WHERE plate=? AND state!='COMPLETED'", (p,)).fetchone()
            if not session or data.get('verified') is not True:
                raise RuleError('Verifikasi kendaraan aktif terlebih dahulu.', 'verification', 400)
            link = db.execute('SELECT * FROM customer_codes WHERE digest=? AND plate=? AND expires_at>?',
                              (digest(str(data.get('code', '')).strip().upper()), p, now)).fetchone()
            if not link:
                raise RuleError('Kode tidak valid atau kedaluwarsa.', 'link_code', 400)
            existing = db.execute('SELECT owner FROM customer_links WHERE session_id=?', (session['id'],)).fetchone()
            if existing and existing['owner'] != link['owner']:
                raise RuleError('Tiket sudah terhubung ke pelanggan lain.', 'ticket_owner', 409)
            db.execute('INSERT OR IGNORE INTO customer_links VALUES(?,?)', (session['id'], link['owner']))
            # Retain code until expiry so a lost response can safely replay this binding.
            self.audit(db, 'CUSTOMER_LINK', session['id'], actor, now)
            return {'linked': True}

        if path in ('/api/ticket', '/api/history', '/api/invoice', '/api/payment'):
            if owner is None:
                raise RuleError('Identitas perangkat diperlukan.', 'customer_identity', 401)
            if path == '/api/ticket' and method == 'GET':
                p = plate(query.get('plate', [''])[0])
                row = db.execute("""SELECT s.id FROM sessions s JOIN customer_links c ON c.session_id=s.id
                  WHERE c.owner=? AND s.plate=? AND (s.state!='COMPLETED' OR s.id=?)
                  ORDER BY (s.state!='COMPLETED') DESC LIMIT 1""",
                  (owner, p, query.get('previous', [''])[0])).fetchone()
                return {'session': self._view(db, row['id'], now) if row else None}
            if path == '/api/history' and method == 'GET':
                return self.history(db, query, now, public=True, owner=owner)
            if method == 'POST':
                sid = data.get('session_id')
                if path == '/api/payment':
                    row = db.execute('SELECT session_id FROM invoices WHERE id=?', (data.get('invoice_id'),)).fetchone()
                    sid = row['session_id'] if row else None
                if not db.execute('SELECT 1 FROM customer_links WHERE session_id=? AND owner=?', (sid, owner)).fetchone():
                    raise RuleError('Tiket tidak tersedia untuk pelanggan ini.', 'ticket_owner', 403)
        return self._dispatch(db, method, full_path, data, token, now)
