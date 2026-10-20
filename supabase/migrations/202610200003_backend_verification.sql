begin;

do $$
declare
  staff_id uuid;
  raw_token text := encode(extensions.gen_random_bytes(32), 'hex');
  suffix text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  test_plate text;
  entry_key text;
  payment_key text;
  authorize_key text;
  complete_key text;
  entry_result jsonb;
  invoice_result jsonb;
  payment_result jsonb;
  authorize_result jsonb;
  complete_result jsonb;
  test_session_id text;
  test_invoice_id text;
  test_authorization_id text;
  qr_token text;
begin
  test_plate := 'MIG' || suffix;
  entry_key := 'verify-entry-' || suffix;
  payment_key := 'verify-payment-' || suffix;
  authorize_key := 'verify-authorize-' || suffix;
  complete_key := 'verify-complete-' || suffix;

  select id into staff_id from public.qpark_staff where username = 'petugas';
  if staff_id is null then raise exception 'Verification requires seeded petugas account'; end if;

  insert into public.qpark_staff_sessions(token_hash, staff_id, expires_at)
  values (encode(extensions.digest(raw_token, 'sha256'), 'hex'), staff_id, now() + interval '5 minutes');

  entry_result := public.qpark_request(
    'POST', '/api/officer/entry', '{}'::jsonb,
    jsonb_build_object(
      'plate', test_plate, 'vehicle_type', 'MOBIL', 'verified', true,
      'image_readable', false, 'image_source', 'manual', 'operation_key', entry_key
    ), raw_token
  );
  test_session_id := entry_result->>'session_id';
  if test_session_id is null or entry_result#>>'{session,state}' <> 'IN_AREA' then
    raise exception 'Entry verification failed';
  end if;

  invoice_result := public.qpark_request(
    'POST', '/api/invoice', '{}'::jsonb,
    jsonb_build_object('session_id', test_session_id), null
  );
  test_invoice_id := invoice_result#>>'{invoice,id}';
  if test_invoice_id is null then raise exception 'Invoice verification failed'; end if;

  payment_result := public.qpark_request(
    'POST', '/api/payment', '{}'::jsonb,
    jsonb_build_object('invoice_id', test_invoice_id, 'outcome', 'SUCCESS', 'operation_key', payment_key), null
  );
  qr_token := payment_result#>>'{session,exit_qr}';
  if qr_token is null or payment_result->>'outcome' <> 'SUCCESS' then
    raise exception 'Payment verification failed';
  end if;

  authorize_result := public.qpark_request(
    'POST', '/api/officer/authorize', '{}'::jsonb,
    jsonb_build_object(
      'qr', qr_token, 'plate', test_plate, 'verified', true,
      'operation_key', authorize_key
    ), raw_token
  );
  test_authorization_id := authorize_result->>'authorization_id';
  if test_authorization_id is null or authorize_result#>>'{session,state}' <> 'EXIT_AUTHORIZED' then
    raise exception 'Authorization verification failed';
  end if;

  complete_result := public.qpark_request(
    'POST', '/api/officer/complete', '{}'::jsonb,
    jsonb_build_object(
      'session_id', test_session_id, 'authorization_id', test_authorization_id,
      'passed', true, 'operation_key', complete_key
    ), raw_token
  );
  if complete_result#>>'{session,state}' <> 'COMPLETED' then
    raise exception 'Completion verification failed';
  end if;

  delete from public.qpark_audit
    where entity_id in (test_session_id, test_invoice_id, test_authorization_id);
  delete from public.qpark_operations
    where key in (entry_key, payment_key, authorize_key, complete_key);
  delete from public.qpark_authorizations a where a.session_id = test_session_id;
  delete from public.qpark_payment_attempts a where a.invoice_id = test_invoice_id;
  update public.qpark_invoices i set window_id = null where i.session_id = test_session_id;
  delete from public.qpark_exit_windows w where w.session_id = test_session_id;
  delete from public.qpark_invoices i where i.session_id = test_session_id;
  delete from public.qpark_parking_sessions s where s.id = test_session_id;
  delete from public.qpark_staff_sessions
    where token_hash = encode(extensions.digest(raw_token, 'sha256'), 'hex');
end $$;

commit;
