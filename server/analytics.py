"""Descriptive parking analytics. Calendar boundaries use WIB (UTC+7)."""
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from statistics import mean, median
import json
from .rules import RuleError

WIB = timezone(timedelta(hours=7))
DAYS = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu']

def parking_analytics(store, db, query, now):
    today = datetime.fromtimestamp(now, WIB).date()
    try:
        first = datetime.strptime(query.get('from', [str(today-timedelta(days=6))])[0], '%Y-%m-%d').date()
        last = datetime.strptime(query.get('to', [str(today)])[0], '%Y-%m-%d').date()
        if first > last or last > today or (last-first).days >= 366:
            raise ValueError()
    except (ValueError, TypeError):
        raise RuleError('Pilih periode valid, maksimal 366 hari dan tidak melewati hari ini.', 'period', 400)
    start = datetime.combine(first, datetime.min.time(), WIB).timestamp()
    end = min(datetime.combine(last+timedelta(days=1), datetime.min.time(), WIB).timestamp(), now)
    coverage = min(now, db.execute('SELECT min(applied_at) FROM migrations').fetchone()[0] or now,
                   db.execute('SELECT min(entered_at) FROM sessions').fetchone()[0] or now)
    observed_start = max(start, coverage)
    def bucket(**labels):
        return dict(labels, arrivals=0, seconds=0.0, vehicle_seconds=0.0, ratio_seconds=0.0)
    daily = {str(first+timedelta(days=i)): bucket(date=str(first+timedelta(days=i))) for i in range((last-first).days+1)}
    hourly = [bucket(hour=i) for i in range(24)]
    weekdays = [bucket(day=i, label=DAYS[i]) for i in range(7)]
    heatmap = [bucket(day=d, hour=h) for d in range(7) for h in range(24)]
    vehicles = {'MOBIL':0, 'MOTOR':0}
    durations = []
    entrants = db.execute('SELECT entered_at,exited_at,state,vehicle_type FROM sessions WHERE entered_at>=? AND entered_at<?', (start,end)).fetchall()
    for s in entrants:
        dt = datetime.fromtimestamp(s['entered_at'], WIB)
        for b in (daily[str(dt.date())],hourly[dt.hour],weekdays[dt.weekday()]):
            b['arrivals'] += 1
        if s['vehicle_type'] in vehicles:
            vehicles[s['vehicle_type']] += 1
        if s['state']=='COMPLETED' and s['exited_at'] is not None and s['exited_at']>=s['entered_at']:
            durations.append((s['exited_at']-s['entered_at'])/60)
    payments = {k:{'count':0,'amount':0} for k in ('QR_SIMULASI','MANUAL')}
    for r in db.execute("SELECT payment_method,count(*) n,sum(amount) amount FROM invoices WHERE state='PAID' AND paid_at>=? AND paid_at<? GROUP BY payment_method",(start,end)):
        if r['payment_method'] in payments:
            payments[r['payment_method']]={'count':r['n'],'amount':r['amount']}
    events = defaultdict(int)
    if observed_start < end:
        for s in db.execute('SELECT entered_at,exited_at FROM sessions WHERE entered_at<? AND (exited_at IS NULL OR exited_at>?)',(end,observed_start)):
            a, b = max(observed_start,s['entered_at']), min(end,s['exited_at'] if s['exited_at'] is not None else end)
            if a < b:
                events[a] += 1
                events[b] -= 1
    capacities = {}
    cap_rows = db.execute("SELECT server_time,result FROM audit WHERE event_type='SETTINGS_CHANGED' ORDER BY server_time,rowid").fetchall()
    # v4 starts with 20 spaces; subsequent capacity changes are audited.
    capacity = 20 if cap_rows else store.settings(db)['capacity']
    for r in cap_rows:
        try:
            c = int(json.loads(r['result'])['capacity'])
        except (ValueError,KeyError,TypeError):
            continue
        if c < 1:
            continue
        if r['server_time']<=observed_start:
            capacity=c
        elif r['server_time']<end:
            capacities[r['server_time']]=c
    cuts={observed_start,end,*events.keys(),*capacities.keys()}
    cursor=datetime.fromtimestamp(observed_start,WIB).replace(minute=0,second=0,microsecond=0)+timedelta(hours=1)
    while cursor.timestamp()<end:
        cuts.add(cursor.timestamp())
        cursor+=timedelta(hours=1)
    cuts=sorted(cuts)
    occupied=0
    peak=0
    total=bucket()
    if observed_start < end:
        for a,b in zip(cuts,cuts[1:]):
            occupied+=events[a]
            capacity=capacities.get(a,capacity)
            dt=datetime.fromtimestamp(a,WIB)
            seconds=b-a
            peak=max(peak,occupied)
            for row in (total,daily[str(dt.date())],hourly[dt.hour],weekdays[dt.weekday()],heatmap[dt.weekday()*24+dt.hour]):
                row['seconds']+=seconds
                row['vehicle_seconds']+=occupied*seconds
                row['ratio_seconds']+=occupied/capacity*seconds
    def finish(row):
        seconds=row.pop('seconds')
        vs=row.pop('vehicle_seconds')
        rs=row.pop('ratio_seconds')
        return dict(row, observed_hours=round(seconds/3600,4),avg_occupied=round(vs/seconds,4) if seconds else None,
                    occupancy_pct=round(rs/seconds*100,4) if seconds else None)
    daily=[finish(b) for b in daily.values()]
    hourly=[finish(b) for b in hourly]
    weekdays=[finish(b) for b in weekdays]
    heatmap=[finish(b) for b in heatmap]
    total=finish(total)
    candidates=[b for b in heatmap if (b['occupancy_pct'] or 0)>0]
    busiest=max(candidates,key=lambda b:b['occupancy_pct']) if candidates else None
    if busiest:
        busiest=dict(busiest,label=DAYS[busiest['day']])
    return dict(from_date=str(first),to_date=str(last),timezone='Asia/Jakarta',coverage_start=coverage,coverage_end=end,
                arrivals=len(entrants),completed_count=len(durations),excluded_active_count=len(entrants)-len(durations),
                mean_minutes=round(mean(durations),2) if durations else None,median_minutes=round(median(durations),2) if durations else None,
                vehicles=vehicles,payments=payments,daily=daily,hourly=hourly,weekdays=weekdays,heatmap=heatmap,
                occupancy_pct=total['occupancy_pct'],avg_occupied=total['avg_occupied'],peak_occupied=peak,busiest=busiest)
