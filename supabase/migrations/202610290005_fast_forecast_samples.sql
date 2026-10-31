-- Reduce forecast runtime for the application REST API timeout budget.
begin;

create index if not exists qpark_sessions_entered_forecast_idx on public.qpark_parking_sessions(entered_at);
create index if not exists qpark_sessions_exited_forecast_idx on public.qpark_parking_sessions(exited_at);

create or replace function public.qpark_analytics(p_query jsonb, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  today date := (p_now at time zone 'Asia/Jakarta')::date;
  first_day date := coalesce(nullif(p_query->>'from','')::date, today - 6);
  last_day date := coalesce(nullif(p_query->>'to','')::date, today);
  start_at timestamptz;
  end_at timestamptz;
  arrivals integer;
  completed integer;
  mean_minutes numeric;
  median_minutes numeric;
  cars integer;
  motors integer;
  peak integer;
  qr_count integer;
  qr_amount bigint;
  manual_count integer;
  manual_amount bigint;
  daily jsonb;
  hourly jsonb;
  weekdays jsonb;
  heatmap jsonb;
  forecast jsonb;
begin
  if first_day > last_day or last_day > today or last_day-first_day >= 366 then
    perform public.qpark_fail('Pilih periode valid, maksimal 366 hari dan tidak melewati hari ini.', 'period', 400);
  end if;
  start_at := (first_day::text || ' 00:00:00+07')::timestamptz;
  end_at := least(((last_day+1)::text || ' 00:00:00+07')::timestamptz, p_now);

  select count(*), count(*) filter(where state='COMPLETED'),
    round(avg(extract(epoch from (exited_at-entered_at))/60) filter(where state='COMPLETED'),2),
    round(percentile_cont(.5) within group(order by extract(epoch from (exited_at-entered_at))/60) filter(where state='COMPLETED')::numeric,2),
    count(*) filter(where vehicle_type='MOBIL'), count(*) filter(where vehicle_type='MOTOR')
  into arrivals,completed,mean_minutes,median_minutes,cars,motors
  from public.qpark_parking_sessions where entered_at>=start_at and entered_at<end_at;

  select count(*) filter(where payment_method='QR_SIMULASI'),
    coalesce(sum(amount) filter(where payment_method='QR_SIMULASI'),0),
    count(*) filter(where payment_method='MANUAL'),
    coalesce(sum(amount) filter(where payment_method='MANUAL'),0)
  into qr_count,qr_amount,manual_count,manual_amount
  from public.qpark_invoices where state='PAID' and paid_at>=start_at and paid_at<end_at;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date', d::text, 'arrivals', (select count(*) from public.qpark_parking_sessions s where (s.entered_at at time zone 'Asia/Jakarta')::date=d),
    'observed_hours', null, 'avg_occupied', null, 'occupancy_pct', null
  ) order by d),'[]'::jsonb) into daily from generate_series(first_day,last_day,'1 day') d;

  select jsonb_agg(jsonb_build_object(
    'hour', h, 'arrivals', (select count(*) from public.qpark_parking_sessions s where s.entered_at>=start_at and s.entered_at<end_at and extract(hour from s.entered_at at time zone 'Asia/Jakarta')=h),
    'observed_hours', null, 'avg_occupied', null, 'occupancy_pct', null
  ) order by h) into hourly from generate_series(0,23) h;

  select jsonb_agg(jsonb_build_object(
    'day', d, 'label', (array['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'])[d+1],
    'arrivals', (select count(*) from public.qpark_parking_sessions s where s.entered_at>=start_at and s.entered_at<end_at and extract(isodow from s.entered_at at time zone 'Asia/Jakarta')-1=d),
    'observed_hours', null, 'avg_occupied', null, 'occupancy_pct', null
  ) order by d) into weekdays from generate_series(0,6) d;

  select jsonb_agg(jsonb_build_object('day',d,'hour',h,'arrivals',0,'observed_hours',null,'avg_occupied',null,'occupancy_pct',null) order by d,h)
  into heatmap from generate_series(0,6) d cross join generate_series(0,23) h;

  select count(*) into peak from public.qpark_parking_sessions where state<>'COMPLETED';
  -- Complete features/targets every 15 minutes, independent of report filters.
  -- Restart history after settings changes to avoid mixing capacity regimes.
  -- Sweep each entry/exit once, then sample cumulative counts on the grid.
  -- This avoids thousands of repeated scans of the transaction history.
  with settings as (
    select capacity, greatest(started_at, updated_at, p_now-interval '56 days') as since
    from public.qpark_settings where singleton
  ), initial as (
    select count(*) as n from public.qpark_parking_sessions s cross join settings c
    where s.entered_at<=c.since and (s.exited_at is null or s.exited_at>c.since)
  ), events as (
    select s.entered_at as t, 1 as da, 0 as dd, false as is_grid
    from public.qpark_parking_sessions s cross join settings c
    where s.entered_at>c.since and s.entered_at<=p_now
    union all
    select s.exited_at, 0, 1, false
    from public.qpark_parking_sessions s cross join settings c
    where s.exited_at>c.since and s.exited_at<=p_now
    union all
    select g.t, 0, 0, true from settings c
    cross join lateral generate_series(c.since,p_now,interval '15 minutes') as g(t)
  ), timeline as (
    select e.t,sum(e.da) as da,sum(e.dd) as dd,bool_or(e.is_grid) as is_grid
    from events e group by e.t
  ), running as (
    select t.t,t.is_grid,
      sum(t.da) over(order by t.t rows unbounded preceding) as a,
      sum(t.dd) over(order by t.t rows unbounded preceding) as d
    from timeline t
  ), grid_counts as (
    select r.t,i.n+r.a-r.d as n,r.a,r.d from running r cross join initial i
    where r.is_grid
  ), observations as (
    select g.t,g.n,lead(g.n,2) over w as future_n,
      g.a-lag(g.a,2) over w as arrivals,g.d-lag(g.d,2) over w as departures
    from grid_counts g window w as (order by g.t)
  ) select jsonb_build_object(
    'version',2,
    'capacity',settings.capacity,
    'current',(select count(*) from public.qpark_parking_sessions s where s.entered_at<=p_now and (s.exited_at is null or s.exited_at>p_now)),
    'target_time',public.qpark_epoch(p_now+interval '30 minutes'),
    'live',jsonb_build_array(
      (select count(*) from public.qpark_parking_sessions s where s.entered_at<=p_now and (s.exited_at is null or s.exited_at>p_now)),
      (select count(*) from public.qpark_parking_sessions s where s.entered_at>p_now-interval '30 minutes' and s.entered_at<=p_now),
      (select count(*) from public.qpark_parking_sessions s where s.exited_at>p_now-interval '30 minutes' and s.exited_at<=p_now),
      public.qpark_epoch(p_now)),
    'samples',coalesce((select jsonb_agg(jsonb_build_array(o.n,o.future_n,o.arrivals,o.departures,public.qpark_epoch(o.t)) order by o.t) from observations o where o.arrivals is not null and o.future_n is not null),'[]'::jsonb)
  ) into forecast from settings;
  return jsonb_build_object(
    'forecast',forecast,
    'from_date',first_day::text,'to_date',last_day::text,'timezone','Asia/Jakarta',
    'coverage_start',public.qpark_epoch((select started_at from public.qpark_settings where singleton)),
    'coverage_end',public.qpark_epoch(end_at),'arrivals',arrivals,'completed_count',completed,
    'excluded_active_count',arrivals-completed,'mean_minutes',mean_minutes,'median_minutes',median_minutes,
    'vehicles',jsonb_build_object('MOBIL',cars,'MOTOR',motors),
    'payments',jsonb_build_object(
      'QR_SIMULASI',jsonb_build_object('count',qr_count,'amount',qr_amount),
      'MANUAL',jsonb_build_object('count',manual_count,'amount',manual_amount)
    ),
    'daily',daily,'hourly',hourly,'weekdays',weekdays,'heatmap',heatmap,
    'occupancy_pct',null,'avg_occupied',null,'peak_occupied',peak,'busiest',null
  );
exception when invalid_text_representation then
  perform public.qpark_fail('Pilih periode valid, maksimal 366 hari dan tidak melewati hari ini.', 'period', 400);
  return null;
end;
$$;


revoke all on function public.qpark_analytics(jsonb,timestamptz) from public;

commit;
