"""Separate capacity accounting and customer-supplied vehicle categories."""
from .rules import RuleError, plate


def capacity_view(db, settings):
    categories = {}
    for kind, key in [('MOBIL', 'car_capacity'), ('MOTOR', 'motor_capacity')]:
        used = db.execute("SELECT count(*) FROM sessions WHERE state!='COMPLETED' AND vehicle_type=?", (kind,)).fetchone()[0]
        total = settings[key]
        categories[kind] = dict(total=total, occupied=used, available=max(0, total-used), full=used >= total)
    return dict(total=sum(x['total'] for x in categories.values()),
                occupied=sum(x['occupied'] for x in categories.values()),
                available=sum(x['available'] for x in categories.values()),
                full=all(x['full'] for x in categories.values()), categories=categories,
                rates={'MOBIL': settings['car_rate'], 'MOTOR': settings['motor_rate']})


def category_request(store, db, method, path, query, data, token, now, owner):
    if path == '/api/officer/vehicle-type' and method == 'GET':
        store._officer(db, token, now)
        p = plate(query.get('plate', [''])[0])
        row = db.execute('SELECT vehicle_type FROM vehicle_categories WHERE plate=? LIMIT 1', (p,)).fetchone()
        return {'vehicle_type': row['vehicle_type'] if row else None}
    if path not in ('/api/customer/vehicle-types', '/api/customer/vehicle-type'):
        return None
    if owner is None:
        raise RuleError('Identitas pelanggan diperlukan.', 'customer_identity', 401)
    if method == 'GET' and path.endswith('vehicle-types'):
        return {'vehicle_types': {r['plate']: r['vehicle_type'] for r in db.execute('SELECT * FROM vehicle_categories WHERE owner=?', (owner,))}}
    p = plate(data.get('plate'))
    if method == 'POST' and data.get('remove') is True:
        db.execute('DELETE FROM vehicle_categories WHERE owner=? AND plate=?', (owner, p))
        return {'removed': True}
    kind = data.get('vehicle_type')
    if method != 'POST' or kind not in ('MOBIL', 'MOTOR'):
        raise RuleError('Pilih Mobil atau Motor.', 'vehicle', 400)
    if db.execute("SELECT 1 FROM sessions WHERE plate=? AND state!='COMPLETED' AND vehicle_type<>?", (p, kind)).fetchone():
        raise RuleError('Kategori tidak dapat berubah selama kendaraan sedang parkir.', 'vehicle_active', 409)
    if db.execute('SELECT 1 FROM vehicle_categories WHERE plate=? AND owner<>? AND vehicle_type<>?', (p, owner, kind)).fetchone():
        raise RuleError('Kategori nopol berbeda dari data tersimpan. Periksa nopol Anda.', 'vehicle_conflict', 409)
    db.execute('INSERT INTO vehicle_categories(owner,plate,vehicle_type) VALUES(?,?,?) ON CONFLICT(owner,plate) DO UPDATE SET vehicle_type=excluded.vehicle_type', (owner, p, kind))
    return {'vehicle_type': kind}
