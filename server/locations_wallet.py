"""Multi-location management, Pengelola/Superadmin scoping, and prototype E-Wallet."""
import json
import secrets
from .rules import RuleError

DEFAULT_LOCATION_ID = 'LOC-DEFAULT'
SECOND_LOCATION_ID = 'LOC-2'


def parse_payment_qr(raw):
    """Extract invoice_id from QPP.SIMULASI.<id> or QPP.<id>."""
    if not isinstance(raw, str):
        raise RuleError('Kode QR tagihan tidak valid.', 'invalid_qr', 400)
    text = raw.strip()
    if text.startswith('QPP.SIMULASI.'):
        inv_id = text[len('QPP.SIMULASI.'):].strip()
    elif text.startswith('QPP.'):
        inv_id = text[len('QPP.'):].strip()
    else:
        raise RuleError('QR bukan kode tagihan parkir QPark.', 'invalid_qr', 400)
    if not inv_id or len(inv_id) > 80:
        raise RuleError('Kode QR tagihan tidak valid.', 'invalid_qr', 400)
    return inv_id


def migrate_v5(store, db):
    """Add locations, location_id scoping, Superadmin/Pengelola accounts, and E-Wallet."""
    from .store import uid, password_hash
    db.execute('BEGIN IMMEDIATE')
    db.executescript('''
      CREATE TABLE IF NOT EXISTS locations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT NOT NULL DEFAULT '',
        car_capacity INTEGER NOT NULL DEFAULT 10,
        motor_capacity INTEGER NOT NULL DEFAULT 10,
        car_rate INTEGER NOT NULL DEFAULT 7000,
        motor_rate INTEGER NOT NULL DEFAULT 2000,
        active INTEGER NOT NULL DEFAULT 1,
        created_at REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS wallets (
        owner TEXT PRIMARY KEY,
        balance INTEGER NOT NULL DEFAULT 0 CHECK(balance >= 0),
        updated_at REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS wallet_transactions (
        id TEXT PRIMARY KEY,
        owner TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('TOPUP', 'PAYMENT')),
        amount INTEGER NOT NULL CHECK(amount > 0),
        balance_after INTEGER NOT NULL,
        description TEXT NOT NULL,
        reference_id TEXT,
        created_at REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS wallet_tx_owner ON wallet_transactions(owner, created_at DESC);
    ''')

    for table, col_def in [
        ('officers', 'location_id TEXT'),
        ('sessions', f"location_id TEXT NOT NULL DEFAULT '{DEFAULT_LOCATION_ID}'"),
        ('audit', 'location_id TEXT'),
    ]:
        present = {x['name'] for x in db.execute('PRAGMA table_info(' + table + ')')}
        col_name = col_def.split()[0]
        if col_name not in present:
            db.execute(f'ALTER TABLE {table} ADD COLUMN {col_def}')

    now = store.clock()
    legacy = json.loads(db.execute("SELECT value FROM metadata WHERE key='parking_settings'").fetchone()[0])
    db.execute(
        '''INSERT OR IGNORE INTO locations
           (id, name, address, car_capacity, motor_capacity, car_rate, motor_rate, active, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)''',
        (
            DEFAULT_LOCATION_ID,
            'QPark Mall Sentral',
            'Jl. Sudirman No. 1, Pusat Kota',
            legacy.get('car_capacity', 10),
            legacy.get('motor_capacity', 10),
            legacy.get('car_rate', 7000),
            legacy.get('motor_rate', 2000),
            now,
        ),
    )

    # Bind existing officers (except SUPERADMIN) without location_id to default location.
    db.execute(
        "UPDATE officers SET location_id=? WHERE location_id IS NULL AND role!='SUPERADMIN'",
        (DEFAULT_LOCATION_ID,),
    )

    if not db.execute('SELECT 1 FROM migrations WHERE version=3').fetchone():
        db.execute(
            '''INSERT OR IGNORE INTO locations
               (id, name, address, car_capacity, motor_capacity, car_rate, motor_rate, active, created_at)
               VALUES (?, ?, ?, 15, 20, 6000, 2000, 1, ?)''',
            (SECOND_LOCATION_ID, 'QPark Gedung Merdeka', 'Jl. Merdeka No. 45', now),
        )
        # Seed superadmin and Location-2 demo staff without altering LOC-DEFAULT's 2 officers.
        for uname, pwd, role, loc_id in [
            ('superadmin', 'superadmin123', 'SUPERADMIN', None),
            ('pengelola_b', 'pengelola123', 'ADMIN', SECOND_LOCATION_ID),
            ('petugas_b', 'petugas123', 'PETUGAS', SECOND_LOCATION_ID),
        ]:
            if not db.execute('SELECT 1 FROM officers WHERE username=?', (uname,)).fetchone():
                salt = secrets.token_hex(16)
                db.execute(
                    'INSERT INTO officers(id,username,password_hash,salt,active,role,location_id) VALUES(?,?,?,?,1,?,?)',
                    (uid('OFF'), uname, password_hash(pwd, salt), salt, role, loc_id),
                )
        db.execute('INSERT INTO migrations VALUES(3, ?)', (now,))
    db.commit()


