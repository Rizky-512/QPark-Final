"""EV charging slot bookings (blue-plate enforcement) and time-gated location promos."""
from .rules import RuleError, plate
from .locations_wallet import DEFAULT_LOCATION_ID, SECOND_LOCATION_ID, get_location


def migrate_v6(store, db):
    """Add EV charging capacity/bookings, blue-plate EV flag, and time-gated promos."""
    from .store import uid
    db.execute('BEGIN IMMEDIATE')
    for table, col_def in [
        ('locations', 'ev_capacity INTEGER NOT NULL DEFAULT 4'),
        ('locations', 'ev_rate INTEGER NOT NULL DEFAULT 10000'),
        ('vehicle_categories', 'is_ev INTEGER NOT NULL DEFAULT 0'),
    ]:
        present = {x['name'] for x in db.execute('PRAGMA table_info(' + table + ')')}
        col_name = col_def.split()[0]
        if col_name not in present:
            db.execute(f'ALTER TABLE {table} ADD COLUMN {col_def}')

    db.executescript('''
      CREATE TABLE IF NOT EXISTS ev_bookings (
        id TEXT PRIMARY KEY,
        location_id TEXT NOT NULL REFERENCES locations(id),
        owner TEXT NOT NULL,
        plate TEXT NOT NULL,
        duration_hours INTEGER NOT NULL CHECK(duration_hours BETWEEN 1 AND 12),
        hourly_rate INTEGER NOT NULL,
        estimated_cost INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('ACTIVE', 'COMPLETED', 'CANCELLED')),
        booked_at REAL NOT NULL,
        expires_at REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS ev_bookings_loc_status ON ev_bookings(location_id, status);
      CREATE INDEX IF NOT EXISTS ev_bookings_owner ON ev_bookings(owner, booked_at DESC);

      CREATE TABLE IF NOT EXISTS promos (
        id TEXT PRIMARY KEY,
        location_id TEXT NOT NULL REFERENCES locations(id),
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        code TEXT NOT NULL DEFAULT '',
        discount_type TEXT NOT NULL CHECK(discount_type IN ('PERCENT', 'FIXED')),
        discount_value INTEGER NOT NULL CHECK(discount_value > 0),
        starts_at REAL NOT NULL,
        ends_at REAL NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_by TEXT,
        created_at REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS promos_loc_time ON promos(location_id, active, starts_at, ends_at);
    ''')

    now = store.clock()
    if not db.execute('SELECT 1 FROM migrations WHERE version=4').fetchone():
        db.execute('UPDATE locations SET ev_capacity=6, ev_rate=9000 WHERE id=?', (SECOND_LOCATION_ID,))
        # Seed 2 sample time-gated promos (valid 30 days) for demo experience.
        if db.execute('SELECT count(*) FROM promos').fetchone()[0] == 0:
            db.execute(
                '''INSERT INTO promos
                   (id, location_id, title, description, code, discount_type, discount_value, starts_at, ends_at, active, created_by, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'SYSTEM', ?)''',
                (
                    uid('PRM'), DEFAULT_LOCATION_ID,
                    'Diskon Parkir 20% Sentral',
                    'Potongan 20% khusus pembayaran Dompet QPark di QPark Mall Sentral.',
                    'SENTRAL20', 'PERCENT', 20, now - 3600, now + 30 * 86400, now,
                ),
            )
            if db.execute('SELECT 1 FROM locations WHERE id=?', (SECOND_LOCATION_ID,)).fetchone():
                db.execute(
                    '''INSERT INTO promos
                       (id, location_id, title, description, code, discount_type, discount_value, starts_at, ends_at, active, created_by, created_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'SYSTEM', ?)''',
                    (
                        uid('PRM'), SECOND_LOCATION_ID,
                        'Hemat Rp2.000 Gedung Merdeka',
                        'Potongan langsung Rp2.000 selama masa promo berlangsung.',
                        'MERDEKA2K', 'FIXED', 2000, now - 3600, now + 30 * 86400, now,
                    ),
                )
        db.execute('INSERT INTO migrations VALUES(4, ?)', (now,))
    db.commit()


def maintain_ev_bookings(db, now):
    try:
        db.execute("UPDATE ev_bookings SET status='COMPLETED' WHERE status='ACTIVE' AND expires_at<=?", (now,))
    except Exception:
        pass


def ev_summary(db, loc):
    total = int(loc.get('ev_capacity', 4))
    rate = int(loc.get('ev_rate', 10000))
    try:
        used = db.execute(
            "SELECT count(*) FROM ev_bookings WHERE location_id=? AND status='ACTIVE'",
            (loc['id'],),
        ).fetchone()[0]
    except Exception:
        used = 0
    return dict(
        total=total,
        occupied=used,
        available=max(0, total - used),
        full=used >= total,
        rate=rate,
    )


