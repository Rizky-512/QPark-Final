begin;

-- EV charging slots (blue-plate verified bookings) and time-gated location promos.
alter table public.qpark_locations add column if not exists ev_capacity integer not null default 4 check (ev_capacity between 0 and 1000000);
alter table public.qpark_locations add column if not exists ev_rate integer not null default 10000 check (ev_rate between 1 and 1000000);
update public.qpark_locations set ev_capacity = 6, ev_rate = 9000 where id = 'LOC-2';

alter table public.qpark_vehicle_categories add column if not exists is_ev boolean not null default false;

create table if not exists public.qpark_ev_bookings (
  id text primary key,
  location_id text not null references public.qpark_locations(id),
  owner text not null,
  plate text not null,
  duration_hours integer not null check (duration_hours between 1 and 12),
  hourly_rate integer not null,
  estimated_cost integer not null,
  status text not null check (status in ('ACTIVE', 'COMPLETED', 'CANCELLED')),
  booked_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists qpark_ev_bookings_loc on public.qpark_ev_bookings(location_id, status);
create index if not exists qpark_ev_bookings_owner on public.qpark_ev_bookings(owner, booked_at desc);

create table if not exists public.qpark_promos (
  id text primary key,
  location_id text not null references public.qpark_locations(id),
  title text not null check (length(trim(title)) between 1 and 80),
  description text not null default '',
  code text not null default '',
  discount_type text not null check (discount_type in ('PERCENT', 'FIXED')),
  discount_value integer not null check (discount_value > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists qpark_promos_loc_time on public.qpark_promos(location_id, active, starts_at, ends_at);

alter table public.qpark_ev_bookings enable row level security;
alter table public.qpark_promos enable row level security;
revoke all on public.qpark_ev_bookings, public.qpark_promos from anon, authenticated;

-- Seed 2 sample time-gated promos if table is empty.
insert into public.qpark_promos(id, location_id, title, description, code, discount_type, discount_value, starts_at, ends_at, active, created_by)
select 'PRM-SEED-1', 'LOC-DEFAULT', 'Diskon Parkir 20% Sentral',
       'Potongan 20% khusus pembayaran Dompet QPark di QPark Mall Sentral.',
       'SENTRAL20', 'PERCENT', 20, now() - interval '1 hour', now() + interval '30 days', true, 'SYSTEM'
where exists (select 1 from public.qpark_locations where id = 'LOC-DEFAULT')
  and not exists (select 1 from public.qpark_promos);

insert into public.qpark_promos(id, location_id, title, description, code, discount_type, discount_value, starts_at, ends_at, active, created_by)
select 'PRM-SEED-2', 'LOC-2', 'Hemat Rp2.000 Gedung Merdeka',
       'Potongan langsung Rp2.000 selama masa promo berlangsung.',
       'MERDEKA2K', 'FIXED', 2000, now() - interval '1 hour', now() + interval '30 days', true, 'SYSTEM'
where exists (select 1 from public.qpark_locations where id = 'LOC-2')
  and not exists (select 1 from public.qpark_promos where id = 'PRM-SEED-2');

-- Update location summary helper to include live EV charging slots.
create or replace function public.qpark_location_summary(p_loc public.qpark_locations)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  car_used integer;
  motor_used integer;
  ev_used integer;
  categories jsonb;
begin
  select count(*) filter(where vehicle_type = 'MOBIL'),
         count(*) filter(where vehicle_type = 'MOTOR')
  into car_used, motor_used
  from public.qpark_parking_sessions
  where state <> 'COMPLETED' and location_id = p_loc.id;

  select count(*) into ev_used
  from public.qpark_ev_bookings
  where location_id = p_loc.id and status = 'ACTIVE' and expires_at > clock_timestamp();

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
    'ev', jsonb_build_object(
      'total', p_loc.ev_capacity, 'occupied', ev_used,
      'available', greatest(0, p_loc.ev_capacity - ev_used),
      'full', ev_used >= p_loc.ev_capacity, 'rate', p_loc.ev_rate
    ),
    'total', p_loc.car_capacity + p_loc.motor_capacity,
    'occupied', car_used + motor_used,
    'available', greatest(0, p_loc.car_capacity - car_used) + greatest(0, p_loc.motor_capacity - motor_used),
    'full', car_used >= p_loc.car_capacity and motor_used >= p_loc.motor_capacity,
    'rates', jsonb_build_object('MOBIL', p_loc.car_rate, 'MOTOR', p_loc.motor_rate, 'EV', p_loc.ev_rate)
  );
end;
$$;

alter function public.qpark_request(text, text, jsonb, jsonb, text) rename to qpark_request_v5;
revoke all on function public.qpark_request_v5(text, text, jsonb, jsonb, text) from public, anon, authenticated;

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
<<v6_api>>
declare
  moment timestamptz := clock_timestamp();
  owner_key text;
  staff_id uuid;
  staff public.qpark_staff%rowtype;
  loc public.qpark_locations%rowtype;
  target_loc_id text;
  result jsonb;
  ev_map jsonb;
  replay jsonb;
  op_key text;
  norm_plate text;
  v_kind text;
  v_is_ev boolean;
  dur_hours integer;
  ev_used integer;
  bid text;
  ev_cap integer;
  ev_rate_val integer;
  promo_row public.qpark_promos%rowtype;
  promo_id text;
  p_title text;
  p_desc text;
  p_code text;
  p_dtype text;
  p_dval integer;
  p_start timestamptz;
  p_end timestamptz;
  p_active boolean;
  inv public.qpark_invoices%rowtype;
  sess public.qpark_parking_sessions%rowtype;
  raw_qr text;
  inv_id text;
  disc integer := 0;
  payable integer;
  bal integer;
  new_bal integer;
  tx_id text;
  att_id text;
  win_id text;
  win_seq integer;
  promos_json jsonb;
begin
  if jsonb_typeof(p_body) is distinct from 'object' or jsonb_typeof(p_query) is distinct from 'object' then
    perform public.qpark_fail('Payload JSON harus objek.', 'payload', 400);
  end if;

  update public.qpark_ev_bookings set status = 'COMPLETED' where status = 'ACTIVE' and expires_at <= moment;

  if auth.uid() is not null then
    if not exists(select 1 from public.profiles where id = auth.uid() and active) then
      perform public.qpark_fail('Akun tidak aktif.', 'customer_identity', 403);
    end if;
    owner_key := 'user:' || auth.uid()::text;
  elsif p_query->>'_customer_key' ~ '^[a-f0-9]{48}$' then
    owner_key := 'demo:' || encode(extensions.digest(p_query->>'_customer_key', 'sha256'), 'hex');
  end if;

  -- Vehicle types with blue-plate EV flag
  if p_path in ('/api/customer/vehicle-types', '/api/customer/vehicle-type') then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    if p_method = 'GET' and p_path = '/api/customer/vehicle-types' then
      select coalesce(jsonb_object_agg(plate, vehicle_type), '{}'::jsonb),
             coalesce(jsonb_object_agg(plate, is_ev), '{}'::jsonb)
      into result, ev_map
      from public.qpark_vehicle_categories where owner = owner_key;
      return jsonb_build_object('vehicle_types', result, 'ev_plates', ev_map, 'server_time', public.qpark_epoch(moment));
    end if;
    norm_plate := public.qpark_plate(p_body->>'plate');
    if p_method = 'POST' and p_body->>'remove' = 'true' then
      delete from public.qpark_vehicle_categories where owner = owner_key and plate = norm_plate;
      return jsonb_build_object('removed', true, 'server_time', public.qpark_epoch(moment));
    end if;
    v_kind := p_body->>'vehicle_type';
    v_is_ev := coalesce((p_body->>'is_ev')::boolean, false);
    if p_method <> 'POST' or v_kind is null or v_kind not in ('MOBIL', 'MOTOR') then
      perform public.qpark_fail('Pilih Mobil atau Motor.', 'vehicle', 400);
    end if;
    if exists(select 1 from public.qpark_parking_sessions where plate = norm_plate and state <> 'COMPLETED' and vehicle_type <> v_kind) then
      perform public.qpark_fail('Kategori tidak dapat berubah selama kendaraan sedang parkir.', 'vehicle_active', 409);
    end if;
    if exists(select 1 from public.qpark_vehicle_categories where plate = norm_plate and owner <> owner_key and vehicle_type <> v_kind) then
      perform public.qpark_fail('Kategori nopol berbeda dari data tersimpan. Periksa nopol Anda.', 'vehicle_conflict', 409);
    end if;
    insert into public.qpark_vehicle_categories(owner, plate, vehicle_type, is_ev)
    values (owner_key, norm_plate, v_kind, v_is_ev)
    on conflict (owner, plate) do update set vehicle_type = excluded.vehicle_type, is_ev = excluded.is_ev;
    return jsonb_build_object('vehicle_type', v_kind, 'is_ev', v_is_ev, 'server_time', public.qpark_epoch(moment));
  end if;

  -- Settings & locations with EV capacity / rate
  if p_path = '/api/admin/settings' and p_method in ('GET', 'POST') then
    result := public.qpark_request_v5(p_method, p_path, p_query, p_body, p_token);
    target_loc_id := result->'settings'->>'location_id';
    select * into loc from public.qpark_locations where id = coalesce(target_loc_id, 'LOC-DEFAULT') for update;
    if p_method = 'POST' and (p_body ? 'ev_capacity' or p_body ? 'ev_rate') then
      ev_cap := coalesce((p_body->>'ev_capacity')::integer, loc.ev_capacity);
      ev_rate_val := coalesce((p_body->>'ev_rate')::integer, loc.ev_rate);
      if ev_cap not between 0 and 1000000 or ev_rate_val not between 1 and 1000000 then
        perform public.qpark_fail('Isi kapasitas EV 0–1.000.000 dan tarif EV 1–1.000.000.', 'settings', 400);
      end if;
      select count(*) into ev_used from public.qpark_ev_bookings where location_id = loc.id and status = 'ACTIVE';
      if ev_cap < ev_used then
        perform public.qpark_fail('Kapasitas EV tidak boleh di bawah jumlah booking EV aktif.', 'capacity', 409);
      end if;
      update public.qpark_locations set ev_capacity = ev_cap, ev_rate = ev_rate_val, updated_at = moment where id = loc.id returning * into loc;
    end if;
    return jsonb_set(result, '{settings}', (result->'settings') || jsonb_build_object('ev_capacity', loc.ev_capacity, 'ev_rate', loc.ev_rate));
  end if;

  if p_path = '/api/admin/locations' and p_method = 'POST' then
    result := public.qpark_request_v5(p_method, p_path, p_query, p_body, p_token);
    target_loc_id := result->'location'->>'id';
    if target_loc_id is not null and (p_body ? 'ev_capacity' or p_body ? 'ev_rate') then
      select * into loc from public.qpark_locations where id = target_loc_id for update;
      ev_cap := coalesce((p_body->>'ev_capacity')::integer, loc.ev_capacity);
      ev_rate_val := coalesce((p_body->>'ev_rate')::integer, loc.ev_rate);
      if ev_cap not between 0 and 1000000 or ev_rate_val not between 1 and 1000000 then
        perform public.qpark_fail('Isi kapasitas EV 0–1.000.000 dan tarif EV 1–1.000.000.', 'settings', 400);
      end if;
      select count(*) into ev_used from public.qpark_ev_bookings where location_id = loc.id and status = 'ACTIVE';
      if ev_cap < ev_used then
        perform public.qpark_fail('Kapasitas EV tidak boleh di bawah jumlah booking EV aktif.', 'capacity', 409);
      end if;
      update public.qpark_locations set ev_capacity = ev_cap, ev_rate = ev_rate_val, updated_at = moment where id = loc.id returning * into loc;
      return jsonb_set(result, '{location}', public.qpark_location_summary(loc));
    end if;
    return result;
  end if;

  -- Public capacity also bundles active time-gated promos in one round-trip
  if p_path = '/api/capacity' and p_method = 'GET' then
    result := public.qpark_request_v5(p_method, p_path, p_query, p_body, p_token);
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'location_id', p.location_id, 'location_name', l.name,
      'title', p.title, 'description', p.description, 'code', p.code,
      'discount_type', p.discount_type, 'discount_value', p.discount_value,
      'starts_at', public.qpark_epoch(p.starts_at), 'ends_at', public.qpark_epoch(p.ends_at),
      'active', p.active
    ) order by p.ends_at asc, p.created_at desc), '[]'::jsonb)
    into promos_json
    from public.qpark_promos p join public.qpark_locations l on l.id = p.location_id
    where p.active and l.active and p.starts_at <= moment and p.ends_at >= moment;
    return result || jsonb_build_object('promos', promos_json);
  end if;

  -- Public time-gated promos
  if p_path = '/api/promos' and p_method = 'GET' then
    target_loc_id := nullif(p_query->>'location_id', '');
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'location_id', p.location_id, 'location_name', l.name,
      'title', p.title, 'description', p.description, 'code', p.code,
      'discount_type', p.discount_type, 'discount_value', p.discount_value,
      'starts_at', public.qpark_epoch(p.starts_at), 'ends_at', public.qpark_epoch(p.ends_at),
      'active', p.active
    ) order by p.ends_at asc, p.created_at desc), '[]'::jsonb)
    into result
    from public.qpark_promos p join public.qpark_locations l on l.id = p.location_id
    where p.active and l.active and p.starts_at <= moment and p.ends_at >= moment
      and (target_loc_id is null or p.location_id = target_loc_id);
    return jsonb_build_object('promos', result, 'server_time', public.qpark_epoch(moment));
  end if;

  -- Admin/Pengelola promos CRUD
  if p_path = '/api/admin/promos' then
    staff_id := public.qpark_staff_for_token(p_token, moment, true);
    select * into staff from public.qpark_staff where id = staff_id;
    if p_method = 'GET' then
      target_loc_id := case when staff.role = 'SUPERADMIN' then nullif(p_query->>'location_id', '') else coalesce(staff.location_id, 'LOC-DEFAULT') end;
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'location_id', p.location_id, 'location_name', l.name,
        'title', p.title, 'description', p.description, 'code', p.code,
        'discount_type', p.discount_type, 'discount_value', p.discount_value,
        'starts_at', public.qpark_epoch(p.starts_at), 'ends_at', public.qpark_epoch(p.ends_at),
        'active', p.active
      ) order by p.created_at desc), '[]'::jsonb)
      into result
      from public.qpark_promos p join public.qpark_locations l on l.id = p.location_id
      where target_loc_id is null or p.location_id = target_loc_id;
      return jsonb_build_object('promos', result, 'server_time', public.qpark_epoch(moment));
    elsif p_method = 'POST' then
      op_key := p_body->>'operation_key';
      replay := public.qpark_operation_replay(op_key, 'promo_save', staff_id::text, p_body);
      if replay is not null then return replay || jsonb_build_object('server_time', public.qpark_epoch(moment)); end if;
      target_loc_id := case when staff.role = 'SUPERADMIN' then coalesce(nullif(p_body->>'location_id', ''), 'LOC-DEFAULT') else coalesce(staff.location_id, 'LOC-DEFAULT') end;
      if not exists(select 1 from public.qpark_locations where id = target_loc_id) then
        perform public.qpark_fail('Lokasi parkir tidak ditemukan.', 'location_not_found', 404);
      end if;
      p_title := trim(coalesce(p_body->>'title', ''));
      p_desc := trim(coalesce(p_body->>'description', ''));
      p_code := upper(trim(coalesce(p_body->>'code', '')));
      p_dtype := coalesce(p_body->>'discount_type', 'PERCENT');
      p_dval := (p_body->>'discount_value')::integer;
      p_start := to_timestamp((p_body->>'starts_at')::double precision);
      p_end := to_timestamp((p_body->>'ends_at')::double precision);
      p_active := coalesce((p_body->>'active')::boolean, true);
      if length(p_title) < 1 or length(p_title) > 80 then
        perform public.qpark_fail('Judul promo wajib diisi (maksimal 80 karakter).', 'promo', 400);
      end if;
      if p_dtype not in ('PERCENT', 'FIXED') or p_dval is null
        or (p_dtype = 'PERCENT' and p_dval not between 1 and 100)
        or (p_dtype = 'FIXED' and p_dval not between 500 and 1000000) then
        perform public.qpark_fail('Nilai diskon tidak valid.', 'promo', 400);
      end if;
      if p_start is null or p_end is null or p_end <= p_start then
        perform public.qpark_fail('Waktu berakhir promo harus setelah waktu mulai.', 'promo', 400);
      end if;
      promo_id := nullif(p_body->>'id', '');
      if promo_id is not null then
        select * into promo_row from public.qpark_promos where id = promo_id;
        if not found then perform public.qpark_fail('Promo tidak ditemukan.', 'promo_not_found', 404); end if;
        if staff.role <> 'SUPERADMIN' and promo_row.location_id <> target_loc_id then
          perform public.qpark_fail('Promo ini milik lokasi lain.', 'location_forbidden', 403);
        end if;
        update public.qpark_promos set location_id = target_loc_id, title = p_title, description = p_desc,
          code = p_code, discount_type = p_dtype, discount_value = p_dval,
          starts_at = p_start, ends_at = p_end, active = p_active
        where id = promo_id returning * into promo_row;
      else
        promo_id := public.qpark_id('PRM');
        insert into public.qpark_promos(id, location_id, title, description, code, discount_type, discount_value, starts_at, ends_at, active, created_by, created_at)
        values (promo_id, target_loc_id, p_title, p_desc, p_code, p_dtype, p_dval, p_start, p_end, p_active, staff_id::text, moment)
        returning * into promo_row;
      end if;
      select name into p_desc from public.qpark_locations where id = promo_row.location_id;
      result := jsonb_build_object('promo', jsonb_build_object(
        'id', promo_row.id, 'location_id', promo_row.location_id, 'location_name', p_desc,
        'title', promo_row.title, 'description', promo_row.description, 'code', promo_row.code,
        'discount_type', promo_row.discount_type, 'discount_value', promo_row.discount_value,
        'starts_at', public.qpark_epoch(promo_row.starts_at), 'ends_at', public.qpark_epoch(promo_row.ends_at),
        'active', promo_row.active
      ));
      perform public.qpark_operation_save(op_key, 'promo_save', staff_id::text, p_body, result, moment);
      return result || jsonb_build_object('server_time', public.qpark_epoch(moment));
    end if;
  end if;

  -- EV bookings endpoints
  if p_path = '/api/ev/bookings' and p_method = 'GET' then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'location_id', b.location_id, 'location_name', l.name, 'location_address', l.address,
      'plate', b.plate, 'duration_hours', b.duration_hours, 'hourly_rate', b.hourly_rate,
      'estimated_cost', b.estimated_cost, 'status', b.status,
      'booked_at', public.qpark_epoch(b.booked_at), 'expires_at', public.qpark_epoch(b.expires_at)
    ) order by b.booked_at desc, b.id desc), '[]'::jsonb)
    into result from public.qpark_ev_bookings b join public.qpark_locations l on l.id = b.location_id
    where b.owner = owner_key;
    return jsonb_build_object('bookings', result, 'server_time', public.qpark_epoch(moment));
  end if;

  if p_path = '/api/ev/book' and p_method = 'POST' then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    op_key := p_body->>'operation_key';
    replay := public.qpark_operation_replay(op_key, 'ev_book', owner_key, p_body);
    if replay is null then
      target_loc_id := coalesce(nullif(p_body->>'location_id', ''), 'LOC-DEFAULT');
      select * into loc from public.qpark_locations where id = target_loc_id for update;
      if not found or not loc.active then perform public.qpark_fail('Lokasi parkir tidak ditemukan atau nonaktif.', 'location_not_found', 404); end if;
      norm_plate := public.qpark_plate(p_body->>'plate');
      dur_hours := coalesce((p_body->>'duration_hours')::integer, 1);
      if dur_hours not between 1 and 12 then perform public.qpark_fail('Durasi charging EV harus 1 hingga 12 jam.', 'duration', 400); end if;
      if not exists(select 1 from public.qpark_vehicle_categories where owner = owner_key and plate = norm_plate and is_ev) then
        perform public.qpark_fail('Booking EV hanya untuk kendaraan plat nomor biru yang sudah terdaftar.', 'ev_plate_required', 400);
      end if;
      if exists(select 1 from public.qpark_ev_bookings where plate = norm_plate and status = 'ACTIVE') then
        perform public.qpark_fail('Kendaraan ini sudah memiliki booking EV aktif.', 'ev_duplicate', 409);
      end if;
      select count(*) into ev_used from public.qpark_ev_bookings where location_id = loc.id and status = 'ACTIVE';
      if ev_used >= loc.ev_capacity then
        perform public.qpark_fail('Slot EV Charging di lokasi ini sedang penuh.', 'ev_full', 409);
      end if;
      bid := public.qpark_id('EVB');
      insert into public.qpark_ev_bookings(id, location_id, owner, plate, duration_hours, hourly_rate, estimated_cost, status, booked_at, expires_at)
      values (bid, loc.id, owner_key, norm_plate, dur_hours, loc.ev_rate, loc.ev_rate * dur_hours, 'ACTIVE', moment, moment + (dur_hours || ' hours')::interval);
      perform public.qpark_audit_event('EV_BOOKED', bid, owner_key, moment, norm_plate);
      replay := jsonb_build_object('booking', jsonb_build_object(
        'id', bid, 'location_id', loc.id, 'location_name', loc.name, 'location_address', loc.address,
        'plate', norm_plate, 'duration_hours', dur_hours, 'hourly_rate', loc.ev_rate,
        'estimated_cost', loc.ev_rate * dur_hours, 'status', 'ACTIVE',
        'booked_at', public.qpark_epoch(moment), 'expires_at', public.qpark_epoch(moment + (dur_hours || ' hours')::interval)
      ));
      perform public.qpark_operation_save(op_key, 'ev_book', owner_key, p_body, replay, moment);
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'location_id', b.location_id, 'location_name', l.name, 'location_address', l.address,
      'plate', b.plate, 'duration_hours', b.duration_hours, 'hourly_rate', b.hourly_rate,
      'estimated_cost', b.estimated_cost, 'status', b.status,
      'booked_at', public.qpark_epoch(b.booked_at), 'expires_at', public.qpark_epoch(b.expires_at)
    ) order by b.booked_at desc, b.id desc), '[]'::jsonb)
    into result from public.qpark_ev_bookings b join public.qpark_locations l on l.id = b.location_id where b.owner = owner_key;
    return replay || jsonb_build_object('bookings', result, 'server_time', public.qpark_epoch(moment));
  end if;

  if p_path = '/api/ev/cancel' and p_method = 'POST' then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    op_key := p_body->>'operation_key';
    replay := public.qpark_operation_replay(op_key, 'ev_cancel', owner_key, p_body);
    if replay is null then
      bid := p_body->>'booking_id';
      if not exists(select 1 from public.qpark_ev_bookings where id = bid and owner = owner_key) then
        perform public.qpark_fail('Booking EV tidak ditemukan.', 'not_found', 404);
      end if;
      update public.qpark_ev_bookings set status = 'CANCELLED' where id = bid and owner = owner_key and status = 'ACTIVE';
      replay := jsonb_build_object('cancelled', true, 'booking_id', bid);
      perform public.qpark_operation_save(op_key, 'ev_cancel', owner_key, p_body, replay, moment);
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'location_id', b.location_id, 'location_name', l.name, 'location_address', l.address,
      'plate', b.plate, 'duration_hours', b.duration_hours, 'hourly_rate', b.hourly_rate,
      'estimated_cost', b.estimated_cost, 'status', b.status,
      'booked_at', public.qpark_epoch(b.booked_at), 'expires_at', public.qpark_epoch(b.expires_at)
    ) order by b.booked_at desc, b.id desc), '[]'::jsonb)
    into result from public.qpark_ev_bookings b join public.qpark_locations l on l.id = b.location_id where b.owner = owner_key;
    return replay || jsonb_build_object('bookings', result, 'server_time', public.qpark_epoch(moment));
  end if;

  -- Enrich wallet inspect with active promos for session's location, and allow promo_id in wallet pay
  if p_path = '/api/wallet/inspect' and p_method = 'POST' then
    result := public.qpark_request_v5(p_method, p_path, p_query, p_body, p_token);
    target_loc_id := result->'session'->>'location_id';
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'location_id', p.location_id, 'title', p.title, 'description', p.description,
      'code', p.code, 'discount_type', p.discount_type, 'discount_value', p.discount_value,
      'starts_at', public.qpark_epoch(p.starts_at), 'ends_at', public.qpark_epoch(p.ends_at), 'active', p.active
    ) order by p.ends_at asc), '[]'::jsonb)
    into promos_json from public.qpark_promos p
    where p.active and p.location_id = target_loc_id and p.starts_at <= moment and p.ends_at >= moment;
    return result || jsonb_build_object('promos', promos_json);
  end if;

  if p_path = '/api/wallet/pay' and p_method = 'POST' and nullif(p_body->>'promo_id', '') is not null then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.', 'customer_identity', 401); end if;
    perform public.qpark_maintain(moment);
    op_key := p_body->>'operation_key';
    replay := public.qpark_operation_replay(op_key, 'wallet_pay', owner_key, p_body);
    if replay is null then
      inv_id := nullif(p_body->>'invoice_id', '');
      if inv_id is null then
        raw_qr := trim(coalesce(p_body->>'qr', ''));
        if raw_qr like 'QPP.SIMULASI.%' then inv_id := substr(raw_qr, 14);
        elsif raw_qr like 'QPP.%' then inv_id := substr(raw_qr, 5);
        else perform public.qpark_fail('QR bukan kode tagihan parkir QPark.', 'invalid_qr', 400);
        end if;
      end if;
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
        select * into promo_row from public.qpark_promos where id = p_body->>'promo_id';
        if not found then perform public.qpark_fail('Promo tidak ditemukan.', 'promo_not_found', 404); end if;
        if promo_row.location_id <> sess.location_id then perform public.qpark_fail('Promo tidak berlaku untuk lokasi parkir ini.', 'promo_location', 400); end if;
        if not promo_row.active or moment < promo_row.starts_at or moment > promo_row.ends_at then
          perform public.qpark_fail('Promo sudah berakhir atau belum berlaku.', 'promo_expired', 409);
        end if;
        disc := case when promo_row.discount_type = 'PERCENT' then (inv.amount * promo_row.discount_value) / 100 else promo_row.discount_value end;
        disc := greatest(0, least(inv.amount, disc));
        payable := greatest(0, inv.amount - disc);
        insert into public.qpark_wallets(owner, balance, updated_at) values (owner_key, 0, moment) on conflict (owner) do nothing;
        select balance into bal from public.qpark_wallets where owner = owner_key for update;
        if bal < payable then perform public.qpark_fail('Saldo Dompet QPark tidak mencukupi. Silakan Top Up terlebih dahulu.', 'insufficient_balance', 409); end if;
        new_bal := bal - payable;
        update public.qpark_wallets set balance = new_bal, updated_at = moment where owner = owner_key;
        select * into loc from public.qpark_locations where id = sess.location_id;
        if payable > 0 then
          tx_id := public.qpark_id('WLT');
          insert into public.qpark_wallet_transactions(id, owner, kind, amount, balance_after, description, reference_id, created_at)
          values (tx_id, owner_key, 'PAYMENT', payable, new_bal,
            'Bayar parkir ' || sess.plate || ' · ' || coalesce(loc.name, 'QPark') || ' (Promo: ' || promo_row.title || ')', inv.id, moment);
        end if;
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
          'attempt_id', att_id, 'paid_at', public.qpark_epoch(moment), 'discount', disc, 'payable', payable);
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

  return public.qpark_request_v5(p_method, p_path, p_query, p_body, p_token);
end;
$$;

revoke all on function public.qpark_request(text, text, jsonb, jsonb, text) from public;
grant execute on function public.qpark_request(text, text, jsonb, jsonb, text) to anon, authenticated;

commit;
