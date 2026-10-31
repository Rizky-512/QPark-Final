-- Runs inside a disposable test database; rollback leaves no sample data.
begin;
create function pg_temp.expect_denied(method text, path text, query jsonb, body jsonb, token text, expected integer)
returns void language plpgsql as $$
begin
  perform public.qpark_request(method,path,query,body,token);
  raise exception 'Expected access rejection for %',path;
exception when raise_exception then
  if sqlerrm not like '{%' then raise; end if;
  if (sqlerrm::jsonb->>'status')::integer <> expected then raise; end if;
end;
$$;

do $$
declare
  staff_token text;
  sid text;
  target_invoice text;
  pairing text;
  qa jsonb := jsonb_build_object('_customer_key',repeat('a',48),'plate','SECURE1');
  qb jsonb := jsonb_build_object('_customer_key',repeat('b',48),'plate','SECURE1');
  result jsonb;
  account_id uuid := gen_random_uuid();
begin
  if has_function_privilege('anon','public.qpark_request_core(text,text,jsonb,jsonb,text)','EXECUTE') or
     has_function_privilege('authenticated','public.qpark_request_core(text,text,jsonb,jsonb,text)','EXECUTE') then
    raise exception 'Private core is externally callable';
  end if;
  if has_table_privilege('anon','public.qpark_customer_links','SELECT') then
    raise exception 'Ownership table is public';
  end if;
  staff_token := public.qpark_request('POST','/api/login','{}','{"username":"petugas","password":"petugas123"}',null)->>'token';
  result := public.qpark_request('POST','/api/officer/entry','{}',
    '{"plate":"SECURE1","vehicle_type":"MOBIL","verified":true,"image_source":"manual","operation_key":"secure-entry-test"}',staff_token);
  sid := result->>'session_id';
  if public.qpark_request('GET','/api/ticket',qa)->'session' <> 'null'::jsonb then raise exception 'Unlinked ticket leaked'; end if;
  pairing := public.qpark_request('POST','/api/customer/code',qa,'{"plate":"SECURE1"}')->>'code';
  perform pg_temp.expect_denied('POST','/api/officer/link','{}',jsonb_build_object('plate','SECURE1','code',pairing,'verified',true),null,401);
  perform public.qpark_request('POST','/api/officer/link','{}',jsonb_build_object('plate','SECURE1','code',pairing,'verified',true),staff_token);
  -- Lost link response can replay safely.
  perform public.qpark_request('POST','/api/officer/link','{}',jsonb_build_object('plate','SECURE1','code',pairing,'verified',true),staff_token);
  if public.qpark_request('GET','/api/ticket',qa)#>>'{session,id}' <> sid then raise exception 'Owner cannot read ticket'; end if;
  if public.qpark_request('GET','/api/ticket',qb)->'session' <> 'null'::jsonb then raise exception 'Other customer sees ticket'; end if;
  if (public.qpark_request('GET','/api/history',qb)->>'total')::int <> 0 then raise exception 'History leaked'; end if;
  -- Caller cannot forge private history scope.
  if (public.qpark_request('GET','/api/history',qb||jsonb_build_object('_owner','demo:'||encode(extensions.digest(repeat('a',48),'sha256'),'hex')))->>'total')::int <> 0 then raise exception 'Scope injection'; end if;
  target_invoice := public.qpark_request('POST','/api/invoice',qa,jsonb_build_object('session_id',sid))#>>'{invoice,id}';
  perform pg_temp.expect_denied('POST','/api/invoice',qb,jsonb_build_object('session_id',sid),null,403);
  perform pg_temp.expect_denied('POST','/api/payment',qb,jsonb_build_object('invoice_id',target_invoice,'outcome','SUCCESS','operation_key','secure-payment-test'),null,403);
  perform public.qpark_request('POST','/api/payment',qa,jsonb_build_object('invoice_id',target_invoice,'outcome','SUCCESS','operation_key','secure-payment-test'));
  perform public.qpark_request('POST','/api/payment',qa,jsonb_build_object('invoice_id',target_invoice,'outcome','SUCCESS','operation_key','secure-payment-test'));
  if (select count(*) from public.qpark_payment_attempts a where a.invoice_id=target_invoice) <> 1 then raise exception 'Duplicate payment'; end if;
  pairing := public.qpark_request('POST','/api/customer/code',qb,'{"plate":"SECURE1"}')->>'code';
  perform pg_temp.expect_denied('POST','/api/officer/link','{}',jsonb_build_object('plate','SECURE1','code',pairing,'verified',true),staff_token,409);
  update public.qpark_customer_codes set expires_at=now()-interval '1 second';
  perform pg_temp.expect_denied('POST','/api/officer/link','{}',jsonb_build_object('plate','SECURE1','code',pairing,'verified',true),staff_token,400);
  perform pg_temp.expect_denied('GET','/api/ticket','{"plate":"SECURE1"}','{}',null,401);

  -- An authenticated account uses auth.uid(), never a supplied guest key.
  insert into auth.users(id,email,raw_user_meta_data) values(account_id,'security-test@example.invalid','{}');
  perform set_config('request.jwt.claim.sub',account_id::text,true);
  if public.qpark_request('GET','/api/ticket',qa)->'session' <> 'null'::jsonb then raise exception 'Account inherited guest access'; end if;
  update public.profiles set active=false where id=account_id;
  perform pg_temp.expect_denied('POST','/api/customer/code',qa,'{"plate":"SECURE1"}',null,403);
end;
$$;
rollback;
