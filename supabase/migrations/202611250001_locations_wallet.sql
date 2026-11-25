begin;

-- Multi-location parking, Pengelola/Superadmin scoping, and prototype E-Wallet.
create table if not exists public.qpark_locations (
  id text primary key,
  name text not null check (length(trim(name)) between 1 and 80),
  address text not null default '',
  car_capacity integer not null default 10 check (car_capacity between 0 and 1000000),
  motor_capacity integer not null default 10 check (motor_capacity between 0 and 1000000),
  car_rate integer not null default 7000 check (car_rate between 1 and 1000000),
  motor_rate integer not null default 2000 check (motor_rate between 1 and 1000000),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.qpark_wallets (
  owner text primary key,
  balance integer not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.qpark_wallet_transactions (
  id text primary key,
  owner text not null,
  kind text not null check (kind in ('TOPUP', 'PAYMENT')),
  amount integer not null check (amount > 0),
  balance_after integer not null check (balance_after >= 0),
  description text not null,
  reference_id text,
  created_at timestamptz not null default now()
);
create index if not exists qpark_wallet_tx_owner on public.qpark_wallet_transactions(owner, created_at desc);

alter table public.qpark_locations enable row level security;
alter table public.qpark_wallets enable row level security;
alter table public.qpark_wallet_transactions enable row level security;
revoke all on public.qpark_locations, public.qpark_wallets, public.qpark_wallet_transactions from anon, authenticated;

-- Seed default location from existing singleton settings + second demo location.
insert into public.qpark_locations(id, name, address, car_capacity, motor_capacity, car_rate, motor_rate, active)
select 'LOC-DEFAULT', 'QPark Mall Sentral', 'Jl. Sudirman No. 1, Pusat Kota',
       coalesce(car_capacity, 10), coalesce(motor_capacity, 10),
       coalesce(car_rate, 7000), coalesce(motor_rate, 2000), true
from public.qpark_settings where singleton
on conflict (id) do nothing;

insert into public.qpark_locations(id, name, address, car_capacity, motor_capacity, car_rate, motor_rate, active)
values ('LOC-2', 'QPark Gedung Merdeka', 'Jl. Merdeka No. 45', 15, 20, 6000, 2000, true)
on conflict (id) do nothing;

-- Allow SUPERADMIN role and attach location_id to staff and sessions.
alter table public.qpark_staff drop constraint if exists qpark_staff_role_check;
alter table public.qpark_staff add constraint qpark_staff_role_check check (role in ('SUPERADMIN', 'ADMIN', 'PETUGAS'));
alter table public.qpark_staff add column if not exists location_id text references public.qpark_locations(id);
update public.qpark_staff set location_id = 'LOC-DEFAULT' where location_id is null and role <> 'SUPERADMIN';

alter table public.qpark_parking_sessions add column if not exists location_id text not null default 'LOC-DEFAULT' references public.qpark_locations(id);
create index if not exists qpark_sessions_location_state on public.qpark_parking_sessions(location_id, state, entered_at desc);

-- Allow EWALLET payment method on invoices.
alter table public.qpark_invoices drop constraint if exists qpark_invoices_payment_method_check;
alter table public.qpark_invoices add constraint qpark_invoices_payment_method_check
  check (payment_method in ('QR_SIMULASI', 'MANUAL', 'EWALLET'));

-- Seed superadmin & Location-2 demo staff without altering existing LOC-DEFAULT staff.
insert into public.qpark_staff(username, password_hash, role, active, location_id)
values
  ('superadmin', extensions.crypt('superadmin123', extensions.gen_salt('bf')), 'SUPERADMIN', true, null),
  ('pengelola_b', extensions.crypt('pengelola123', extensions.gen_salt('bf')), 'ADMIN', true, 'LOC-2'),
  ('petugas_b', extensions.crypt('petugas123', extensions.gen_salt('bf')), 'PETUGAS', true, 'LOC-2')
on conflict (username) do nothing;

-- Update token helper so both ADMIN (Pengelola) and SUPERADMIN pass admin checks.
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
  if p_admin and staff.role not in ('ADMIN', 'SUPERADMIN') then
    perform public.qpark_fail('Hanya pengelola atau superadmin yang dapat mengelola akun dan pengaturan.', 'forbidden', 403);
  end if;
  return staff.id;
end;
$$;

-- Helper to build one location's capacity summary.
create or replace function public.qpark_location_summary(p_loc public.qpark_locations)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  car_used integer;
  motor_used integer;
  categories jsonb;
begin
  select count(*) filter(where vehicle_type = 'MOBIL'),
         count(*) filter(where vehicle_type = 'MOTOR')
  into car_used, motor_used
  from public.qpark_parking_sessions
  where state <> 'COMPLETED' and location_id = p_loc.id;

  categories := jsonb_build_object(
    'MOBIL', jsonb_build_object('total', p_loc.car_capacity, 'occupied', car_used,
      'available', greatest(0, p_loc.car_capacity - car_used), 'full', car_used >= p_loc.car_capacity),
    'MOTOR', jsonb_build_object('total', p_loc.motor_capacity, 'occupied', motor_used,
      'available', greatest(0, p_loc.motor_capacity - motor_used), 'full', motor_used >= p_loc.motor_capacity)
  );
  return jsonb_build_object(
    'id', p_loc.id,
    'name', p_loc.name,
    'address', p_loc.address,
    'active', p_loc.active,
    'categories', categories,
    'total', p_loc.car_capacity + p_loc.motor_capacity,
    'occupied', car_used + motor_used,
    'available', greatest(0, p_loc.car_capacity - car_used) + greatest(0, p_loc.motor_capacity - motor_used),
    'full', car_used >= p_loc.car_capacity and motor_used >= p_loc.motor_capacity,
    'rates', jsonb_build_object('MOBIL', p_loc.car_rate, 'MOTOR', p_loc.motor_rate)
  );
end;
$$;

-- Enrich session view with location metadata.
create or replace function public.qpark_session_view(
  p_session_id text,
  p_now timestamptz,
  p_include_qr boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.qpark_parking_sessions%rowtype;
  loc public.qpark_locations%rowtype;
  w public.qpark_exit_windows%rowtype;
  a public.qpark_authorizations%rowtype;
  has_window boolean := false;
  has_auth boolean := false;
  invoices jsonb;
  amount_paid bigint;
  win_status text;
  pay_status text;
begin
  select * into s from public.qpark_parking_sessions where id = p_session_id;
  if not found then
    perform public.qpark_fail('Sesi parkir tidak ditemukan.', 'not_found', 404);
  end if;
  select * into loc from public.qpark_locations where id = s.location_id;

  select * into w from public.qpark_exit_windows where session_id = s.id order by sequence desc limit 1;
  has_window := found;
  select * into a from public.qpark_authorizations where session_id = s.id and state = 'ACTIVE' limit 1;
  has_auth := found;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'session_id', i.session_id, 'kind', i.kind, 'amount', i.amount,
    'hours', i.hours, 'duration', i.duration_seconds, 'issued_at', public.qpark_epoch(i.issued_at),
    'expires_at', public.qpark_epoch(i.expires_at), 'state', i.state, 'window_id', i.window_id,
    'paid_at', public.qpark_epoch(i.paid_at), 'payment_method', i.payment_method,
    'received', i.received, 'change_amount', i.change_amount, 'paid_by', i.paid_by
  ) order by i.issued_at, i.id), '[]'::jsonb),
  coalesce(sum(i.amount) filter (where i.state = 'PAID'), 0)
  into invoices, amount_paid
  from public.qpark_invoices i where i.session_id = s.id;

  win_status := case
    when not has_window then 'NONE'
    when s.state = 'COMPLETED' then 'CONSUMED'
    when p_now <= w.deadline or has_auth then 'VALID'
    else 'EXPIRED'
  end;

  pay_status := case
    when s.state = 'COMPLETED' then 'Selesai'
    when exists(select 1 from public.qpark_invoices i where i.session_id = s.id and i.kind = 'PENALTY' and i.state = 'PENDING') then 'Tambahan belum dibayar'
    when has_window then 'Lunas'
    else 'Belum dibayar'
  end;

  return jsonb_build_object(
    'id', s.id, 'plate', s.plate, 'vehicle_type', s.vehicle_type, 'hourly_rate', s.hourly_rate,
    'location_id', s.location_id,
    'location_name', coalesce(loc.name, 'QPark'),
    'location_address', coalesce(loc.address, ''),
    'entered_at', public.qpark_epoch(s.entered_at), 'entered_by', s.entered_by, 'state', s.state,
    'exited_at', public.qpark_epoch(s.exited_at), 'exited_by', s.exited_by,
    'invoices', invoices,
    'window', case when has_window then jsonb_build_object(
      'id', w.id, 'session_id', w.session_id, 'invoice_id', w.invoice_id,
      'sequence', w.sequence, 'paid_at', public.qpark_epoch(w.paid_at), 'deadline', public.qpark_epoch(w.deadline)
    ) else null end,
    'authorization', case when has_auth then jsonb_build_object(
      'id', a.id, 'session_id', a.session_id, 'window_id', a.window_id,
      'approved_by', a.approved_by, 'approved_at', public.qpark_epoch(a.approved_at),
      'expires_at', public.qpark_epoch(a.expires_at), 'state', a.state
    ) else null end,
    'server_time', public.qpark_epoch(p_now),
    'amount_paid', amount_paid,
    'duration_seconds', greatest(0, extract(epoch from (coalesce(s.exited_at, p_now) - s.entered_at))),
    'window_status', win_status,
    'payment_status', pay_status,
    'exit_qr', case when has_window and win_status = 'VALID' and p_include_qr then public.qpark_qr(w.id) else null end
  );