def get_location(db, location_id):
    loc = db.execute('SELECT * FROM locations WHERE id=?', (location_id,)).fetchone()
    if not loc:
        raise RuleError('Lokasi parkir tidak ditemukan.', 'location_not_found', 404)
    return dict(loc)


def location_capacity_item(db, loc):
    categories = {}
    for kind, key in [('MOBIL', 'car_capacity'), ('MOTOR', 'motor_capacity')]:
        used = db.execute(
            "SELECT count(*) FROM sessions WHERE state!='COMPLETED' AND vehicle_type=? AND location_id=?",
            (kind, loc['id']),
        ).fetchone()[0]
        total = loc[key]
        categories[kind] = dict(
            total=total,
            occupied=used,
            available=max(0, total - used),
            full=used >= total,
        )
    return dict(
        id=loc['id'],
        name=loc['name'],
        address=loc['address'],
        active=bool(loc['active']),
        total=sum(x['total'] for x in categories.values()),
        occupied=sum(x['occupied'] for x in categories.values()),
        available=sum(x['available'] for x in categories.values()),
        full=all(x['full'] for x in categories.values()),
        categories=categories,
        rates={'MOBIL': loc['car_rate'], 'MOTOR': loc['motor_rate']},
    )


def list_locations_with_capacity(db, include_inactive=False):
    sql = 'SELECT * FROM locations' + ('' if include_inactive else ' WHERE active=1') + ' ORDER BY created_at, id'
    return [location_capacity_item(db, dict(r)) for r in db.execute(sql).fetchall()]


def wallet_view(db, owner):
    row = db.execute('SELECT balance, updated_at FROM wallets WHERE owner=?', (owner,)).fetchone()
    balance = row['balance'] if row else 0
    txs = [
        dict(r)
        for r in db.execute(
            '''SELECT id, kind, amount, balance_after, description, reference_id, created_at
               FROM wallet_transactions WHERE owner=? ORDER BY created_at DESC, id DESC LIMIT 50''',
            (owner,),
        ).fetchall()
    ]
    return {'balance': balance, 'transactions': txs}


