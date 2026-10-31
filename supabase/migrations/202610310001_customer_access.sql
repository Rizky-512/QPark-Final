-- Apply after 202610290005. Existing sessions stay staff-only until verified.
begin;
create table public.qpark_customer_links (
  session_id text primary key references public.qpark_parking_sessions(id),
  owner text not null
);
create index qpark_customer_links_owner_idx on public.qpark_customer_links(owner);
create table public.qpark_customer_codes (
  digest text primary key,
  owner text not null unique,
  plate text not null,
  expires_at timestamptz not null
);
alter table public.qpark_customer_links enable row level security;
alter table public.qpark_customer_codes enable row level security;
revoke all on public.qpark_customer_links, public.qpark_customer_codes from public, anon, authenticated;

-- Keep the old business implementation private; all external requests pass
-- through the ownership boundary, including requests to the old RPC name.
alter function public.qpark_request(text,text,jsonb,jsonb,text) rename to qpark_request_core;
revoke all on function public.qpark_request_core(text,text,jsonb,jsonb,text) from public, anon, authenticated;

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
    where (not p_public or (s.plate = plate_filter and exists (
        select 1 from public.qpark_customer_links l where l.session_id=s.id and l.owner=p_query->>'_owner'
      )))
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


create function public.qpark_request(
  p_method text, p_path text, p_query jsonb default '{}'::jsonb,
  p_body jsonb default '{}'::jsonb, p_token text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  moment timestamptz := clock_timestamp();
  customer_owner text;
  device_key text := p_query->>'_customer_key';
  safe_query jsonb := coalesce(p_query,'{}'::jsonb)-'_owner'-'_customer_key';
  sid text;
  normalized_plate text;
  code text;
  link public.qpark_customer_codes%rowtype;
  existing_owner text;
  actor uuid;
  result jsonb;
begin
  if jsonb_typeof(p_body) is distinct from 'object' or jsonb_typeof(p_query) is distinct from 'object' then
    perform public.qpark_fail('Payload JSON harus objek.','payload',400);
  end if;
  if auth.uid() is not null then
    if not exists(select 1 from public.profiles where id=auth.uid() and active) then
      perform public.qpark_fail('Akun tidak aktif.','customer_identity',403);
    end if;
    customer_owner := 'user:'||auth.uid()::text;
  elsif device_key ~ '^[a-f0-9]{48}$' then
    customer_owner := 'demo:'||encode(extensions.digest(device_key,'sha256'),'hex');
  end if;

  if p_method='POST' and p_path='/api/customer/code' then
    if customer_owner is null then
      perform public.qpark_fail('Masuk atau gunakan identitas perangkat demo.','customer_identity',401);
    end if;
    normalized_plate := public.qpark_plate(p_body->>'plate');
    code := upper(encode(extensions.gen_random_bytes(6),'hex'));
    delete from public.qpark_customer_codes where expires_at<=moment;
    insert into public.qpark_customer_codes(digest,owner,plate,expires_at)
      values(encode(extensions.digest(code,'sha256'),'hex'),customer_owner,normalized_plate,moment+interval '15 minutes')
      on conflict(owner) do update set digest=excluded.digest,plate=excluded.plate,expires_at=excluded.expires_at;
    return jsonb_build_object('code',code,'expires_at',public.qpark_epoch(moment+interval '15 minutes'),'server_time',public.qpark_epoch(moment));
  end if;

  if p_method='POST' and p_path='/api/officer/link' then
    actor := public.qpark_staff_for_token(p_token,moment,false);
    normalized_plate := public.qpark_plate(p_body->>'plate');
    if p_body->>'verified' is distinct from 'true' then
      perform public.qpark_fail('Cocokkan kendaraan fisik terlebih dahulu.','verification',400);
    end if;
    select id into sid from public.qpark_parking_sessions where plate=normalized_plate and state<>'COMPLETED' for update;
    if sid is null then perform public.qpark_fail('Kendaraan aktif tidak ditemukan.','not_found',404); end if;
    select * into link from public.qpark_customer_codes
      where digest=encode(extensions.digest(upper(trim(coalesce(p_body->>'code',''))),'sha256'),'hex')
        and plate=normalized_plate and expires_at>moment for update;
    if not found then perform public.qpark_fail('Kode tidak valid atau kedaluwarsa.','link_code',400); end if;
    select owner into existing_owner from public.qpark_customer_links where session_id=sid;
    if existing_owner is not null and existing_owner<>link.owner then
      perform public.qpark_fail('Tiket sudah terhubung ke pelanggan lain.','ticket_owner',409);
    end if;
    insert into public.qpark_customer_links values(sid,link.owner) on conflict(session_id) do nothing;
    perform public.qpark_audit_event('CUSTOMER_LINK',sid,actor::text,moment);
    return jsonb_build_object('linked',true,'server_time',public.qpark_epoch(moment));
  end if;

  if p_path in ('/api/ticket','/api/history','/api/invoice','/api/payment') then
    if customer_owner is null then
      perform public.qpark_fail('Masuk atau gunakan identitas perangkat demo.','customer_identity',401);
    end if;
    if p_method='GET' and p_path='/api/ticket' then
      normalized_plate := public.qpark_plate(safe_query->>'plate');
      select s.id into sid from public.qpark_parking_sessions s
        join public.qpark_customer_links l on l.session_id=s.id
        where l.owner=customer_owner and s.plate=normalized_plate
          and (s.state<>'COMPLETED' or s.id=safe_query->>'previous')
        order by (s.state<>'COMPLETED') desc limit 1;
      perform public.qpark_maintain(moment);
      return jsonb_build_object('session',case when sid is null then null else public.qpark_session_view(sid,moment,true) end,
        'server_time',public.qpark_epoch(moment));
    elsif p_method='GET' and p_path='/api/history' then
      safe_query := safe_query||jsonb_build_object('_owner',customer_owner);
    elsif p_method='POST' then
      sid := p_body->>'session_id';
      if p_path='/api/payment' then
        select session_id into sid from public.qpark_invoices where id=p_body->>'invoice_id';
      end if;
      if not exists(select 1 from public.qpark_customer_links where session_id=sid and owner=customer_owner) then
        perform public.qpark_fail('Tiket tidak tersedia untuk pelanggan ini.','ticket_owner',403);
      end if;
    end if;
  end if;
  result := public.qpark_request_core(p_method,p_path,safe_query,p_body,p_token);
  return result;
end;
$$;
revoke all on function public.qpark_request(text,text,jsonb,jsonb,text) from public;
grant execute on function public.qpark_request(text,text,jsonb,jsonb,text) to anon, authenticated;
commit;
