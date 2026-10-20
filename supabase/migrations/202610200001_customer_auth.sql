begin;

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_url text,
  role text not null default 'CUSTOMER'
    check (role in ('CUSTOMER', 'PETUGAS', 'ADMIN')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plate text not null check (plate ~ '^[A-Z0-9]{1,32}$'),
  created_at timestamptz not null default now(),
  unique (user_id, plate)
);

create index if not exists customer_vehicles_user_created_idx
  on public.customer_vehicles(user_id, created_at);

alter table public.profiles enable row level security;
alter table public.customer_vehicles enable row level security;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', split_part(coalesce(new.email, ''), '@', 1)),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do update
    set display_name = excluded.display_name,
        avatar_url = excluded.avatar_url,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of raw_user_meta_data on auth.users
  for each row execute procedure public.handle_new_user();

-- Backfill users created before this migration.
insert into public.profiles (id, display_name, avatar_url)
select
  id,
  coalesce(raw_user_meta_data ->> 'full_name', raw_user_meta_data ->> 'name', split_part(coalesce(email, ''), '@', 1)),
  raw_user_meta_data ->> 'avatar_url'
from auth.users
on conflict (id) do nothing;

create or replace function public.is_active_staff(required_role text default 'PETUGAS')
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and active
      and case
        when required_role = 'ADMIN' then role = 'ADMIN'
        else role in ('PETUGAS', 'ADMIN')
      end
  );
$$;

revoke all on function public.is_active_staff(text) from public;
grant execute on function public.is_active_staff(text) to authenticated;

drop policy if exists "profiles_read_own_or_staff" on public.profiles;
create policy "profiles_read_own_or_staff"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.is_active_staff());

drop policy if exists "vehicles_read_own" on public.customer_vehicles;
create policy "vehicles_read_own"
on public.customer_vehicles for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "vehicles_insert_own" on public.customer_vehicles;
create policy "vehicles_insert_own"
on public.customer_vehicles for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "vehicles_update_own" on public.customer_vehicles;
create policy "vehicles_update_own"
on public.customer_vehicles for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "vehicles_delete_own" on public.customer_vehicles;
create policy "vehicles_delete_own"
on public.customer_vehicles for delete
to authenticated
using (user_id = auth.uid());

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.customer_vehicles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant select, insert, update, delete on table public.customer_vehicles to authenticated;

commit;