def wallet_dispatch(store, db, method, path, query, data, token, now, owner):
    from .store import uid
    if path == '/api/locations' and method == 'GET':
        include_inactive = False
        if token:
            try:
                officer = store._officer_row(db, token, now)
                include_inactive = officer['role'] == 'SUPERADMIN'
            except RuleError:
                pass
        return {'locations': list_locations_with_capacity(db, include_inactive=include_inactive)}

    if path == '/api/admin/locations':
        officer = store._officer_row(db, token, now)
        if officer['role'] not in ('ADMIN', 'SUPERADMIN'):
            raise RuleError('Hanya pengelola atau superadmin yang dapat mengakses lokasi.', 'forbidden', 403)
        if method == 'GET':
            if officer['role'] == 'SUPERADMIN':
                return {'locations': list_locations_with_capacity(db, include_inactive=True)}
            loc = get_location(db, officer['location_id'] or DEFAULT_LOCATION_ID)
            return {'locations': [location_capacity_item(db, loc)]}
        if method == 'POST':
            if officer['role'] != 'SUPERADMIN':
                raise RuleError('Hanya superadmin yang dapat menambah atau mengubah lokasi.', 'forbidden', 403)
            def save_location():
                name = str(data.get('name', '')).strip()
                address = str(data.get('address', '')).strip()
                if not name or len(name) > 80:
                    raise RuleError('Nama lokasi wajib diisi (maksimal 80 karakter).', 'location', 400)
                if len(address) > 200:
                    raise RuleError('Alamat lokasi maksimal 200 karakter.', 'location', 400)
                values = {k: data.get(k) for k in ('car_capacity', 'motor_capacity', 'car_rate', 'motor_rate')}
                if any(
                    type(v) is not int or v < (0 if k.endswith('capacity') else 1) or v > 1000000
                    for k, v in values.items()
                ):
                    raise RuleError('Isi kapasitas 0-1.000.000 dan tarif 1-1.000.000.', 'settings', 400)
                active = data.get('active', True)
                if type(active) is not bool:
                    raise RuleError('Status lokasi tidak valid.', 'location', 400)
                loc_id = data.get('id')
                if loc_id:
                    old = get_location(db, loc_id)
                    for kind, key in [('MOBIL', 'car_capacity'), ('MOTOR', 'motor_capacity')]:
                        occupied = db.execute(
                            "SELECT count(*) FROM sessions WHERE state!='COMPLETED' AND vehicle_type=? AND location_id=?",
                            (kind, old['id']),
                        ).fetchone()[0]
                        if values[key] < occupied:
                            raise RuleError(f'Kapasitas {kind} tidak boleh di bawah jumlah kendaraan aktif.', 'capacity')
                    if not active:
                        any_active = db.execute(
                            "SELECT count(*) FROM sessions WHERE state!='COMPLETED' AND location_id=?",
                            (old['id'],),
                        ).fetchone()[0]
                        if any_active > 0:
                            raise RuleError('Lokasi tidak dapat dinonaktifkan selama masih ada kendaraan parkir.', 'active_sessions')
                    db.execute(
                        '''UPDATE locations SET name=?, address=?, car_capacity=?, motor_capacity=?,
                           car_rate=?, motor_rate=?, active=? WHERE id=?''',
                        (name, address, values['car_capacity'], values['motor_capacity'],
                         values['car_rate'], values['motor_rate'], int(active), old['id']),
                    )
                    if old['id'] == DEFAULT_LOCATION_ID:
                        meta = dict(values, capacity=values['car_capacity'] + values['motor_capacity'])
                        db.execute("UPDATE metadata SET value=? WHERE key='parking_settings'", (json.dumps(meta),))
                    store.audit(db, 'LOCATION_UPDATED', old['id'], officer['id'], now, name)
                    return {'location': location_capacity_item(db, get_location(db, old['id']))}
                new_id = uid('LOC')
                db.execute(
                    '''INSERT INTO locations(id, name, address, car_capacity, motor_capacity, car_rate, motor_rate, active, created_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    (new_id, name, address, values['car_capacity'], values['motor_capacity'],
                     values['car_rate'], values['motor_rate'], int(active), now),
                )
                store.audit(db, 'LOCATION_CREATED', new_id, officer['id'], now, name)
                return {'location': location_capacity_item(db, get_location(db, new_id))}
            return store._operation(db, 'location_save', data, officer['id'], now, save_location)

    if path == '/api/wallet' and method == 'GET':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        return wallet_view(db, owner)

    if path == '/api/wallet/topup' and method == 'POST':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        def topup():
            amount = data.get('amount')
            if type(amount) is not int or amount < 1000 or amount > 10000000:
                raise RuleError('Nominal top up harus antara Rp1.000 hingga Rp10.000.000.', 'amount', 400)
            row = db.execute('SELECT balance FROM wallets WHERE owner=?', (owner,)).fetchone()
            new_balance = (row['balance'] if row else 0) + amount
            if new_balance > 1000000000:
                raise RuleError('Saldo maksimal Rp1.000.000.000 tercapai.', 'balance_limit', 400)
            db.execute(
                'INSERT INTO wallets(owner, balance, updated_at) VALUES(?,?,?) ON CONFLICT(owner) DO UPDATE SET balance=excluded.balance, updated_at=excluded.updated_at',
                (owner, new_balance, now),
            )
            tx_id = uid('WLT')
            db.execute(
                'INSERT INTO wallet_transactions VALUES(?,?,?,?,?,?,?,?)',
                (tx_id, owner, 'TOPUP', amount, new_balance, 'Top up saldo Dompet QPark (simulasi)', data['operation_key'], now),
            )
            store.audit(db, 'WALLET_TOPUP', tx_id, owner, now, str(amount))
            return {'balance': new_balance, 'transaction_id': tx_id}
        res = store._operation(db, 'wallet_topup', data, owner, now, topup)
        return {**res, **wallet_view(db, owner)}

    if path == '/api/wallet/inspect' and method == 'POST':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        inv_id = data.get('invoice_id') or parse_payment_qr(data.get('qr', ''))
        inv = db.execute('SELECT * FROM invoices WHERE id=?', (inv_id,)).fetchone()
        if not inv:
            raise RuleError('Tagihan parkir tidak ditemukan.', 'invoice', 404)
        if inv['state'] == 'PAID':
            raise RuleError('Tagihan ini sudah lunas.', 'invoice_paid', 409)
        if inv['state'] == 'EXPIRED' or (inv['expires_at'] is not None and now >= inv['expires_at']):
            raise RuleError('Tagihan sudah kedaluwarsa. Minta QR tagihan baru.', 'invoice_expired', 409)
        s = store._view(db, inv['session_id'], now, include_qr=False)
        if s['state'] != 'IN_AREA':
            raise RuleError('Sesi parkir tidak dapat dibayar saat ini.', 'state', 409)
        w = wallet_view(db, owner)
        return {'invoice': dict(inv), 'session': s, 'balance': w['balance']}

    if path == '/api/wallet/pay' and method == 'POST':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        def pay_wallet():
            inv_id = data.get('invoice_id') or parse_payment_qr(data.get('qr', ''))
            inv = db.execute('SELECT * FROM invoices WHERE id=?', (inv_id,)).fetchone()
            if not inv:
                raise RuleError('Tagihan parkir tidak ditemukan.', 'invoice', 404)
            sid = inv['session_id']
            if inv['state'] == 'PAID':
                a = db.execute("SELECT * FROM attempts WHERE invoice_id=? AND outcome='SUCCESS'", (inv['id'],)).fetchone()
                return {'session_id': sid, 'invoice_id': inv['id'], 'outcome': 'SUCCESS',
                        'attempt_id': a['id'] if a else None, 'paid_at': inv['paid_at']}
            if inv['state'] == 'EXPIRED' or (inv['expires_at'] is not None and now >= inv['expires_at']):
                raise RuleError('Tagihan kedaluwarsa. Buka tagihan baru.', 'invoice_expired', 409)
            s = store._session(db, sid)
            if s['state'] != 'IN_AREA':
                raise RuleError('Sesi tidak dapat dibayar saat ini.', 'state', 409)
            row = db.execute('SELECT balance FROM wallets WHERE owner=?', (owner,)).fetchone()
            balance = row['balance'] if row else 0
            if balance < inv['amount']:
                raise RuleError('Saldo Dompet QPark tidak mencukupi. Silakan Top Up terlebih dahulu.', 'insufficient_balance', 409)
            new_balance = balance - inv['amount']
            db.execute('UPDATE wallets SET balance=?, updated_at=? WHERE owner=?', (new_balance, now, owner))
            loc = get_location(db, s.get('location_id') or DEFAULT_LOCATION_ID)
            tx_id = uid('WLT')
            db.execute(
                'INSERT INTO wallet_transactions VALUES(?,?,?,?,?,?,?,?)',
                (tx_id, owner, 'PAYMENT', inv['amount'], new_balance,
                 f"Bayar parkir {s['plate']} · {loc['name']}", inv['id'], now),
            )
            # Link unowned session to paying customer so exit QR & receipt appear in Aktivitas.
            existing_link = db.execute('SELECT owner FROM customer_links WHERE session_id=?', (sid,)).fetchone()
            if not existing_link:
                db.execute('INSERT OR IGNORE INTO customer_links VALUES(?,?)', (sid, owner))
            return store.settle(db, inv, 'SUCCESS', data['operation_key'], owner, 'EWALLET', now)
        res = store._operation(db, 'wallet_pay', data, owner, now, pay_wallet)
        return {**res, 'balance': wallet_view(db, owner)['balance']}

    return None