end;
$$;

alter function public.qpark_request(text, text, jsonb, jsonb, text) rename to qpark_request_v4;
revoke all on function public.qpark_request_v4(text, text, jsonb, jsonb, text) from public, anon, authenticated;

create function public.qpark_request(
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
<<v5_api>>
declare
  moment timestamptz := clock_timestamp();
  owner_key text;
  staff_id uuid;
  staff public.qpark_staff%rowtype;
  loc public.qpark_locations%rowtype;
  target_loc_id text;
  all_locs jsonb;
  result jsonb;
  replay jsonb;
  op_key text;
  inv public.qpark_invoices%rowtype;
  sess public.qpark_parking_sessions%rowtype;
  raw_qr text;
  inv_id text;
  bal integer;
  amt integer;
  new_bal integer;
  tx_id text;
  win_id text;
  win_seq integer;
  att_id text;
  cars integer;
  motors integer;
  c_rate integer;
  m_rate integer;
  car_used integer;
  motor_used integer;
  uname text;
  pwd text;
  new_role text;
  is_active boolean;
  old_staff public.qpark_staff%rowtype;
  norm_plate text;
  saved_kind text;
  v_kind text;
  new_sid text;
  loc_name text;
  loc_addr text;
begin
  if jsonb_typeof(p_body) is distinct from 'object' or jsonb_typeof(p_query) is distinct from 'object' then
    perform public.qpark_fail('Payload JSON harus objek.', 'payload', 400);
  end if;

  if auth.uid() is not null then
    if not exists(select 1 from public.profiles where id = auth.uid() and active) then
      perform public.qpark_fail('Akun tidak aktif.', 'customer_identity', 403);
    end if;
    owner_key := 'user:' || auth.uid()::text;
  elsif p_query->>'_customer_key' ~ '^[a-f0-9]{48}$' then
    owner_key := 'demo:' || encode(extensions.digest(p_query->>'_customer_key', 'sha256'), 'hex');
  end if;

  -- Public locations & capacity
  if p_path = '/api/locations' and p_method = 'GET' then
    select coalesce(jsonb_agg(public.qpark_location_summary(l) order by l.created_at, l.id), '[]'::jsonb)
    into all_locs from public.qpark_locations l where l.active;
    return jsonb_build_object('locations', all_locs, 'server_time', public.qpark_epoch(moment));
  end if;

  if p_path = '/api/capacity' and p_method = 'GET' then
    target_loc_id := nullif(p_query->>'location_id', '');
    if target_loc_id is null and p_token is not null and p_token <> '' then
      select s.location_id into target_loc_id
      from public.qpark_staff_sessions ss join public.qpark_staff s on s.id = ss.staff_id
      where ss.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
        and not ss.revoked and ss.expires_at > moment and s.active;
    end if;
    target_loc_id := coalesce(target_loc_id, 'LOC-DEFAULT');
    select * into loc from public.qpark_locations where id = target_loc_id;
    if not found then
      perform public.qpark_fail('Lokasi parkir tidak ditemukan.', 'location_not_found', 404);
    end if;
    select coalesce(jsonb_agg(public.qpark_location_summary(l) order by l.created_at, l.id), '[]'::jsonb)
    into all_locs from public.qpark_locations l where l.active;
    return public.qpark_location_summary(loc) || jsonb_build_object(
      'location', jsonb_build_object('id', loc.id, 'name', loc.name, 'address', loc.address, 'active', loc.active),
      'locations', all_locs,
      'server_time', public.qpark_epoch(moment)
    );
  end if;

  -- Enrich login response with location_id & location_name
  if p_path = '/api/login' and p_method = 'POST' then
    result := public.qpark_request_v4(p_method, p_path, p_query, p_body, p_token);
    select s.location_id, l.name into target_loc_id, loc_name
    from public.qpark_staff s left join public.qpark_locations l on l.id = s.location_id
    where s.username = result->>'username';
    return result || jsonb_build_object('location_id', target_loc_id, 'location_name', loc_name);
  end if;

  -- Admin/Superadmin locations management
  if p_path = '/api/admin/locations' then
    staff_id := public.qpark_staff_for_token(p_token, moment, true);
    select * into staff from public.qpark_staff where id = staff_id;
    if p_method = 'GET' then
      if staff.role = 'SUPERADMIN' then
        select coalesce(jsonb_agg(public.qpark_location_summary(l) order by l.created_at, l.id), '[]'::jsonb)
        into all_locs from public.qpark_locations l;
      else
        select coalesce(jsonb_agg(public.qpark_location_summary(l)), '[]'::jsonb)
        into all_locs from public.qpark_locations l where l.id = coalesce(staff.location_id, 'LOC-DEFAULT');
      end if;
      return jsonb_build_object('locations', all_locs, 'server_time', public.qpark_epoch(moment));
    elsif p_method = 'POST' then
      if staff.role <> 'SUPERADMIN' then
        perform public.qpark_fail('Hanya superadmin yang dapat menambah atau mengubah lokasi.', 'forbidden', 403);
      end if;
      op_key := p_body->>'operation_key';
      replay := public.qpark_operation_replay(op_key, 'location_save', staff_id::text, p_body);
      if replay is not null then return replay || jsonb_build_object('server_time', public.qpark_epoch(moment)); end if;
      loc_name := trim(coalesce(p_body->>'name', ''));
      loc_addr := trim(coalesce(p_body->>'address', ''));
      if length(loc_name) < 1 or length(loc_name) > 80 then
        perform public.qpark_fail('Nama lokasi wajib diisi (maksimal 80 karakter).', 'location', 400);
      end if;
      cars := (p_body->>'car_capacity')::integer;
      motors := (p_body->>'motor_capacity')::integer;
      c_rate := (p_body->>'car_rate')::integer;
      m_rate := (p_body->>'motor_rate')::integer;
      is_active := coalesce((p_body->>'active')::boolean, true);
      if cars is null or motors is null or c_rate is null or m_rate is null
        or cars not between 0 and 1000000 or motors not between 0 and 1000000
        or c_rate not between 1 and 1000000 or m_rate not between 1 and 1000000 then
        perform public.qpark_fail('Isi kapasitas 0–1.000.000 dan tarif 1–1.000.000.', 'settings', 400);
      end if;
      target_loc_id := nullif(p_body->>'id', '');
      if target_loc_id is not null then
        select * into loc from public.qpark_locations where id = target_loc_id for update;
        if not found then perform public.qpark_fail('Lokasi parkir tidak ditemukan.', 'location_not_found', 404); end if;
        select count(*) filter(where vehicle_type = 'MOBIL'), count(*) filter(where vehicle_type = 'MOTOR')
        into car_used, motor_used from public.qpark_parking_sessions where state <> 'COMPLETED' and location_id = loc.id;
        if cars < car_used or motors < motor_used then
          perform public.qpark_fail('Kapasitas setiap jenis tidak boleh di bawah jumlah kendaraan aktif.', 'capacity', 409);
        end if;
        if not is_active and (car_used + motor_used) > 0 then
          perform public.qpark_fail('Lokasi tidak dapat dinonaktifkan selama masih ada kendaraan parkir.', 'active_sessions', 409);
        end if;
        update public.qpark_locations
        set name = loc_name, address = loc_addr, car_capacity = cars, motor_capacity = motors,
            car_rate = c_rate, motor_rate = m_rate, active = is_active, updated_at = moment
        where id = loc.id returning * into loc;
        if loc.id = 'LOC-DEFAULT' then
          update public.qpark_settings set car_capacity = cars, motor_capacity = motors, capacity = cars + motors,
            car_rate = c_rate, motor_rate = m_rate, updated_at = moment where singleton;
        end if;
        perform public.qpark_audit_event('LOCATION_UPDATED', loc.id, staff_id::text, moment, loc_name);
      else
        target_loc_id := public.qpark_id('LOC');
        insert into public.qpark_locations(id, name, address, car_capacity, motor_capacity, car_rate, motor_rate, active, created_at, updated_at)
        values (target_loc_id, loc_name, loc_addr, cars, motors, c_rate, m_rate, is_active, moment, moment)
        returning * into loc;
        perform public.qpark_audit_event('LOCATION_CREATED', loc.id, staff_id::text, moment, loc_name);
      end if;
      result := jsonb_build_object('location', public.qpark_location_summary(loc));
      perform public.qpark_operation_save(op_key, 'location_save', staff_id::text, p_body, result, moment);
      return result || jsonb_build_object('server_time', public.qpark_epoch(moment));
    end if;
  end if;

  -- Location-scoped settings for Pengelola / Superadmin
  if p_path = '/api/admin/settings' then
    staff_id := public.qpark_staff_for_token(p_token, moment, true);
    select * into staff from public.qpark_staff where id = staff_id;
    target_loc_id := case
      when staff.role = 'SUPERADMIN' then coalesce(nullif(case when p_method = 'GET' then p_query->>'location_id' else p_body->>'location_id' end, ''), 'LOC-DEFAULT')
      else coalesce(staff.location_id, 'LOC-DEFAULT')
    end;
    if staff.role <> 'SUPERADMIN' and nullif(case when p_method = 'GET' then p_query->>'location_id' else p_body->>'location_id' end, '') is distinct from null
      and (case when p_method = 'GET' then p_query->>'location_id' else p_body->>'location_id' end) <> target_loc_id then
      perform public.qpark_fail('Akun ini hanya dapat mengelola lokasi yang ditugaskan.', 'location_forbidden', 403);
    end if;
    select * into loc from public.qpark_locations where id = target_loc_id for update;
    if not found then perform public.qpark_fail('Lokasi parkir tidak ditemukan.', 'location_not_found', 404); end if;
    if p_method = 'POST' then
      cars := (p_body->>'car_capacity')::integer; motors := (p_body->>'motor_capacity')::integer;
      c_rate := (p_body->>'car_rate')::integer; m_rate := (p_body->>'motor_rate')::integer;
      if cars is null or motors is null or c_rate is null or m_rate is null
        or cars not between 0 and 1000000 or motors not between 0 and 1000000
        or c_rate not between 1 and 1000000 or m_rate not between 1 and 1000000 then
        perform public.qpark_fail('Isi kapasitas 0–1.000.000 dan tarif 1–1.000.000.', 'settings', 400);
      end if;
      select count(*) filter(where vehicle_type = 'MOBIL'), count(*) filter(where vehicle_type = 'MOTOR')
      into car_used, motor_used from public.qpark_parking_sessions where state <> 'COMPLETED' and location_id = loc.id;
      if cars < car_used or motors < motor_used then
        perform public.qpark_fail('Kapasitas setiap jenis tidak boleh di bawah jumlah kendaraan aktif.', 'capacity', 409);
      end if;
      update public.qpark_locations set car_capacity = cars, motor_capacity = motors,
        car_rate = c_rate, motor_rate = m_rate, updated_at = moment where id = loc.id returning * into loc;
      if loc.id = 'LOC-DEFAULT' then
        update public.qpark_settings set car_capacity = cars, motor_capacity = motors, capacity = cars + motors,
          car_rate = c_rate, motor_rate = m_rate, updated_at = moment where singleton;
      end if;
      perform public.qpark_audit_event('SETTINGS_CHANGED', loc.id, staff_id::text, moment, p_body::text);
    end if;
    return jsonb_build_object('settings', jsonb_build_object(
      'location_id', loc.id, 'name', loc.name, 'address', loc.address,
      'capacity', loc.car_capacity + loc.motor_capacity,
      'car_capacity', loc.car_capacity, 'motor_capacity', loc.motor_capacity,
      'car_rate', loc.car_rate, 'motor_rate', loc.motor_rate
    ), 'server_time', public.qpark_epoch(moment));
  end if;

  -- Location-scoped users management
  if p_path = '/api/admin/users' then
    staff_id := public.qpark_staff_for_token(p_token, moment, true);
    select * into staff from public.qpark_staff where id = staff_id;
    if p_method = 'GET' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'username', s.username, 'role', s.role,
        'active', case when s.active then 1 else 0 end,
        'location_id', s.location_id, 'location_name', l.name
      ) order by s.username), '[]'::jsonb)
      into result
      from public.qpark_staff s left join public.qpark_locations l on l.id = s.location_id
      where staff.role = 'SUPERADMIN' or (s.location_id = staff.location_id and s.role <> 'SUPERADMIN');
      return jsonb_build_object('users', result, 'server_time', public.qpark_epoch(moment));
    elsif p_method = 'POST' then
      op_key := p_body->>'operation_key';
      replay := public.qpark_operation_replay(op_key, 'user_update', staff_id::text, p_body);
      if replay is not null then return replay || jsonb_build_object('server_time', public.qpark_epoch(moment)); end if;
      uname := lower(trim(coalesce(p_body->>'username', '')));
      pwd := coalesce(p_body->>'password', '');
      new_role := coalesce(p_body->>'role', 'PETUGAS');
      is_active := coalesce((p_body->>'active')::boolean, true);
      if length(uname) < 1 or length(uname) > 40 or
        (staff.role = 'SUPERADMIN' and new_role not in ('SUPERADMIN', 'ADMIN', 'PETUGAS')) or
        (staff.role <> 'SUPERADMIN' and new_role not in ('ADMIN', 'PETUGAS')) then
        perform public.qpark_fail('Username atau peran tidak valid.', 'user', 400);
      end if;
      if pwd <> '' and length(pwd) < 8 then
        perform public.qpark_fail('Password minimum delapan karakter.', 'password', 400);
      end if;
      target_loc_id := case
        when new_role = 'SUPERADMIN' then null
        when staff.role = 'SUPERADMIN' then coalesce(nullif(p_body->>'location_id', ''), 'LOC-DEFAULT')
        else coalesce(staff.location_id, 'LOC-DEFAULT')
      end;
      if target_loc_id is not null and not exists(select 1 from public.qpark_locations where id = target_loc_id) then
        perform public.qpark_fail('Lokasi parkir tidak ditemukan.', 'location_not_found', 404);
      end if;
      select * into old_staff from public.qpark_staff where username = uname;
      if found then
        if staff.role <> 'SUPERADMIN' and (old_staff.role = 'SUPERADMIN' or old_staff.location_id is distinct from staff.location_id) then
          perform public.qpark_fail('Akun tersebut milik lokasi lain atau superadmin.', 'forbidden', 403);
        end if;
        if old_staff.id = staff.id and (not is_active or new_role <> staff.role) then
          perform public.qpark_fail('Pengelola tidak dapat menonaktifkan atau menurunkan perannya sendiri.', 'self_change', 409);
        end if;
        update public.qpark_staff set role = new_role, active = is_active, location_id = target_loc_id,
          password_hash = case when pwd <> '' then extensions.crypt(pwd, extensions.gen_salt('bf')) else password_hash end,
          updated_at = moment
        where id = old_staff.id;
        if pwd <> '' or not is_active or new_role <> old_staff.role or target_loc_id is distinct from old_staff.location_id then
          update public.qpark_staff_sessions set revoked = true where staff_id = old_staff.id;
        end if;
      else
        if pwd = '' then perform public.qpark_fail('Password akun baru wajib diisi.', 'password', 400); end if;
        insert into public.qpark_staff(username, password_hash, role, active, location_id)
        values (uname, extensions.crypt(pwd, extensions.gen_salt('bf')), new_role, is_active, target_loc_id);
      end if;
      result := jsonb_build_object('updated', true);
      perform public.qpark_operation_save(op_key, 'user_update', staff_id::text, p_body, result, moment);
      return result || jsonb_build_object('server_time', public.qpark_epoch(moment));
    end if;
  end if;

  -- Location-scoped officer monitor & entry
  if p_path = '/api/officer/monitor' and p_method = 'GET' then
    perform public.qpark_maintain(moment);
    staff_id := public.qpark_staff_for_token(p_token, moment, false);
    select * into staff from public.qpark_staff where id = staff_id;
    target_loc_id := case when staff.role = 'SUPERADMIN' then nullif(p_query->>'location_id', '') else coalesce(staff.location_id, 'LOC-DEFAULT') end;
    select coalesce(jsonb_agg(public.qpark_session_view(s.id, moment, false) order by s.entered_at desc), '[]'::jsonb)
    into result from public.qpark_parking_sessions s
    where s.state <> 'COMPLETED'
      and (target_loc_id is null or s.location_id = target_loc_id)
      and strpos(s.plate, upper(replace(coalesce(p_query->>'q', ''), ' ', ''))) > 0;
    return jsonb_build_object('sessions', result, 'server_time', public.qpark_epoch(moment));
  end if;

  if p_path = '/api/officer/entry' and p_method = 'POST' then
    perform public.qpark_maintain(moment);
    staff_id := public.qpark_staff_for_token(p_token, moment, false);
    select * into staff from public.qpark_staff where id = staff_id;
    target_loc_id := case when staff.role = 'SUPERADMIN' then coalesce(nullif(p_body->>'location_id', ''), 'LOC-DEFAULT') else coalesce(staff.location_id, 'LOC-DEFAULT') end;
    select * into loc from public.qpark_locations where id = target_loc_id for update;
    if not found then perform public.qpark_fail('Lokasi parkir tidak ditemukan.', 'location_not_found', 404); end if;
    op_key := p_body->>'operation_key';
    replay := public.qpark_operation_replay(op_key, 'entry', staff_id::text, p_body);
    if replay is not null then
      return replay || jsonb_build_object('session', public.qpark_session_view(replay->>'session_id', moment, true), 'server_time', public.qpark_epoch(moment));
    end if;
    norm_plate := public.qpark_plate(p_body->>'plate');
    if p_body->>'verified' is distinct from 'true' or not (
      p_body->>'image_source' = 'manual' or (p_body->>'image_readable' = 'true' and p_body->>'image_source' in ('test_photo', 'camera'))
    ) then
      perform public.qpark_fail('Kendaraan wajib diverifikasi. Jika menggunakan gambar, pastikan gambar terbaca.', 'verification', 400);
    end if;
    if exists(select 1 from public.qpark_parking_sessions where plate = norm_plate and state <> 'COMPLETED') then
      perform public.qpark_fail('Nopol masih memiliki sesi aktif.', 'duplicate_plate', 409);
    end if;
    select vehicle_type into saved_kind from public.qpark_vehicle_categories where plate = norm_plate limit 1;
    v_kind := coalesce(saved_kind, nullif(p_body->>'vehicle_type', ''), 'MOBIL');
    if v_kind not in ('MOBIL', 'MOTOR') then perform public.qpark_fail('Pilih Mobil atau Motor.', 'vehicle', 400); end if;
    select count(*) into car_used from public.qpark_parking_sessions where state <> 'COMPLETED' and vehicle_type = v_kind and location_id = loc.id;
    if car_used >= (case when v_kind = 'MOTOR' then loc.motor_capacity else loc.car_capacity end) then
      perform public.qpark_fail('Area parkir penuh. Kendaraan ditolak.', 'full', 409);
    end if;
    new_sid := public.qpark_id('QP');
    insert into public.qpark_parking_sessions(id, plate, vehicle_type, hourly_rate, entered_at, entered_by, state, location_id)
    values (new_sid, norm_plate, v_kind, case when v_kind = 'MOTOR' then loc.motor_rate else loc.car_rate end, moment, staff_id, 'IN_AREA', loc.id);
    perform public.qpark_audit_event('ENTRY', new_sid, staff_id::text, moment, p_body->>'image_source');
    result := jsonb_build_object('session_id', new_sid);
    perform public.qpark_operation_save(op_key, 'entry', staff_id::text, p_body, result, moment);
    return result || jsonb_build_object('session', public.qpark_session_view(new_sid, moment, true), 'server_time', public.qpark_epoch(moment));
  end if;

  -- Prototype E-Wallet endpoints
  if p_path = '/api/wallet' and p_method = 'GET' then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    select coalesce(balance, 0) into bal from public.qpark_wallets where owner = owner_key;
    bal := coalesce(bal, 0);
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'kind', t.kind, 'amount', t.amount, 'balance_after', t.balance_after,
      'description', t.description, 'reference_id', t.reference_id, 'created_at', public.qpark_epoch(t.created_at)
    ) order by t.created_at desc, t.id desc), '[]'::jsonb)
    into result from (select * from public.qpark_wallet_transactions where owner = owner_key order by created_at desc, id desc limit 50) t;
    return jsonb_build_object('balance', bal, 'transactions', result, 'server_time', public.qpark_epoch(moment));
  end if;

  if p_path = '/api/wallet/topup' and p_method = 'POST' then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    op_key := p_body->>'operation_key';
    replay := public.qpark_operation_replay(op_key, 'wallet_topup', owner_key, p_body);
    if replay is null then
      amt := (p_body->>'amount')::integer;
      if amt is null or amt < 1000 or amt > 10000000 then
        perform public.qpark_fail('Nominal top up harus antara Rp1.000 hingga Rp10.000.000.', 'amount', 400);
      end if;
      insert into public.qpark_wallets(owner, balance, updated_at) values (owner_key, 0, moment) on conflict (owner) do nothing;
      select balance into bal from public.qpark_wallets where owner = owner_key for update;
      new_bal := bal + amt;
      if new_bal > 1000000000 then perform public.qpark_fail('Saldo maksimal Rp1.000.000.000 tercapai.', 'balance_limit', 400); end if;
      update public.qpark_wallets set balance = new_bal, updated_at = moment where owner = owner_key;
      tx_id := public.qpark_id('WLT');
      insert into public.qpark_wallet_transactions(id, owner, kind, amount, balance_after, description, reference_id, created_at)
      values (tx_id, owner_key, 'TOPUP', amt, new_bal, 'Top up saldo Dompet QPark (simulasi)', op_key, moment);
      perform public.qpark_audit_event('WALLET_TOPUP', tx_id, owner_key, moment, amt::text);
      replay := jsonb_build_object('balance', new_bal, 'transaction_id', tx_id);
      perform public.qpark_operation_save(op_key, 'wallet_topup', owner_key, p_body, replay, moment);
    end if;
    select coalesce(balance, 0) into bal from public.qpark_wallets where owner = owner_key;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'kind', t.kind, 'amount', t.amount, 'balance_after', t.balance_after,
      'description', t.description, 'reference_id', t.reference_id, 'created_at', public.qpark_epoch(t.created_at)
    ) order by t.created_at desc, t.id desc), '[]'::jsonb)
    into result from (select * from public.qpark_wallet_transactions where owner = owner_key order by created_at desc, id desc limit 50) t;
    return replay || jsonb_build_object('balance', coalesce(bal, 0), 'transactions', result, 'server_time', public.qpark_epoch(moment));
  end if;

  if p_path in ('/api/wallet/inspect', '/api/wallet/pay') and p_method = 'POST' then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    perform public.qpark_maintain(moment);
    inv_id := nullif(p_body->>'invoice_id', '');
    if inv_id is null then
      raw_qr := trim(coalesce(p_body->>'qr', ''));
      if raw_qr like 'QPP.SIMULASI.%' then inv_id := substr(raw_qr, 14);
      elsif raw_qr like 'QPP.%' then inv_id := substr(raw_qr, 5);
      else perform public.qpark_fail('QR bukan kode tagihan parkir QPark.', 'invalid_qr', 400);
      end if;
    end if;
    if p_path = '/api/wallet/inspect' then
      select * into inv from public.qpark_invoices where id = inv_id;
      if not found then perform public.qpark_fail('Tagihan parkir tidak ditemukan.', 'invoice', 404); end if;
      if inv.state = 'PAID' then perform public.qpark_fail('Tagihan ini sudah lunas.', 'invoice_paid', 409); end if;
      if inv.state = 'EXPIRED' or (inv.expires_at is not null and moment >= inv.expires_at) then
        perform public.qpark_fail('Tagihan sudah kedaluwarsa. Minta QR tagihan baru.', 'invoice_expired', 409);
      end if;
      select * into sess from public.qpark_parking_sessions where id = inv.session_id;
      if sess.state <> 'IN_AREA' then perform public.qpark_fail('Sesi parkir tidak dapat dibayar saat ini.', 'state', 409); end if;
      select coalesce(balance, 0) into bal from public.qpark_wallets where owner = owner_key;
      return jsonb_build_object(
        'invoice', jsonb_build_object('id', inv.id, 'session_id', inv.session_id, 'kind', inv.kind,
          'amount', inv.amount, 'hours', inv.hours, 'duration', inv.duration_seconds,
          'expires_at', public.qpark_epoch(inv.expires_at), 'state', inv.state),
        'session', public.qpark_session_view(inv.session_id, moment, false),
        'balance', coalesce(bal, 0),
        'server_time', public.qpark_epoch(moment)
      );
    end if;

    -- POST /api/wallet/pay
    op_key := p_body->>'operation_key';
    replay := public.qpark_operation_replay(op_key, 'wallet_pay', owner_key, p_body);
    if replay is null then
      select * into inv from public.qpark_invoices where id = inv_id for update;
      if not found then perform public.qpark_fail('Tagihan parkir tidak ditemukan.', 'invoice', 404); end if;
      if inv.state = 'PAID' then
        replay := jsonb_build_object('session_id', inv.session_id, 'invoice_id', inv.id, 'outcome', 'SUCCESS', 'paid_at', public.qpark_epoch(inv.paid_at));
      else
        if inv.state = 'EXPIRED' or (inv.expires_at is not null and moment >= inv.expires_at) then
          perform public.qpark_fail('Tagihan kedaluwarsa. Buka tagihan baru.', 'invoice_expired', 409);
        end if;
        select * into sess from public.qpark_parking_sessions where id = inv.session_id for update;
        if sess.state <> 'IN_AREA' then perform public.qpark_fail('Sesi tidak dapat dibayar saat ini.', 'state', 409); end if;
        insert into public.qpark_wallets(owner, balance, updated_at) values (owner_key, 0, moment) on conflict (owner) do nothing;
        select balance into bal from public.qpark_wallets where owner = owner_key for update;
        if bal < inv.amount then
          perform public.qpark_fail('Saldo Dompet QPark tidak mencukupi. Silakan Top Up terlebih dahulu.', 'insufficient_balance', 409);
        end if;
        new_bal := bal - inv.amount;
        update public.qpark_wallets set balance = new_bal, updated_at = moment where owner = owner_key;
        select * into loc from public.qpark_locations where id = sess.location_id;
        tx_id := public.qpark_id('WLT');
        insert into public.qpark_wallet_transactions(id, owner, kind, amount, balance_after, description, reference_id, created_at)
        values (tx_id, owner_key, 'PAYMENT', inv.amount, new_bal,
          'Bayar parkir ' || sess.plate || ' · ' || coalesce(loc.name, 'QPark'), inv.id, moment);
        att_id := public.qpark_id('PAY');
        insert into public.qpark_payment_attempts(id, invoice_id, operation_key, outcome, server_time)
        values (att_id, inv.id, op_key, 'SUCCESS', moment);
        update public.qpark_invoices set state = 'PAID', paid_at = moment, payment_method = 'EWALLET', paid_by = owner_key where id = inv.id;
        select coalesce(max(sequence), 0) + 1 into win_seq from public.qpark_exit_windows where session_id = sess.id;
        win_id := public.qpark_id('WIN');
        insert into public.qpark_exit_windows(id, session_id, invoice_id, sequence, paid_at, deadline, token_digest)
        values (win_id, sess.id, inv.id, win_seq, moment, moment + interval '15 minutes',
          encode(extensions.digest(public.qpark_qr(win_id), 'sha256'), 'hex'));
        insert into public.qpark_customer_links(session_id, owner) values (sess.id, owner_key) on conflict (session_id) do nothing;
        perform public.qpark_audit_event('PAYMENT_SUCCESS', inv.id, owner_key, moment, 'EWALLET');
        replay := jsonb_build_object('session_id', sess.id, 'invoice_id', inv.id, 'outcome', 'SUCCESS',
          'attempt_id', att_id, 'paid_at', public.qpark_epoch(moment));
      end if;
      perform public.qpark_operation_save(op_key, 'wallet_pay', owner_key, p_body, replay, moment);
    end if;
    select coalesce(balance, 0) into bal from public.qpark_wallets where owner = owner_key;
    return replay || jsonb_build_object(
      'session', public.qpark_session_view(replay->>'session_id', moment, true),
      'balance', coalesce(bal, 0),
      'server_time', public.qpark_epoch(moment)
    );
  end if;

  return public.qpark_request_v4(p_method, p_path, p_query, p_body, p_token);
end;
$$;

revoke all on function public.qpark_request(text, text, jsonb, jsonb, text) from public;
grant execute on function public.qpark_request(text, text, jsonb, jsonb, text) to anon, authenticated;

commit;
