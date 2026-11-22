begin;

-- Preserve the former total and all active sessions. Admin can adjust this
-- initial allocation after migration; no vehicle category is guessed.
alter table public.qpark_settings add column car_capacity integer;
alter table public.qpark_settings add column motor_capacity integer;
update public.qpark_settings set car_capacity=greatest(capacity/2,
  (select count(*) from public.qpark_parking_sessions where state<>'COMPLETED' and vehicle_type='MOBIL'));
update public.qpark_settings set motor_capacity=greatest(capacity-car_capacity,
  (select count(*) from public.qpark_parking_sessions where state<>'COMPLETED' and vehicle_type='MOTOR'));
alter table public.qpark_settings drop constraint qpark_settings_capacity_check;
update public.qpark_settings set capacity=car_capacity+motor_capacity;
alter table public.qpark_settings alter column car_capacity set not null;
alter table public.qpark_settings alter column motor_capacity set not null;
alter table public.qpark_settings add check(car_capacity between 0 and 1000000);
alter table public.qpark_settings add check(motor_capacity between 0 and 1000000);
alter table public.qpark_settings add check(capacity=car_capacity+motor_capacity);

create table public.qpark_vehicle_categories (
  owner text not null, plate text not null,
  vehicle_type text not null check(vehicle_type in ('MOBIL','MOTOR')),
  primary key(owner,plate)
);
create index qpark_vehicle_categories_plate on public.qpark_vehicle_categories(plate);
alter table public.qpark_vehicle_categories enable row level security;
revoke all on public.qpark_vehicle_categories from anon,authenticated;

-- Keep the established transaction/idempotency implementation. Patch only the
-- entry capacity check and fail the migration if its expected source changed.
do $$
declare definition text;
  old_part text := $old$select count(*) into active_count from public.qpark_parking_sessions where state<>'COMPLETED';
        if active_count>=settings.capacity then$old$;
  new_part text := $new$select count(*) into active_count from public.qpark_parking_sessions where state<>'COMPLETED' and vehicle_type=p_body->>'vehicle_type';
        if active_count>=(case when p_body->>'vehicle_type'='MOTOR' then settings.motor_capacity else settings.car_capacity end) then$new$;
begin
  definition := replace(pg_get_functiondef('public.qpark_request_core(text,text,jsonb,jsonb,text)'::regprocedure),chr(13),'');
  old_part := replace(old_part,chr(13),'');
  new_part := replace(new_part,chr(13),'');
  if strpos(definition,old_part)=0 then raise exception 'Unexpected entry capacity implementation'; end if;
  execute replace(definition,old_part,new_part);
end $$;

alter function public.qpark_request(text,text,jsonb,jsonb,text) rename to qpark_request_access;
revoke all on function public.qpark_request_access(text,text,jsonb,jsonb,text) from public,anon,authenticated;

