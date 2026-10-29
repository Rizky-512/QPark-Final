"""Read-only extraction and research feature contract (15 minute grid, WIB)."""
from bisect import bisect_right
from contextlib import closing
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import sqlite3

WIB = timezone(timedelta(hours=7))
HORIZON = 1800
STEP = 900
FEATURES = ['occupied_now', 'arrivals_30m', 'departures_30m',
            'hour_sin', 'hour_cos'] + [f'day_{i}' for i in range(1, 7)]


def timestamp(value):
    if isinstance(value, str):
        dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if dt.tzinfo is None:
            raise ValueError('Timestamp ISO harus menyertakan zona waktu.')
        value = dt.timestamp()
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError('Timestamp harus finite.')
    datetime.fromtimestamp(value, WIB)  # reject out-of-range calendar values
    return float(value)


def iso(value):
    return datetime.fromtimestamp(value, WIB).isoformat()


def read_sqlite(path, coverage):
    """No Store/bootstrap/migration: SQLite explicitly rejects any writes."""
    with closing(sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)) as db:
        db.execute('PRAGMA query_only=ON')
        db.execute('BEGIN')
        sessions = [dict(id=r[0], entered_at=r[1], exited_at=r[2]) for r in
                    db.execute('SELECT id,entered_at,exited_at FROM sessions')]
        changes = []
        for at, result in db.execute("SELECT server_time,result FROM audit "
                                    "WHERE event_type='SETTINGS_CHANGED' ORDER BY server_time,rowid"):
            changes.append(dict(at=at, capacity=json.loads(result)['capacity']))
    return dict(coverage, sessions=sessions, capacity_changes=changes)


class History:
    def __init__(self, source, now):
        self.now = timestamp(now)
        if not isinstance(source, dict):
            raise ValueError('Snapshot harus objek JSON.')
        for key in ('coverage', 'sessions', 'capacity_changes'):
            if not isinstance(source.get(key, []), list) or any(
                    not isinstance(item, dict) for item in source.get(key, [])):
                raise ValueError('Coverage, sesi, dan audit harus berupa daftar objek.')
        if source.get('source_kind') not in ('operational', 'simulation'):
            raise ValueError('source_kind wajib operational atau simulation.')
        self.kind = source['source_kind']
        if source.get('complete_history') is not True:
            raise ValueError('Riwayat lengkap, termasuk sesi sebelum coverage, harus diverifikasi.')
        self.ranges = []
        for r in source.get('coverage', []):
            a, b = timestamp(r['start']), timestamp(r['end'])
            if a >= b or b > self.now or r.get('capacity') != 20:
                raise ValueError('Coverage harus teramati, berurutan, dan kapasitas tetap 20.')
            self.ranges.append((a, b))
        self.ranges.sort()
        if any(a < prev[1] for prev, (a, b) in zip(self.ranges, self.ranges[1:])):
            raise ValueError('Coverage tidak boleh tumpang tindih.')
        self.entered, self.exited = [], []
        seen = set()
        for s in source.get('sessions', []):
            # Reject the snapshot instead of dropping an invalid event and biasing occupancy.
            sid = s['id']
            if not isinstance(sid, str) or not sid or sid in seen:
                raise ValueError('ID kunjungan kosong/duplikat.')
            seen.add(sid)
            a = timestamp(s['entered_at'])
            b = None if s['exited_at'] is None else timestamp(s['exited_at'])
            if a > self.now or (b is not None and (b < a or b > self.now)):
                raise ValueError('Waktu sesi tidak valid/belum terjadi.')
            self.entered.append(a)
            if b is not None:
                self.exited.append(b)
        self.entered.sort()
        self.exited.sort()
        self.changes = []
        for c in source.get('capacity_changes', []):
            at = timestamp(c['at'])
            cap = c['capacity']
            if type(cap) is not int or cap < 1 or at > self.now:
                raise ValueError('Audit kapasitas tidak valid.')
            self.changes.append((at, cap))
        self.changes.sort(key=lambda x: x[0])
        # Verify every event within coverage, not only sampled grid points.
        for t in sorted(set(self.entered + self.exited)):
            if any(a <= t <= b for a, b in self.ranges) and not 0 <= self.occupied(t) <= 20:
                raise ValueError('Keterisian di luar kapasitas; audit riwayat diperlukan.')

    def occupied(self, t):
        return bisect_right(self.entered, t) - bisect_right(self.exited, t)

    def covered(self, t, future=True):
        end = t + HORIZON if future else t
        if not any(a <= t-HORIZON and end <= b for a, b in self.ranges):
            return False
        # Manifest attests capacity at range start; audit can invalidate it.
        past = [cap for at, cap in self.changes if at <= t-HORIZON]
        return (not past or past[-1] == 20) and not any(
            t-HORIZON < at <= end and cap != 20 for at, cap in self.changes)

    def features(self, t):
        dt = datetime.fromtimestamp(t, WIB)
        angle = 2 * math.pi * (dt.hour + dt.minute/60 + dt.second/3600) / 24
        return [self.occupied(t),
                bisect_right(self.entered, t)-bisect_right(self.entered, t-HORIZON),
                bisect_right(self.exited, t)-bisect_right(self.exited, t-HORIZON),
                math.sin(angle), math.cos(angle)] + [int(dt.weekday() == i) for i in range(1, 7)]

    def dataset(self):
        rows = []
        rejected = 0
        for a, b in self.ranges:
            t = math.ceil((a+HORIZON)/STEP)*STEP
            while t+HORIZON <= b:
                if self.covered(t):
                    x, y = self.features(t), self.occupied(t+HORIZON)
                    if not 0 <= x[0] <= 20 or not 0 <= y <= 20:
                        raise ValueError('Keterisian di luar kapasitas.')
                    rows.append(dict(observed_at=t, target_at=t+HORIZON, x=x, y=y))
                else:
                    rejected += 1
                t += STEP
        return rows, rejected
