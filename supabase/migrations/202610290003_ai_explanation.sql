begin;
create table if not exists public.qpark_ai_usage (
  staff_id uuid primary key references public.qpark_staff(id) on delete cascade,
  requested_at timestamptz not null
);
alter table public.qpark_ai_usage enable row level security;
revoke all on public.qpark_ai_usage from anon, authenticated;

create or replace function public.qpark_ai_claim(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid; moment timestamptz := clock_timestamp();
begin
  actor := public.qpark_staff_for_token(p_token,moment,true);
  insert into public.qpark_ai_usage(staff_id,requested_at) values(actor,moment)
  on conflict(staff_id) do update set requested_at=excluded.requested_at
    where public.qpark_ai_usage.requested_at < moment-interval '1 minute';
  if not found then
    perform public.qpark_fail('Tunggu satu menit sebelum mencoba lagi.','rate_limit',429);
  end if;
  return jsonb_build_object('capacity',(select capacity from public.qpark_settings where singleton));
end;
$$;
revoke all on function public.qpark_ai_claim(text) from public, anon, authenticated;
grant execute on function public.qpark_ai_claim(text) to service_role;
commit;
