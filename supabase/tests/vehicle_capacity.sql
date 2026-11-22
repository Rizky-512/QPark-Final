begin;
create function pg_temp.capacity_denied(method text,path text,query jsonb,body jsonb,token text,expected integer)
returns void language plpgsql as $$
begin
  perform public.qpark_request(method,path,query,body,token);
  raise exception 'Expected rejection: %',path;
exception when raise_exception then
  if sqlerrm not like '{%' then raise; end if;
  if (sqlerrm::jsonb->>'status')::integer<>expected then raise; end if;
end $$;
do $$
declare admin_token text; staff_token text; r jsonb; cap jsonb; sid text; inv jsonb;
  customer jsonb:=jsonb_build_object('_customer_key',repeat('c',48));
begin
  if has_function_privilege('anon','public.qpark_request_access(text,text,jsonb,jsonb,text)','execute')
    or has_table_privilege('authenticated','public.qpark_vehicle_categories','select') then raise exception 'Private category data exposed'; end if;
  admin_token:=public.qpark_request('POST','/api/login','{}','{"username":"admin","password":"admin123"}')->>'token';
  staff_token:=public.qpark_request('POST','/api/login','{}','{"username":"petugas","password":"petugas123"}')->>'token';
  perform pg_temp.capacity_denied('POST','/api/admin/settings','{}','{"car_capacity":2,"motor_capacity":1,"car_rate":7000,"motor_rate":2000}',staff_token,403);
  perform pg_temp.capacity_denied('POST','/api/admin/settings','{}','{"car_capacity":null,"motor_capacity":1,"car_rate":7000,"motor_rate":2000}',admin_token,400);
  perform public.qpark_request('POST','/api/admin/settings','{}','{"car_capacity":0,"motor_capacity":0,"car_rate":7000,"motor_rate":2000}',admin_token);
  if public.qpark_request('GET','/api/capacity')->>'full'<>'true' then raise exception 'Zero capacity is not closed'; end if;
  perform public.qpark_request('GET','/api/admin/analytics','{}','{}',admin_token);
  perform public.qpark_request('POST','/api/admin/settings','{}','{"car_capacity":2,"motor_capacity":1,"car_rate":7000,"motor_rate":2000}',admin_token);
  cap:=public.qpark_request('GET','/api/capacity');
  if cap#>>'{categories,MOBIL,available}'<>'2' or cap#>>'{categories,MOTOR,available}'<>'1' then raise exception 'Wrong public capacity'; end if;
  perform pg_temp.capacity_denied('GET','/api/officer/vehicle-type','{"plate":"TYPE1"}','{}',null,401);
  perform public.qpark_request('POST','/api/customer/vehicle-type',customer,'{"plate":"TYPE1","vehicle_type":"MOTOR"}');
  r:=public.qpark_request('GET','/api/officer/vehicle-type','{"plate":"TYPE1"}','{}',staff_token);
  if r->>'vehicle_type'<>'MOTOR' then raise exception 'Saved category missing'; end if;
  -- The backend resolves registered category even when a client sends a wrong fallback.
  r:=public.qpark_request('POST','/api/officer/entry','{}','{"plate":"TYPE1","vehicle_type":"MOBIL","verified":true,"image_source":"manual","operation_key":"type-entry-1"}',staff_token);
  sid:=r->>'session_id';
  if r#>>'{session,vehicle_type}'<>'MOTOR' then raise exception 'Wrong category admitted'; end if;
  perform pg_temp.capacity_denied('POST','/api/customer/vehicle-type',customer,'{"plate":"TYPE1","vehicle_type":"MOBIL"}',null,409);
  perform pg_temp.capacity_denied('POST','/api/admin/settings','{}','{"car_capacity":2,"motor_capacity":0,"car_rate":7000,"motor_rate":2000}',admin_token,409);
  perform pg_temp.capacity_denied('POST','/api/officer/entry','{}','{"plate":"TYPE2","vehicle_type":"MOTOR","verified":true,"image_source":"manual","operation_key":"type-entry-2"}',staff_token,409);
  perform public.qpark_request('POST','/api/officer/entry','{}','{"plate":"TYPE3","vehicle_type":"MOBIL","verified":true,"image_source":"manual","operation_key":"type-entry-3"}',staff_token);
  cap:=public.qpark_request('GET','/api/capacity');
  if cap#>>'{categories,MOBIL,available}'<>'1' or cap#>>'{categories,MOTOR,full}'<>'true' then raise exception 'Shared capacity remains'; end if;
  inv:=public.qpark_request('POST','/api/officer/manual-quote','{}',jsonb_build_object('session_id',sid),staff_token)->'invoice';
  r:=public.qpark_request('POST','/api/officer/manual-pay','{}',jsonb_build_object('session_id',sid,'invoice_id',inv->>'id','expected_amount',inv->'amount','received',10000,'verified',true,'plate','TYPE1','operation_key','type-pay'),staff_token)->'session';
  if public.qpark_request('GET','/api/capacity')#>>'{categories,MOTOR,available}'<>'0' then raise exception 'Payment released capacity'; end if;
  perform public.qpark_request('POST','/api/officer/complete','{}',jsonb_build_object('session_id',sid,'authorization_id',r#>>'{authorization,id}','passed',true,'operation_key','type-exit'),staff_token);
  if public.qpark_request('GET','/api/capacity')#>>'{categories,MOTOR,available}'<>'1' then raise exception 'Exit did not free motorcycle slot'; end if;
end $$;
rollback;
