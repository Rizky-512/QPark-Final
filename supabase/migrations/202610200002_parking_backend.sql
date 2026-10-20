begin;

create extension if not exists pgcrypto;

create table if not exists public.qpark_staff (
  id uuid primary key default gen_random_uuid(),
  username text not null unique check (username = lower(username) and length(username) between 1 and 40),
  password_hash text not null,
  role text not null check (role in ('ADMIN', 'PETUGAS')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.qpark_staff_sessions (
  token_hash text primary key,
  staff_id uuid not null references public.qpark_staff(id) on delete cascade,
  expires_at timestamptz not null,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.qpark_settings (
  singleton boolean primary key default true check (singleton),
  capacity integer not null check (capacity between 1 and 1000000),
  car_rate integer not null check (car_rate between 1 and 1000000),
  motor_rate integer not null check (motor_rate between 1 and 1000000),
  qr_secret text not null,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.qpark_parking_sessions (
  id text primary key,
  plate text not null check (plate ~ '^[A-Z0-9]{1,32}$'),
  vehicle_type text not null check (vehicle_type in ('MOBIL', 'MOTOR')),
  hourly_rate integer not null check (hourly_rate > 0),
  entered_at timestamptz not null,
  entered_by uuid not null references public.qpark_staff(id),
  state text not null check (state in ('IN_AREA', 'EXIT_AUTHORIZED', 'COMPLETED')),
  exited_at timestamptz,
  exited_by uuid references public.qpark_staff(id)
);

create unique index if not exists qpark_active_plate_idx
  on public.qpark_parking_sessions(plate) where state <> 'COMPLETED';
create index if not exists qpark_sessions_state_entered_idx
  on public.qpark_parking_sessions(state, entered_at desc);

create table if not exists public.qpark_invoices (
  id text primary key,
  session_id text not null references public.qpark_parking_sessions(id) on delete cascade,
  kind text not null check (kind in ('BASE', 'PENALTY')),
  amount integer not null check (amount > 0),
  hours integer not null check (hours > 0),
  duration_seconds double precision not null default 0 check (duration_seconds >= 0),
  issued_at timestamptz not null,
  expires_at timestamptz,
  state text not null check (state in ('PENDING', 'PAID', 'EXPIRED')),
  window_id text unique,
  paid_at timestamptz,
  payment_method text check (payment_method in ('QR_SIMULASI', 'MANUAL')),
  received integer,
  change_amount integer,
  paid_by text
);

create unique index if not exists qpark_base_open_idx
  on public.qpark_invoices(session_id) where kind = 'BASE' and state = 'PENDING';
create unique index if not exists qpark_base_paid_idx
  on public.qpark_invoices(session_id) where kind = 'BASE' and state = 'PAID';

create table if not exists public.qpark_payment_attempts (
  id text primary key,
  invoice_id text not null references public.qpark_invoices(id) on delete cascade,
  operation_key text not null unique,
  outcome text not null check (outcome in ('PENDING', 'SUCCESS', 'FAILED')),
  server_time timestamptz not null
);

create unique index if not exists qpark_invoice_success_idx
  on public.qpark_payment_attempts(invoice_id) where outcome = 'SUCCESS';

create table if not exists public.qpark_exit_windows (
  id text primary key,
  session_id text not null references public.qpark_parking_sessions(id) on delete cascade,
  invoice_id text not null unique references public.qpark_invoices(id) on delete cascade,
  sequence integer not null,
  paid_at timestamptz not null,
  deadline timestamptz not null,
  token_hash text not null unique,
  unique (session_id, sequence)
);

alter table public.qpark_invoices
  drop constraint if exists qpark_invoices_window_fk;
alter table public.qpark_invoices
  add constraint qpark_invoices_window_fk foreign key (window_id)
  references public.qpark_exit_windows(id) deferrable initially deferred;

create table if not exists public.qpark_authorizations (
  id text primary key,
  session_id text not null references public.qpark_parking_sessions(id) on delete cascade,
  window_id text not null references public.qpark_exit_windows(id) on delete cascade,
  approved_by uuid not null references public.qpark_staff(id),
  approved_at timestamptz not null,
  expires_at timestamptz not null,
  state text not null check (state in ('ACTIVE', 'EXPIRED', 'CANCELLED', 'COMPLETED'))
);

create unique index if not exists qpark_one_authorization_idx
  on public.qpark_authorizations(session_id) where state = 'ACTIVE';

create table if not exists public.qpark_operations (
  key text primary key,
  action text not null,
  fingerprint text not null,
  actor text not null,
  result jsonb not null,
  created_at timestamptz not null
);

create table if not exists public.qpark_audit (
  id uuid primary key default gen_random_uuid(),
  entity_id text not null,
  event_type text not null,
  actor text not null,
  server_time timestamptz not null,
  result text not null default 'OK'
);

insert into public.qpark_settings(singleton, capacity, car_rate, motor_rate, qr_secret)
values (true, 20, 7000, 2000, encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (singleton) do nothing;

insert into public.qpark_staff(username, password_hash, role)
values
  ('admin', extensions.crypt('admin123', extensions.gen_salt('bf')), 'ADMIN'),
  ('petugas', extensions.crypt('petugas123', extensions.gen_salt('bf')), 'PETUGAS')
on conflict (username) do nothing;

create or replace function public.qpark_fail(p_message text, p_code text default 'invalid', p_status integer default 409)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception '%', jsonb_build_object('error', p_message, 'code', p_code, 'status', p_status)::text
    using errcode = 'P0001';
end;
$$;

create or replace function public.qpark_id(p_prefix text)
returns text
language sql
volatile
set search_path = ''
as $$
  select p_prefix || '-' || replace(gen_random_uuid()::text, '-', '');
$$;

create or replace function public.qpark_epoch(p_value timestamptz)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select case when p_value is null then null else extract(epoch from p_value)::double precision end;
$$;

create or replace function public.qpark_plate(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  normalized text := upper(regexp_replace(coalesce(p_value, ''), '\s+', '', 'g'));
begin
  if normalized !~ '^[A-Z0-9]{1,32}$' then
    perform public.qpark_fail('Nopol harus 1–32 huruf atau angka, tanpa tanda baca.', 'plate', 400);
  end if;
  return normalized;
end;
$$;

create or replace function public.qpark_qr(p_window_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select 'QPX.' || p_window_id || '.' || encode(
    extensions.hmac(p_window_id, (select qr_secret from public.qpark_settings where singleton), 'sha256'),
    'hex'
  );
$$;

create or replace function public.qpark_audit_event(
  p_event text, p_entity text, p_actor text, p_now timestamptz, p_result text default 'OK'
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.qpark_audit(entity_id, event_type, actor, server_time, result)
  values (p_entity, p_event, p_actor, p_now, coalesce(p_result, 'OK'));
$$;

create or replace function public.qpark_staff_for_token(p_token text, p_now timestamptz, p_admin boolean default false)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  staff public.qpark_staff%rowtype;
begin
  select s.* into staff
  from public.qpark_staff_sessions ss
  join public.qpark_staff s on s.id = ss.staff_id
  where ss.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and not ss.revoked and ss.expires_at > p_now and s.active;
  if not found then
    perform public.qpark_fail('Sesi petugas tidak sah atau telah berakhir. Login kembali.', 'unauthorized', 401);
  end if;
  if p_admin and staff.role <> 'ADMIN' then
    perform public.qpark_fail('Hanya admin yang dapat mengelola akun dan pengaturan.', 'forbidden', 403);
  end if;
  return staff.id;
end;
$$;

create or replace function public.qpark_maintain(p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  item record;
  invoice_id text;
begin
  for item in
    select id, session_id from public.qpark_authorizations
    where state = 'ACTIVE' and expires_at <= p_now for update
  loop
    update public.qpark_authorizations set state = 'EXPIRED' where id = item.id;
    update public.qpark_parking_sessions set state = 'IN_AREA'
      where id = item.session_id and state = 'EXIT_AUTHORIZED';
    perform public.qpark_audit_event('AUTH_EXPIRED', item.id, 'SYSTEM', p_now);
  end loop;

  update public.qpark_invoices set state = 'EXPIRED'
  where kind = 'BASE' and state = 'PENDING' and expires_at <= p_now;

  for item in
    select s.id as session_id, s.hourly_rate, w.id as window_id
    from public.qpark_parking_sessions s
    join lateral (
      select * from public.qpark_exit_windows x
      where x.session_id = s.id order by sequence desc limit 1
    ) w on true
    where s.state = 'IN_AREA' and w.deadline < p_now
      and not exists (select 1 from public.qpark_invoices i where i.window_id = w.id)
    for update of s
  loop
    invoice_id := public.qpark_id('INV');
    insert into public.qpark_invoices(
      id, session_id, kind, amount, hours, duration_seconds,
      issued_at, state, window_id
    ) values (
      invoice_id, item.session_id, 'PENALTY', item.hourly_rate, 1, 0,
      p_now, 'PENDING', item.window_id
    );
    perform public.qpark_audit_event('PENALTY_CREATED', invoice_id, 'SYSTEM', p_now);
  end loop;
end;
$$;

create or replace function public.qpark_session_view(
  p_session_id text, p_now timestamptz, p_include_qr boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s public.qpark_parking_sessions%rowtype;
  w public.qpark_exit_windows%rowtype;
  a public.qpark_authorizations%rowtype;
  invoice_rows jsonb;
  amount_paid bigint;
  window_status text;
  payment_status text;
begin
  select * into s from public.qpark_parking_sessions where id = p_session_id;
  if not found then perform public.qpark_fail('Sesi parkir tidak ditemukan.', 'not_found', 404); end if;
  select * into w from public.qpark_exit_windows where session_id = s.id order by sequence desc limit 1;
  select * into a from public.qpark_authorizations where session_id = s.id and state = 'ACTIVE' limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'session_id', i.session_id, 'kind', i.kind, 'amount', i.amount,
    'hours', i.hours, 'duration', i.duration_seconds,
    'issued_at', public.qpark_epoch(i.issued_at), 'expires_at', public.qpark_epoch(i.expires_at),
    'state', i.state, 'window_id', i.window_id, 'paid_at', public.qpark_epoch(i.paid_at),
    'payment_method', i.payment_method, 'received', i.received,
    'change_amount', i.change_amount, 'paid_by', i.paid_by
  ) order by i.issued_at, i.id), '[]'::jsonb),
  coalesce(sum(i.amount) filter (where i.state = 'PAID'), 0)
  into invoice_rows, amount_paid
  from public.qpark_invoices i where i.session_id = s.id;

  window_status := case
    when w.id is null then 'NONE'
    when s.state = 'COMPLETED' then 'CONSUMED'
    when p_now <= w.deadline or a.id is not null then 'VALID'
    else 'EXPIRED'
  end;
  payment_status := case
    when s.state = 'COMPLETED' then 'Selesai'
    when exists(select 1 from public.qpark_invoices i where i.session_id=s.id and i.kind='PENALTY' and i.state='PENDING') then 'Tambahan belum dibayar'
    when w.id is not null then 'Lunas'
    else 'Belum dibayar'
  end;

  return jsonb_build_object(
    'id', s.id, 'plate', s.plate, 'vehicle_type', s.vehicle_type,
    'hourly_rate', s.hourly_rate, 'entered_at', public.qpark_epoch(s.entered_at),
    'entered_by', s.entered_by::text, 'state', s.state,
    'exited_at', public.qpark_epoch(s.exited_at), 'exited_by', case when s.exited_by is null then null else s.exited_by::text end,
    'invoices', invoice_rows, 'amount_paid', amount_paid,
    'duration_seconds', greatest(0, extract(epoch from (coalesce(s.exited_at, p_now) - s.entered_at))),
    'window_status', window_status, 'payment_status', payment_status,
    'window', case when w.id is null then null else jsonb_build_object(
      'id', w.id, 'session_id', w.session_id, 'invoice_id', w.invoice_id,
      'sequence', w.sequence, 'paid_at', public.qpark_epoch(w.paid_at),
      'deadline', public.qpark_epoch(w.deadline)
    ) end,
    'authorization', case when a.id is null then null else jsonb_build_object(
      'id', a.id, 'session_id', a.session_id, 'window_id', a.window_id,
      'approved_by', a.approved_by::text, 'approved_at', public.qpark_epoch(a.approved_at),
      'expires_at', public.qpark_epoch(a.expires_at), 'state', a.state
    ) end,
    'exit_qr', case when w.id is not null and window_status = 'VALID' and p_include_qr
      then public.qpark_qr(w.id) else null end,
    'server_time', public.qpark_epoch(p_now)
  );
end;
$$;

create or replace function public.qpark_operation_replay(
  p_key text, p_action text, p_actor text, p_body jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  old public.qpark_operations%rowtype;
  fingerprint text := encode(extensions.digest(coalesce(p_body, '{}'::jsonb)::text, 'sha256'), 'hex');
begin
  if p_key is null or length(p_key) < 8 or length(p_key) > 128 then
    perform public.qpark_fail('Kunci operasi wajib 8–128 karakter.', 'operation_key', 400);
  end if;
  select * into old from public.qpark_operations where key = p_key;
  if not found then return null; end if;
  if old.action <> p_action or old.actor <> p_actor or old.fingerprint <> fingerprint then
    perform public.qpark_fail('Kunci operasi telah dipakai untuk permintaan berbeda.', 'operation_conflict', 409);
  end if;
  return old.result;
end;
$$;

create or replace function public.qpark_operation_save(
  p_key text, p_action text, p_actor text, p_body jsonb, p_result jsonb, p_now timestamptz
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.qpark_operations(key, action, fingerprint, actor, result, created_at)
  values (p_key, p_action, encode(extensions.digest(coalesce(p_body, '{}'::jsonb)::text, 'sha256'), 'hex'), p_actor, p_result, p_now);
$$;

create or replace function public.qpark_history(p_query jsonb, p_public boolean, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  plate_filter text;
  query_filter text := upper(replace(coalesce(p_query->>'q', ''), ' ', ''));
  vehicle_filter text := nullif(p_query->>'vehicle', '');
  method_filter text := nullif(p_query->>'method', '');
  start_at timestamptz;
  end_at timestamptz;
  row_offset integer := greatest(0, coalesce((p_query->>'offset')::integer, 0));
  total_rows integer;
  revenue_total bigint;
  rows jsonb;
begin
  if p_public then plate_filter := public.qpark_plate(p_query->>'plate'); end if;
  if vehicle_filter is not null and vehicle_filter not in ('MOBIL','MOTOR') then
    perform public.qpark_fail('Jenis kendaraan tidak valid.', 'vehicle', 400);
  end if;
  if method_filter is not null and method_filter not in ('MANUAL','QR_SIMULASI') then
    perform public.qpark_fail('Metode tidak valid.', 'method', 400);
  end if;
  begin
    if nullif(p_query->>'from','') is not null then start_at := ((p_query->>'from') || ' 00:00:00+07')::timestamptz; end if;
    if nullif(p_query->>'to','') is not null then end_at := (((p_query->>'to')::date + 1)::text || ' 00:00:00+07')::timestamptz; end if;
  exception when others then
    perform public.qpark_fail('Tanggal atau halaman tidak valid.', 'filter', 400);
  end;

  with filtered as (
    select s.id from public.qpark_parking_sessions s
    where (not p_public or s.plate = plate_filter)
      and (p_public or query_filter = '' or position(query_filter in s.plate) > 0)
      and (vehicle_filter is null or s.vehicle_type = vehicle_filter)
      and (start_at is null or s.entered_at >= start_at)
      and (end_at is null or s.entered_at < end_at)
      and (method_filter is null or exists (
        select 1 from public.qpark_invoices i where i.session_id=s.id and i.state='PAID' and i.payment_method=method_filter
      ))
  ), page as (
    select s.id from public.qpark_parking_sessions s join filtered f on f.id=s.id
    order by s.entered_at desc, s.id desc limit 50 offset row_offset
  )
  select (select count(*) from filtered),
         coalesce((select sum(i.amount) from public.qpark_invoices i where i.state='PAID' and i.session_id in (select id from filtered)),0),
         coalesce((select jsonb_agg(public.qpark_session_view(id,p_now,false)) from page),'[]'::jsonb)
  into total_rows, revenue_total, rows;
  return jsonb_build_object('sessions',rows,'total',total_rows,'offset',row_offset,'revenue',revenue_total);
exception when invalid_text_representation then
  perform public.qpark_fail('Tanggal atau halaman tidak valid.', 'filter', 400);
  return null;
end;
$$;

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
  return jsonb_build_object(
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

create or replace function public.qpark_request(
  p_method text,
  p_path text,
  p_query jsonb default '{}'::jsonb,
  p_body jsonb default '{}'::jsonb,
  p_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_at timestamptz := clock_timestamp();
  now_epoch double precision;
  result jsonb;
  replay jsonb;
  actor uuid;
  actor_text text;
  staff public.qpark_staff%rowtype;
  settings public.qpark_settings%rowtype;
  parking public.qpark_parking_sessions%rowtype;
  invoice public.qpark_invoices%rowtype;
  window_row public.qpark_exit_windows%rowtype;
  auth_row public.qpark_authorizations%rowtype;
  operation_key text := p_body->>'operation_key';
  raw_token text;
  normalized_plate text;
  item_id text;
  hours_value integer;
  amount_value integer;
  sequence_value integer;
  outcome_value text;
  received_value integer;
  expected_value integer;
  active_count integer;
  existing_id text;
begin
  if p_body is null or jsonb_typeof(p_body) <> 'object' then
    perform public.qpark_fail('Payload JSON harus objek.', 'payload', 400);
  end if;
  now_epoch := public.qpark_epoch(now_at);
  perform public.qpark_maintain(now_at);

  if p_method='GET' and p_path='/api/health' then
    result := jsonb_build_object('service','qpark','version',6,'simulation',true);

  elsif p_method='POST' and p_path='/api/login' then
    select * into staff from public.qpark_staff
    where username=lower(trim(coalesce(p_body->>'username',''))) and active;
    if not found or staff.password_hash <> extensions.crypt(coalesce(p_body->>'password',''),staff.password_hash) then
      perform public.qpark_fail('Nama pengguna atau kata sandi tidak valid.', 'credentials', 401);
    end if;
    raw_token := encode(extensions.gen_random_bytes(32),'hex');
    insert into public.qpark_staff_sessions(token_hash,staff_id,expires_at)
      values(encode(extensions.digest(raw_token,'sha256'),'hex'),staff.id,now_at+interval '8 hours');
    perform public.qpark_audit_event('LOGIN',staff.id::text,staff.id::text,now_at);
    result := jsonb_build_object('token',raw_token,'username',staff.username,'role',staff.role,'expires_at',public.qpark_epoch(now_at+interval '8 hours'));

  elsif p_method='POST' and p_path='/api/logout' then
    update public.qpark_staff_sessions set revoked=true
      where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and not revoked
      returning staff_id into actor;
    if actor is not null then perform public.qpark_audit_event('LOGOUT',actor::text,actor::text,now_at); end if;
    result := jsonb_build_object('revoked',true);

  elsif p_method='GET' and p_path='/api/capacity' then
    select * into settings from public.qpark_settings where singleton;
    select count(*) into active_count from public.qpark_parking_sessions where state<>'COMPLETED';
    result := jsonb_build_object(
      'total',settings.capacity,'occupied',active_count,'available',greatest(0,settings.capacity-active_count),
      'full',active_count>=settings.capacity,'rates',jsonb_build_object('MOBIL',settings.car_rate,'MOTOR',settings.motor_rate)
    );

  elsif p_method='GET' and p_path='/api/ticket' then
    normalized_plate := public.qpark_plate(p_query->>'plate');
    select * into parking from public.qpark_parking_sessions where plate=normalized_plate and state<>'COMPLETED' limit 1;
    if not found and nullif(p_query->>'previous','') is not null then
      select * into parking from public.qpark_parking_sessions where id=p_query->>'previous' and plate=normalized_plate;
    end if;
    result := jsonb_build_object('session',case when parking.id is null then null else public.qpark_session_view(parking.id,now_at,true) end);

  elsif p_method='GET' and p_path='/api/history' then
    result := public.qpark_history(p_query,true,now_at);

  elsif p_method='POST' and p_path='/api/invoice' then
    select * into parking from public.qpark_parking_sessions where id=p_body->>'session_id' for update;
    if not found then perform public.qpark_fail('Sesi parkir tidak ditemukan.','not_found',404); end if;
    if parking.state='COMPLETED' then perform public.qpark_fail('Sesi telah selesai.','completed',409); end if;
    select * into invoice from public.qpark_invoices where session_id=parking.id and state='PENDING' order by issued_at limit 1;
    if not found and not exists(select 1 from public.qpark_exit_windows where session_id=parking.id) then
      hours_value := greatest(1,floor(extract(epoch from(now_at-parking.entered_at))/3600)::integer);
      amount_value := hours_value*parking.hourly_rate;
      item_id := public.qpark_id('INV');
      insert into public.qpark_invoices(id,session_id,kind,amount,hours,duration_seconds,issued_at,expires_at,state)
      values(item_id,parking.id,'BASE',amount_value,hours_value,extract(epoch from(now_at-parking.entered_at)),now_at,now_at+interval '5 minutes','PENDING')
      returning * into invoice;
      perform public.qpark_audit_event('INVOICE_CREATED',item_id,'DRIVER',now_at);
    end if;
    result := jsonb_build_object(
      'invoice',case when invoice.id is null then null else (public.qpark_session_view(parking.id,now_at,true)->'invoices')->-1 end,
      'session',public.qpark_session_view(parking.id,now_at,true)
    );

  elsif p_method='POST' and p_path='/api/payment' then
    replay := public.qpark_operation_replay(operation_key,'payment','DRIVER',p_body);
    if replay is not null then
      result := replay || jsonb_build_object('session',public.qpark_session_view(replay->>'session_id',now_at,true));
    else
      select * into invoice from public.qpark_invoices where id=p_body->>'invoice_id' for update;
      if not found then perform public.qpark_fail('Tagihan tidak ditemukan.','invoice',404); end if;
      if invoice.state='PAID' then
        select id into item_id from public.qpark_payment_attempts where invoice_id=invoice.id and outcome='SUCCESS' limit 1;
        result := jsonb_build_object('session_id',invoice.session_id,'invoice_id',invoice.id,'outcome','SUCCESS','attempt_id',item_id,'paid_at',public.qpark_epoch(invoice.paid_at));
      else
        if invoice.state='EXPIRED' or (invoice.expires_at is not null and now_at>=invoice.expires_at) then
          perform public.qpark_fail('Tagihan kedaluwarsa. Buka tagihan baru.','invoice_expired',409);
        end if;
        select * into parking from public.qpark_parking_sessions where id=invoice.session_id for update;
        if parking.state<>'IN_AREA' then perform public.qpark_fail('Sesi tidak dapat dibayar saat ini.','state',409); end if;
        outcome_value := p_body->>'outcome';
        if outcome_value not in ('PENDING','SUCCESS','FAILED') then perform public.qpark_fail('Hasil simulasi tidak valid.','outcome',400); end if;
        item_id := public.qpark_id('PAY');
        insert into public.qpark_payment_attempts(id,invoice_id,operation_key,outcome,server_time)
          values(item_id,invoice.id,operation_key,outcome_value,now_at);
        if outcome_value='SUCCESS' then
          update public.qpark_invoices set state='PAID',paid_at=now_at,payment_method='QR_SIMULASI',paid_by='DRIVER' where id=invoice.id;
          select coalesce(max(sequence),0)+1 into sequence_value from public.qpark_exit_windows where session_id=invoice.session_id;
          existing_id := public.qpark_id('WIN');
          raw_token := public.qpark_qr(existing_id);
          insert into public.qpark_exit_windows(id,session_id,invoice_id,sequence,paid_at,deadline,token_hash)
            values(existing_id,invoice.session_id,invoice.id,sequence_value,now_at,now_at+interval '15 minutes',encode(extensions.digest(raw_token,'sha256'),'hex'));
        end if;
        perform public.qpark_audit_event('PAYMENT_'||outcome_value,invoice.id,'DRIVER',now_at,'QR_SIMULASI');
        result := jsonb_build_object('session_id',invoice.session_id,'invoice_id',invoice.id,'outcome',outcome_value,'attempt_id',item_id,'paid_at',case when outcome_value='SUCCESS' then now_epoch else null end);
      end if;
      perform public.qpark_operation_save(operation_key,'payment','DRIVER',p_body,result,now_at);
      result := result || jsonb_build_object('session',public.qpark_session_view(invoice.session_id,now_at,true));
    end if;

  elsif p_path like '/api/admin/%' then
    actor := public.qpark_staff_for_token(p_token,now_at,true); actor_text := actor::text;
    if p_method='GET' and p_path='/api/admin/settings' then
      select * into settings from public.qpark_settings where singleton;
      result := jsonb_build_object('settings',jsonb_build_object('capacity',settings.capacity,'car_rate',settings.car_rate,'motor_rate',settings.motor_rate));
    elsif p_method='POST' and p_path='/api/admin/settings' then
      begin
        amount_value := (p_body->>'capacity')::integer;
        hours_value := (p_body->>'car_rate')::integer;
        sequence_value := (p_body->>'motor_rate')::integer;
      exception when others then perform public.qpark_fail('Isian harus bilangan bulat 1–1.000.000.','settings',400); end;
      if amount_value not between 1 and 1000000 or hours_value not between 1 and 1000000 or sequence_value not between 1 and 1000000 then
        perform public.qpark_fail('Isian harus bilangan bulat 1–1.000.000.','settings',400);
      end if;
      select count(*) into active_count from public.qpark_parking_sessions where state<>'COMPLETED';
      if amount_value<active_count then perform public.qpark_fail('Kapasitas tidak boleh di bawah jumlah kendaraan aktif.','capacity',409); end if;
      update public.qpark_settings set capacity=amount_value,car_rate=hours_value,motor_rate=sequence_value,updated_at=now_at where singleton;
      result := jsonb_build_object('settings',jsonb_build_object('capacity',amount_value,'car_rate',hours_value,'motor_rate',sequence_value));
      perform public.qpark_audit_event('SETTINGS_CHANGED','parking',actor_text,now_at,(result->'settings')::text);
    elsif p_method='GET' and p_path='/api/admin/users' then
      select jsonb_build_object('users',coalesce(jsonb_agg(jsonb_build_object(
        'id',id::text,'username',username,'role',role,'active',case when active then 1 else 0 end
      ) order by username),'[]'::jsonb)) into result from public.qpark_staff;
    elsif p_method='POST' and p_path='/api/admin/users' then
      replay := public.qpark_operation_replay(operation_key,'user_update',actor_text,p_body);
      if replay is not null then result:=replay;
      else
        normalized_plate := lower(trim(coalesce(p_body->>'username','')));
        if normalized_plate='' or length(normalized_plate)>40 or coalesce(p_body->>'role','') not in ('ADMIN','PETUGAS') then
          perform public.qpark_fail('Username atau peran tidak valid.','user',400);
        end if;
        if coalesce(p_body->>'password','')<>'' and length(p_body->>'password')<8 then perform public.qpark_fail('Password minimum delapan karakter.','password',400); end if;
        select * into staff from public.qpark_staff where username=normalized_plate for update;
        if found and staff.id=actor and ((p_body->>'active')::boolean=false or p_body->>'role'<>'ADMIN') then
          perform public.qpark_fail('Admin tidak dapat menonaktifkan atau menurunkan perannya sendiri.','self_change',409);
        end if;
        if not found and coalesce(p_body->>'password','')='' then perform public.qpark_fail('Password akun baru wajib diisi.','password',400); end if;
        if found then
          update public.qpark_staff set role=p_body->>'role',active=coalesce((p_body->>'active')::boolean,true),
            password_hash=case when coalesce(p_body->>'password','')='' then password_hash else extensions.crypt(p_body->>'password',extensions.gen_salt('bf')) end,
            updated_at=now_at where id=staff.id;
          if coalesce(p_body->>'password','')<>'' or coalesce((p_body->>'active')::boolean,true)=false or p_body->>'role'<>staff.role then
            update public.qpark_staff_sessions set revoked=true where staff_id=staff.id;
          end if;
          item_id:=staff.id::text;
        else
          insert into public.qpark_staff(username,password_hash,role,active)
          values(normalized_plate,extensions.crypt(p_body->>'password',extensions.gen_salt('bf')),p_body->>'role',coalesce((p_body->>'active')::boolean,true)) returning id::text into item_id;
        end if;
        result:=jsonb_build_object('updated',true);
        perform public.qpark_audit_event('USER_UPDATED',item_id,actor_text,now_at,p_body->>'role');
        perform public.qpark_operation_save(operation_key,'user_update',actor_text,p_body,result,now_at);
      end if;
    elsif p_method='GET' and p_path='/api/admin/analytics' then
      result := public.qpark_analytics(p_query,now_at);
    else perform public.qpark_fail('Endpoint tidak ditemukan.','not_found',404);
    end if;

  elsif p_path like '/api/officer/%' then
    actor := public.qpark_staff_for_token(p_token,now_at,false); actor_text := actor::text;
    if p_method='GET' and p_path='/api/officer/monitor' then
      select jsonb_build_object('sessions',coalesce(jsonb_agg(public.qpark_session_view(s.id,now_at,false) order by s.entered_at desc),'[]'::jsonb))
      into result from public.qpark_parking_sessions s
      where s.state<>'COMPLETED' and position(upper(replace(coalesce(p_query->>'q',''),' ','')) in s.plate)>0;
    elsif p_method='GET' and p_path='/api/officer/history' then
      result:=public.qpark_history(p_query,false,now_at);
    elsif p_method='POST' and p_path='/api/officer/entry' then
      replay:=public.qpark_operation_replay(operation_key,'entry',actor_text,p_body);
      if replay is not null then result:=replay||jsonb_build_object('session',public.qpark_session_view(replay->>'session_id',now_at,true));
      else
        normalized_plate:=public.qpark_plate(p_body->>'plate');
        if coalesce((p_body->>'verified')::boolean,false) is not true or not (
          p_body->>'image_source'='manual' or (coalesce((p_body->>'image_readable')::boolean,false) and p_body->>'image_source' in ('test_photo','camera'))
        ) then perform public.qpark_fail('Kendaraan wajib diverifikasi. Jika menggunakan gambar, pastikan gambar terbaca.','verification',400); end if;
        if coalesce(p_body->>'vehicle_type','') not in ('MOBIL','MOTOR') then perform public.qpark_fail('Pilih Mobil atau Motor.','vehicle',400); end if;
        select * into settings from public.qpark_settings where singleton for update;
        if exists(select 1 from public.qpark_parking_sessions where plate=normalized_plate and state<>'COMPLETED') then perform public.qpark_fail('Nopol masih memiliki sesi aktif.','duplicate_plate',409); end if;
        select count(*) into active_count from public.qpark_parking_sessions where state<>'COMPLETED';
        if active_count>=settings.capacity then perform public.qpark_fail('Area parkir penuh. Kendaraan ditolak.','full',409); end if;
        item_id:=public.qpark_id('QP');
        insert into public.qpark_parking_sessions(id,plate,vehicle_type,hourly_rate,entered_at,entered_by,state)
        values(item_id,normalized_plate,p_body->>'vehicle_type',case when p_body->>'vehicle_type'='MOTOR' then settings.motor_rate else settings.car_rate end,now_at,actor,'IN_AREA');
        result:=jsonb_build_object('session_id',item_id);
        perform public.qpark_audit_event('ENTRY',item_id,actor_text,now_at,p_body->>'image_source');
        perform public.qpark_operation_save(operation_key,'entry',actor_text,p_body,result,now_at);
        result:=result||jsonb_build_object('session',public.qpark_session_view(item_id,now_at,true));
      end if;
    elsif p_method='POST' and p_path='/api/officer/scan' then
      select w.* into window_row from public.qpark_exit_windows w where w.token_hash=encode(extensions.digest(coalesce(p_body->>'qr',''),'sha256'),'hex');
      if not found then perform public.qpark_fail('QR keluar tidak dikenal.','invalid_qr',409); end if;
      select * into parking from public.qpark_parking_sessions where id=window_row.session_id;
      if parking.state='COMPLETED' then perform public.qpark_fail('Sesi sudah selesai; QR tidak berlaku.','completed',409); end if;
      if window_row.id<>(select id from public.qpark_exit_windows where session_id=parking.id order by sequence desc limit 1) then perform public.qpark_fail('QR versi lama. Minta QR keluar terbaru.','old_qr',409); end if;
      if parking.state<>'EXIT_AUTHORIZED' and now_at>window_row.deadline then perform public.qpark_fail('Izin 15 menit habis. Lunasi tagihan tambahan sesuai tarif kendaraan.','window_expired',409); end if;
      result:=jsonb_build_object('session',public.qpark_session_view(parking.id,now_at,true));
    elsif p_method='POST' and p_path='/api/officer/authorize' then
      replay:=public.qpark_operation_replay(operation_key,'authorize',actor_text,p_body);
      if replay is not null then result:=replay||jsonb_build_object('session',public.qpark_session_view(replay->>'session_id',now_at,true));
      else
        select w.* into window_row from public.qpark_exit_windows w where w.token_hash=encode(extensions.digest(coalesce(p_body->>'qr',''),'sha256'),'hex');
        if not found then perform public.qpark_fail('QR keluar tidak dikenal.','invalid_qr',409); end if;
        select * into parking from public.qpark_parking_sessions where id=window_row.session_id for update;
        if coalesce((p_body->>'verified')::boolean,false) is not true or public.qpark_plate(p_body->>'plate')<>parking.plate then perform public.qpark_fail('Nopol kendaraan harus cocok dan diverifikasi petugas.','plate_mismatch',409); end if;
        select id into existing_id from public.qpark_authorizations where session_id=parking.id and state='ACTIVE';
        if existing_id is null then
          if now_at>window_row.deadline then perform public.qpark_fail('Izin 15 menit habis. Lunasi tagihan tambahan sesuai tarif kendaraan.','window_expired',409); end if;
          existing_id:=public.qpark_id('AUTH');
          insert into public.qpark_authorizations(id,session_id,window_id,approved_by,approved_at,expires_at,state)
          values(existing_id,parking.id,window_row.id,actor,now_at,now_at+interval '2 minutes','ACTIVE');
          update public.qpark_parking_sessions set state='EXIT_AUTHORIZED' where id=parking.id;
          perform public.qpark_audit_event('AUTHORIZE',existing_id,actor_text,now_at);
        end if;
        result:=jsonb_build_object('session_id',parking.id,'authorization_id',existing_id);
        perform public.qpark_operation_save(operation_key,'authorize',actor_text,p_body,result,now_at);
        result:=result||jsonb_build_object('session',public.qpark_session_view(parking.id,now_at,true));
      end if;
    elsif p_method='POST' and p_path in ('/api/officer/complete','/api/officer/cancel') then
      outcome_value:=case when p_path like '%complete' then 'complete' else 'cancel' end;
      replay:=public.qpark_operation_replay(operation_key,outcome_value,actor_text,p_body);
      if replay is not null then result:=replay||jsonb_build_object('session',public.qpark_session_view(replay->>'session_id',now_at,true));
      else
        select * into parking from public.qpark_parking_sessions where id=p_body->>'session_id' for update;
        if not found then perform public.qpark_fail('Sesi parkir tidak ditemukan.','not_found',404); end if;
        select * into auth_row from public.qpark_authorizations where id=p_body->>'authorization_id' and session_id=parking.id for update;
        if not found then perform public.qpark_fail('Persetujuan keluar tidak ditemukan.','authorization',409); end if;
        if auth_row.state<>'ACTIVE' or now_at>=auth_row.expires_at then perform public.qpark_fail('Persetujuan 120 detik sudah habis. Verifikasi ulang.','authorization_expired',409); end if;
        if outcome_value='complete' and coalesce((p_body->>'passed')::boolean,false) is not true then perform public.qpark_fail('Konfirmasi kendaraan benar-benar sudah lewat.','verification',400); end if;
        update public.qpark_authorizations set state=case when outcome_value='complete' then 'COMPLETED' else 'CANCELLED' end where id=auth_row.id;
        if outcome_value='complete' then update public.qpark_parking_sessions set state='COMPLETED',exited_at=now_at,exited_by=actor where id=parking.id;
        else update public.qpark_parking_sessions set state='IN_AREA' where id=parking.id; end if;
        result:=jsonb_build_object('session_id',parking.id,'authorization_id',auth_row.id);
        perform public.qpark_audit_event(case when outcome_value='complete' then 'EXIT' else 'AUTH_CANCELLED' end,parking.id,actor_text,now_at);
        perform public.qpark_operation_save(operation_key,outcome_value,actor_text,p_body,result,now_at);
        result:=result||jsonb_build_object('session',public.qpark_session_view(parking.id,now_at,true));
      end if;
    elsif p_method='POST' and p_path='/api/officer/manual-quote' then
      select * into parking from public.qpark_parking_sessions where id=p_body->>'session_id' for update;
      if not found then perform public.qpark_fail('Sesi parkir tidak ditemukan.','not_found',404); end if;
      if parking.state='COMPLETED' then perform public.qpark_fail('Sesi telah selesai.','completed',409); end if;
      select * into invoice from public.qpark_invoices where session_id=parking.id and state='PENDING' order by issued_at limit 1;
      if not found and not exists(select 1 from public.qpark_exit_windows where session_id=parking.id) then
        hours_value:=greatest(1,floor(extract(epoch from(now_at-parking.entered_at))/3600)::integer); amount_value:=hours_value*parking.hourly_rate; item_id:=public.qpark_id('INV');
        insert into public.qpark_invoices(id,session_id,kind,amount,hours,duration_seconds,issued_at,expires_at,state)
        values(item_id,parking.id,'BASE',amount_value,hours_value,extract(epoch from(now_at-parking.entered_at)),now_at,now_at+interval '5 minutes','PENDING') returning * into invoice;
      end if;
      result:=jsonb_build_object('invoice',case when invoice.id is null then null else (public.qpark_session_view(parking.id,now_at,true)->'invoices')->-1 end,'session',public.qpark_session_view(parking.id,now_at,true));
    elsif p_method='POST' and p_path='/api/officer/manual-pay' then
      replay:=public.qpark_operation_replay(operation_key,'manual_pay',actor_text,p_body);
      if replay is not null then result:=replay||jsonb_build_object('session',public.qpark_session_view(replay->>'session_id',now_at,true));
      else
        select * into parking from public.qpark_parking_sessions where id=p_body->>'session_id' for update;
        if not found then perform public.qpark_fail('Sesi parkir tidak ditemukan.','not_found',404); end if;
        if parking.state='COMPLETED' then perform public.qpark_fail('Kendaraan sudah keluar.','completed',409); end if;
        if coalesce((p_body->>'verified')::boolean,false) is not true or public.qpark_plate(p_body->>'plate')<>parking.plate then perform public.qpark_fail('Cocokkan nopol dan verifikasi kendaraan.','verification',400); end if;
        expected_value:=(p_body->>'expected_amount')::integer; received_value:=(p_body->>'received')::integer;
        if received_value<0 or received_value>1000000000 then perform public.qpark_fail('Nominal uang tidak valid.','money',400); end if;
        if nullif(p_body->>'invoice_id','') is not null then
          select * into invoice from public.qpark_invoices where id=p_body->>'invoice_id' and session_id=parking.id for update;
          if not found or invoice.state<>'PENDING' or (invoice.expires_at is not null and now_at>=invoice.expires_at) then perform public.qpark_fail('Tagihan berubah, sudah dibayar, atau kedaluwarsa. Muat ulang sebelum menerima uang.','requote',409); end if;
          if invoice.amount<>expected_value or received_value<expected_value then perform public.qpark_fail('Uang kurang atau tagihan berubah.','money',400); end if;
          item_id:=public.qpark_id('PAY');
          insert into public.qpark_payment_attempts(id,invoice_id,operation_key,outcome,server_time) values(item_id,invoice.id,operation_key,'SUCCESS',now_at);
          update public.qpark_invoices set state='PAID',paid_at=now_at,payment_method='MANUAL',received=received_value,change_amount=received_value-invoice.amount,paid_by=actor_text where id=invoice.id;
          select coalesce(max(sequence),0)+1 into sequence_value from public.qpark_exit_windows where session_id=parking.id;
          existing_id:=public.qpark_id('WIN'); raw_token:=public.qpark_qr(existing_id);
          insert into public.qpark_exit_windows(id,session_id,invoice_id,sequence,paid_at,deadline,token_hash)
          values(existing_id,parking.id,invoice.id,sequence_value,now_at,now_at+interval '15 minutes',encode(extensions.digest(raw_token,'sha256'),'hex'));
        else
          select * into window_row from public.qpark_exit_windows where session_id=parking.id order by sequence desc limit 1;
          if expected_value<>0 or received_value<>0 or window_row.id is null or (now_at>window_row.deadline and parking.state<>'EXIT_AUTHORIZED') or exists(select 1 from public.qpark_invoices where session_id=parking.id and state='PENDING') then perform public.qpark_fail('Muat ulang tagihan sebelum mengizinkan keluar.','requote',409); end if;
        end if;
        select id into existing_id from public.qpark_authorizations where session_id=parking.id and state='ACTIVE';
        if existing_id is null then
          select * into window_row from public.qpark_exit_windows where session_id=parking.id order by sequence desc limit 1;
          existing_id:=public.qpark_id('AUTH');
          insert into public.qpark_authorizations(id,session_id,window_id,approved_by,approved_at,expires_at,state)
          values(existing_id,parking.id,window_row.id,actor,now_at,now_at+interval '2 minutes','ACTIVE');
          update public.qpark_parking_sessions set state='EXIT_AUTHORIZED' where id=parking.id;
        end if;
        result:=jsonb_build_object('session_id',parking.id,'authorization_id',existing_id);
        perform public.qpark_audit_event('MANUAL_AUTHORIZE',parking.id,actor_text,now_at);
        perform public.qpark_operation_save(operation_key,'manual_pay',actor_text,p_body,result,now_at);
        result:=result||jsonb_build_object('session',public.qpark_session_view(parking.id,now_at,true));
      end if;
    else perform public.qpark_fail('Endpoint tidak ditemukan.','not_found',404);
    end if;
  else
    perform public.qpark_fail('Endpoint tidak ditemukan.','not_found',404);
  end if;
  return result || jsonb_build_object('server_time',now_epoch);
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'qpark_staff','qpark_staff_sessions','qpark_settings','qpark_parking_sessions',
    'qpark_invoices','qpark_payment_attempts','qpark_exit_windows','qpark_authorizations',
    'qpark_operations','qpark_audit'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
  end loop;
end $$;

revoke all on function public.qpark_fail(text,text,integer) from public;
revoke all on function public.qpark_id(text) from public;
revoke all on function public.qpark_epoch(timestamptz) from public;
revoke all on function public.qpark_plate(text) from public;
revoke all on function public.qpark_qr(text) from public;
revoke all on function public.qpark_audit_event(text,text,text,timestamptz,text) from public;
revoke all on function public.qpark_staff_for_token(text,timestamptz,boolean) from public;
revoke all on function public.qpark_maintain(timestamptz) from public;
revoke all on function public.qpark_session_view(text,timestamptz,boolean) from public;
revoke all on function public.qpark_operation_replay(text,text,text,jsonb) from public;
revoke all on function public.qpark_operation_save(text,text,text,jsonb,jsonb,timestamptz) from public;
revoke all on function public.qpark_history(jsonb,boolean,timestamptz) from public;
revoke all on function public.qpark_analytics(jsonb,timestamptz) from public;
revoke all on function public.qpark_request(text,text,jsonb,jsonb,text) from public;
grant execute on function public.qpark_request(text,text,jsonb,jsonb,text) to anon, authenticated;

commit;