def compute_promo_discount(db, promo_id, location_id, amount, now):
    if not promo_id:
        return 0, None
    p = db.execute('SELECT * FROM promos WHERE id=?', (promo_id,)).fetchone()
    if not p:
        raise RuleError('Promo tidak ditemukan.', 'promo_not_found', 404)
    if p['location_id'] != location_id:
        raise RuleError('Promo tidak berlaku untuk lokasi parkir ini.', 'promo_location', 400)
    if not p['active'] or now < p['starts_at'] or now > p['ends_at']:
        raise RuleError('Promo sudah berakhir atau belum berlaku.', 'promo_expired', 409)
    if p['discount_type'] == 'PERCENT':
        disc = (amount * int(p['discount_value'])) // 100
    else:
        disc = int(p['discount_value'])
    disc = max(0, min(amount, disc))
    return disc, dict(p)


def active_promos_list(db, now, location_id=None):
    sql = '''SELECT p.*, l.name AS location_name
             FROM promos p JOIN locations l ON l.id=p.location_id
             WHERE p.active=1 AND l.active=1 AND p.starts_at<=? AND p.ends_at>=?'''
    params = [now, now]
    if location_id:
        sql += ' AND p.location_id=?'
        params.append(location_id)
    sql += ' ORDER BY p.ends_at ASC, p.created_at DESC'
    rows = db.execute(sql, params).fetchall()
    return [
        {**dict(r), 'active': bool(r['active'])}
        for r in rows
    ]


def ev_bookings_list(db, owner):
    rows = db.execute(
        '''SELECT b.*, l.name AS location_name, l.address AS location_address
           FROM ev_bookings b JOIN locations l ON l.id=b.location_id
           WHERE b.owner=? ORDER BY b.booked_at DESC, b.id DESC LIMIT 30''',
        (owner,),
    ).fetchall()
    return [dict(r) for r in rows]


