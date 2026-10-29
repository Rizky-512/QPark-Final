"""Seeded fictitious visits, never written to operational parking tables."""
from datetime import datetime
import heapq
import json
import random
from .data import WIB, iso, timestamp


def generate(start='2026-08-24T00:00:00+07:00', days=56, seed=512):
    if type(days) is not int or not 2 <= days <= 366:
        raise ValueError('Simulasi memerlukan 2-366 hari.')
    start = timestamp(start)
    end = start + days*86400
    rng = random.Random(seed)
    active, sessions = [], []
    for t in range(int(start), int(end), 300):
        while active and active[0] <= t:
            heapq.heappop(active)
        dt = datetime.fromtimestamp(t, WIB)
        probability = .60 if 7 <= dt.hour < 18 else .06
        if dt.weekday() >= 5:
            probability *= .6
        for _ in range(2):
            if rng.random() < probability and len(active) < 20:
                duration = rng.randint(3, 30)*300
                exit_at = t+duration
                heapq.heappush(active, exit_at)
                sessions.append(dict(id=f'SIM-{seed}-{len(sessions)+1:06d}', entered_at=t,
                                     exited_at=exit_at if exit_at <= end else None))
    return dict(source_kind='simulation', complete_history=True,
                generator=dict(version=1, seed=seed, start=iso(start), days=days),
                coverage=[dict(start=iso(start), end=iso(end), capacity=20)],
                capacity_changes=[], sessions=sessions)


def upload_sql(source, run_id):
    """Admin-only SQL, atomic and idempotent for this exact snapshot."""
    if source.get('source_kind') != 'simulation':
        raise ValueError('Uploader ini hanya menerima simulasi.')
    def literal(value):
        return "'" + str(value).replace("'", "''") + "'"
    # One JSON snapshot preserves coverage, provenance and exact timestamps;
    # the separate visits table supports SQL inspection/export without app joins.
    payload = json.dumps(source, separators=(',', ':'), allow_nan=False)
    return f"""BEGIN;
INSERT INTO qpark_ml.simulation_runs(run_id, snapshot)
VALUES ({literal(run_id)}, {literal(payload)}::jsonb)
ON CONFLICT (run_id) DO UPDATE SET snapshot = CASE
  WHEN qpark_ml.simulation_runs.snapshot = EXCLUDED.snapshot THEN EXCLUDED.snapshot
  ELSE NULL END; -- NOT NULL rejects accidental reuse with different data.
INSERT INTO qpark_ml.simulation_sessions(run_id, visit_id, entered_at, exited_at)
SELECT r.run_id, s->>'id', to_timestamp((s->>'entered_at')::double precision),
       to_timestamp((s->>'exited_at')::double precision)
FROM qpark_ml.simulation_runs r, jsonb_array_elements(r.snapshot->'sessions') s
WHERE r.run_id={literal(run_id)}
ON CONFLICT (run_id, visit_id) DO NOTHING;
COMMIT;
"""