create function public.qpark_request(
  p_method text,p_path text,p_query jsonb default '{}'::jsonb,
  p_body jsonb default '{}'::jsonb,p_token text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
<<capacity_api>>
declare
  moment timestamptz:=clock_timestamp();
  settings public.qpark_settings%rowtype;
  owner_key text; normalized_plate text; kind text; saved_kind text;
  cars integer; motors integer; car_used integer; motor_used integer;
  car_rate integer; motor_rate integer;
  actor uuid; result jsonb; categories jsonb;
begin
  if jsonb_typeof(p_body) is distinct from 'object' or jsonb_typeof(p_query) is distinct from 'object' then
    perform public.qpark_fail('Payload JSON harus objek.','payload',400);
  end if;
  if auth.uid() is not null then
    if not exists(select 1 from public.profiles where id=auth.uid() and active) then
      perform public.qpark_fail('Akun tidak aktif.','customer_identity',403);
    end if;
    owner_key:='user:'||auth.uid()::text;
  elsif p_query->>'_customer_key' ~ '^[a-f0-9]{48}$' then
    owner_key:='demo:'||encode(extensions.digest(p_query->>'_customer_key','sha256'),'hex');
  end if;

  if p_path='/api/capacity' and p_method='GET' then
    -- A single statement gives settings and occupancy one consistent snapshot.
    select s.car_capacity,s.motor_capacity,s.car_rate,s.motor_rate,
      count(p.id) filter(where p.vehicle_type='MOBIL'),count(p.id) filter(where p.vehicle_type='MOTOR')
      into cars,motors,car_rate,motor_rate
      ,car_used,motor_used
      from public.qpark_settings s left join public.qpark_parking_sessions p on p.state<>'COMPLETED'
      where s.singleton group by s.car_capacity,s.motor_capacity,s.car_rate,s.motor_rate;
    categories:=jsonb_build_object(
      'MOBIL',jsonb_build_object('total',cars,'occupied',car_used,'available',greatest(0,cars-car_used),'full',car_used>=cars),
      'MOTOR',jsonb_build_object('total',motors,'occupied',motor_used,'available',greatest(0,motors-motor_used),'full',motor_used>=motors));
    return jsonb_build_object('categories',categories,'total',cars+motors,'occupied',car_used+motor_used,
      'available',greatest(0,cars-car_used)+greatest(0,motors-motor_used),'full',car_used>=cars and motor_used>=motors,
      'rates',jsonb_build_object('MOBIL',car_rate,'MOTOR',motor_rate),'server_time',public.qpark_epoch(moment));
  end if;

  if p_path='/api/admin/settings' then
    actor:=public.qpark_staff_for_token(p_token,moment,true);
    select * into settings from public.qpark_settings where singleton for update;
    if p_method='POST' then
      if not (p_body->>'car_capacity' ~ '^\d{1,7}$' and p_body->>'motor_capacity' ~ '^\d{1,7}$'
        and p_body->>'car_rate' ~ '^\d{1,7}$' and p_body->>'motor_rate' ~ '^\d{1,7}$')
        or not (p_body ?& array['car_capacity','motor_capacity','car_rate','motor_rate']) then
        perform public.qpark_fail('Isi kapasitas dan tarif setiap jenis kendaraan.','settings',400);
      end if;
      cars:=(p_body->>'car_capacity')::integer; motors:=(p_body->>'motor_capacity')::integer;
      car_rate:=(p_body->>'car_rate')::integer; motor_rate:=(p_body->>'motor_rate')::integer;
      if cars is null or motors is null or car_rate is null or motor_rate is null or cars not between 0 and 1000000 or motors not between 0 and 1000000
        or car_rate not between 1 and 1000000 or motor_rate not between 1 and 1000000 then
        perform public.qpark_fail('Isi kapasitas 0–1.000.000 dan tarif 1–1.000.000.','settings',400);
      end if;
      select count(*) filter(where vehicle_type='MOBIL'),count(*) filter(where vehicle_type='MOTOR') into car_used,motor_used
        from public.qpark_parking_sessions where state<>'COMPLETED';
      if cars<car_used or motors<motor_used then
        perform public.qpark_fail('Kapasitas setiap jenis tidak boleh di bawah jumlah kendaraan aktif.','capacity',409);
      end if;
      update public.qpark_settings set car_capacity=cars,motor_capacity=motors,capacity=cars+motors,
        car_rate=capacity_api.car_rate,motor_rate=capacity_api.motor_rate,updated_at=moment where singleton returning * into settings;
      perform public.qpark_audit_event('SETTINGS_CHANGED','parking',actor::text,moment,p_body::text);
    elsif p_method<>'GET' then
      perform public.qpark_fail('Metode tidak didukung.','method',405);
    end if;
    return jsonb_build_object('settings',jsonb_build_object('capacity',settings.capacity,'car_capacity',settings.car_capacity,
      'motor_capacity',settings.motor_capacity,'car_rate',settings.car_rate,'motor_rate',settings.motor_rate),'server_time',public.qpark_epoch(moment));
  end if;

  if p_path in ('/api/customer/vehicle-types','/api/customer/vehicle-type') then
    if owner_key is null then perform public.qpark_fail('Identitas pelanggan diperlukan.','customer_identity',401); end if;
    if p_method='GET' and p_path='/api/customer/vehicle-types' then
      select coalesce(jsonb_object_agg(plate,vehicle_type),'{}'::jsonb) into result from public.qpark_vehicle_categories where owner=owner_key;
      return jsonb_build_object('vehicle_types',result,'server_time',public.qpark_epoch(moment));
    end if;
    normalized_plate:=public.qpark_plate(p_body->>'plate');
    perform 1 from public.qpark_settings where singleton for update;
    if p_method='POST' and p_body->>'remove'='true' then
      delete from public.qpark_vehicle_categories where owner=owner_key and plate=normalized_plate;
      return jsonb_build_object('removed',true);
    end if;
    kind:=p_body->>'vehicle_type';
    if p_method<>'POST' or kind is null or kind not in ('MOBIL','MOTOR') then perform public.qpark_fail('Pilih Mobil atau Motor.','vehicle',400); end if;
    if exists(select 1 from public.qpark_parking_sessions where plate=normalized_plate and state<>'COMPLETED' and vehicle_type<>kind) then
      perform public.qpark_fail('Kategori tidak dapat berubah selama kendaraan sedang parkir.','vehicle_active',409);
    end if;
    if exists(select 1 from public.qpark_vehicle_categories where plate=normalized_plate and owner<>owner_key and vehicle_type<>kind) then
      perform public.qpark_fail('Kategori nopol berbeda dari data tersimpan. Periksa nopol Anda.','vehicle_conflict',409);
    end if;
    insert into public.qpark_vehicle_categories values(owner_key,normalized_plate,kind)
      on conflict(owner,plate) do update set vehicle_type=excluded.vehicle_type;
    return jsonb_build_object('vehicle_type',kind);
  end if;

  if p_path='/api/officer/vehicle-type' and p_method='GET' then
    actor:=public.qpark_staff_for_token(p_token,moment,false);
    normalized_plate:=public.qpark_plate(p_query->>'plate');
    select vehicle_type into kind from public.qpark_vehicle_categories where plate=normalized_plate limit 1;
    return jsonb_build_object('vehicle_type',kind);
  end if;
  if p_path='/api/officer/entry' and p_method='POST' then
    actor:=public.qpark_staff_for_token(p_token,moment,false);
    perform 1 from public.qpark_settings where singleton for update;
    normalized_plate:=public.qpark_plate(p_body->>'plate');
    select vehicle_type into saved_kind from public.qpark_vehicle_categories where plate=normalized_plate limit 1;
    if saved_kind is not null then p_body:=p_body||jsonb_build_object('vehicle_type',saved_kind); end if;
  end if;
  return public.qpark_request_access(p_method,p_path,p_query,p_body,p_token);
end $$;
revoke all on function public.qpark_request(text,text,jsonb,jsonb,text) from public;
grant execute on function public.qpark_request(text,text,jsonb,jsonb,text) to anon,authenticated;
commit;