def ev_promo_dispatch(store, db, method, path, query, data, token, now, owner):
    from .store import uid

    if path == '/api/promos' and method == 'GET':
        req_loc = query.get('location_id', [''])[0] or None
        return {'promos': active_promos_list(db, now, req_loc)}

    if path == '/api/admin/promos':
        officer = store._officer_row(db, token, now)
        if officer['role'] not in ('ADMIN', 'SUPERADMIN'):
            raise RuleError('Hanya pengelola atau superadmin yang dapat mengelola promo.', 'forbidden', 403)
        if method == 'GET':
            req_loc = query.get('location_id', [''])[0] or None
            if officer['role'] == 'SUPERADMIN' and not req_loc:
                rows = db.execute(
                    '''SELECT p.*, l.name AS location_name
                       FROM promos p JOIN locations l ON l.id=p.location_id
                       ORDER BY p.created_at DESC'''
                ).fetchall()
            else:
                loc_id = store._location_for_staff(officer, req_loc)
                rows = db.execute(
                    '''SELECT p.*, l.name AS location_name
                       FROM promos p JOIN locations l ON l.id=p.location_id
                       WHERE p.location_id=? ORDER BY p.created_at DESC''',
                    (loc_id,),
                ).fetchall()
            return {'promos': [{**dict(r), 'active': bool(r['active'])} for r in rows]}
        if method == 'POST':
            def save_promo():
                loc_id = store._location_for_staff(officer, data.get('location_id'))
                get_location(db, loc_id)
                title = str(data.get('title', '')).strip()
                description = str(data.get('description', '')).strip()
                code = str(data.get('code', '')).strip().upper()
                discount_type = data.get('discount_type', 'PERCENT')
                discount_value = data.get('discount_value')
                starts_at = data.get('starts_at')
                ends_at = data.get('ends_at')
                active = data.get('active', True)
                if not title or len(title) > 80:
                    raise RuleError('Judul promo wajib diisi (maksimal 80 karakter).', 'promo', 400)
                if len(description) > 240 or len(code) > 24:
                    raise RuleError('Deskripsi maksimal 240 karakter dan kode maksimal 24 karakter.', 'promo', 400)
                if discount_type not in ('PERCENT', 'FIXED'):
                    raise RuleError('Jenis diskon harus PERCENT atau FIXED.', 'promo', 400)
                if type(discount_value) is not int or (
                    discount_type == 'PERCENT' and not (1 <= discount_value <= 100)
                ) or (
                    discount_type == 'FIXED' and not (500 <= discount_value <= 1000000)
                ):
                    raise RuleError('Nilai diskon tidak valid (persen 1–100 atau nominal Rp500–Rp1.000.000).', 'promo', 400)
                if not isinstance(starts_at, (int, float)) or not isinstance(ends_at, (int, float)) or ends_at <= starts_at:
                    raise RuleError('Waktu berakhir promo harus setelah waktu mulai.', 'promo', 400)
                if type(active) is not bool:
                    raise RuleError('Status promo tidak valid.', 'promo', 400)
                promo_id = data.get('id')
                if promo_id:
                    old = db.execute('SELECT * FROM promos WHERE id=?', (promo_id,)).fetchone()
                    if not old:
                        raise RuleError('Promo tidak ditemukan.', 'promo_not_found', 404)
                    if officer['role'] != 'SUPERADMIN' and old['location_id'] != loc_id:
                        raise RuleError('Promo ini milik lokasi lain.', 'location_forbidden', 403)
                    db.execute(
                        '''UPDATE promos SET location_id=?, title=?, description=?, code=?,
                           discount_type=?, discount_value=?, starts_at=?, ends_at=?, active=?
                           WHERE id=?''',
                        (loc_id, title, description, code, discount_type, discount_value,
                         float(starts_at), float(ends_at), int(active), promo_id),
                    )
                    store.audit(db, 'PROMO_UPDATED', promo_id, officer['id'], now, title, location_id=loc_id)
                else:
                    promo_id = uid('PRM')
                    db.execute(
                        '''INSERT INTO promos
                           (id, location_id, title, description, code, discount_type, discount_value,
                            starts_at, ends_at, active, created_by, created_at)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                        (promo_id, loc_id, title, description, code, discount_type, discount_value,
                         float(starts_at), float(ends_at), int(active), officer['id'], now),
                    )
                    store.audit(db, 'PROMO_CREATED', promo_id, officer['id'], now, title, location_id=loc_id)
                saved = db.execute(
                    'SELECT p.*, l.name AS location_name FROM promos p JOIN locations l ON l.id=p.location_id WHERE p.id=?',
                    (promo_id,),
                ).fetchone()
                return {'promo': {**dict(saved), 'active': bool(saved['active'])}}
            return store._operation(db, 'promo_save', data, officer['id'], now, save_promo)

    if path == '/api/ev/bookings' and method == 'GET':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        return {'bookings': ev_bookings_list(db, owner)}

    if path == '/api/ev/book' and method == 'POST':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        def book_ev():
            loc_id = data.get('location_id') or DEFAULT_LOCATION_ID
            loc = get_location(db, loc_id)
            if not loc['active']:
                raise RuleError('Lokasi parkir sedang nonaktif.', 'location_inactive', 409)
            p = plate(data.get('plate'))
            hours = data.get('duration_hours', 1)
            if type(hours) is not int or not (1 <= hours <= 12):
                raise RuleError('Durasi charging EV harus 1 hingga 12 jam.', 'duration', 400)
            veh = db.execute(
                'SELECT vehicle_type, is_ev FROM vehicle_categories WHERE owner=? AND plate=?',
                (owner, p),
            ).fetchone()
            if not veh or not veh['is_ev']:
                raise RuleError(
                    'Booking EV hanya untuk kendaraan plat nomor biru yang sudah terdaftar.',
                    'ev_plate_required', 400,
                )
            if db.execute(
                "SELECT 1 FROM ev_bookings WHERE plate=? AND status='ACTIVE'",
                (p,),
            ).fetchone():
                raise RuleError('Kendaraan ini sudah memiliki booking EV aktif.', 'ev_duplicate', 409)
            used = db.execute(
                "SELECT count(*) FROM ev_bookings WHERE location_id=? AND status='ACTIVE'",
                (loc_id,),
            ).fetchone()[0]
            if used >= int(loc.get('ev_capacity', 0)):
                raise RuleError('Slot EV Charging di lokasi ini sedang penuh.', 'ev_full', 409)
            bid = uid('EVB')
            rate = int(loc.get('ev_rate', 10000))
            cost = rate * hours
            db.execute(
                '''INSERT INTO ev_bookings
                   (id, location_id, owner, plate, duration_hours, hourly_rate, estimated_cost, status, booked_at, expires_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, 'ACTIVE', ?, ?)''',
                (bid, loc_id, owner, p, hours, rate, cost, now, now + hours * 3600),
            )
            store.audit(db, 'EV_BOOKED', bid, owner, now, p, location_id=loc_id)
            row = db.execute(
                '''SELECT b.*, l.name AS location_name, l.address AS location_address
                   FROM ev_bookings b JOIN locations l ON l.id=b.location_id WHERE b.id=?''',
                (bid,),
            ).fetchone()
            return {'booking': dict(row)}
        res = store._operation(db, 'ev_book', data, owner, now, book_ev)
        return {**res, 'bookings': ev_bookings_list(db, owner)}

    if path == '/api/ev/cancel' and method == 'POST':
        if owner is None:
            raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
        def cancel_ev():
            bid = data.get('booking_id')
            row = db.execute('SELECT * FROM ev_bookings WHERE id=? AND owner=?', (bid, owner)).fetchone()
            if not row:
                raise RuleError('Booking EV tidak ditemukan.', 'not_found', 404)
            if row['status'] != 'ACTIVE':
                return {'cancelled': True, 'booking_id': bid}
            db.execute("UPDATE ev_bookings SET status='CANCELLED' WHERE id=?", (bid,))
            store.audit(db, 'EV_CANCELLED', bid, owner, now, row['plate'], location_id=row['location_id'])
            return {'cancelled': True, 'booking_id': bid}
        res = store._operation(db, 'ev_cancel', data, owner, now, cancel_ev)
        return {**res, 'bookings': ev_bookings_list(db, owner)}

    return None
