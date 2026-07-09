-- ============================================================
-- Patient Care — Supabase schema + roles + Row Level Security
-- Roles: admin (full) · recorder (record data) · viewer (read + print)
-- Re-run this whole script any time to (re)apply.
-- ============================================================

create table if not exists action_log (
  id bigserial primary key,
  log_date date not null,
  logged_at timestamptz default now(),
  action_type text,
  action_detail text,
  status text default 'done',
  client_id text
);

create table if not exists vitals (
  id bigserial primary key,
  log_date date not null,
  recorded_at timestamptz default now(),
  temp numeric,
  systolic int,
  diastolic int,
  pulse int,
  resp_rate int,
  spo2 int,
  glucose numeric,
  urine text,
  stool text,
  urine_note text,
  stool_note text
);

create table if not exists medications_log (
  id bigserial primary key,
  log_date date not null,
  slot_time text,
  med_name text,
  crush_confirmed bool default false,
  flush_done bool default false,
  given_at timestamptz default now()
);

create table if not exists suppository_log (
  id bigserial primary key,
  given_date date not null,
  given_at timestamptz default now()
);

-- ---- Roles ----
create table if not exists app_roles (
  email text primary key,
  role text not null check (role in ('admin','recorder','viewer')),
  updated_at timestamptz default now()
);

-- make sure an old constraint (admin/viewer only) is replaced
alter table app_roles drop constraint if exists app_roles_role_check;
alter table app_roles add constraint app_roles_role_check check (role in ('admin','recorder','viewer'));

insert into app_roles (email, role) values
  ('admin@careportal.com',   'admin'),
  ('jocel@careportal.com',   'recorder'),
  ('ahmed@careportal.com',   'viewer'),
  ('mervat@careportal.com',  'viewer'),
  ('mohamed@careportal.com', 'viewer'),
  ('eyad@careportal.com',    'viewer'),
  ('radwa@careportal.com',   'viewer'),
  ('yasmine@careportal.com', 'viewer')
on conflict (email) do update set
  role = excluded.role,
  updated_at = now();

create or replace function current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select role
      from app_roles
      where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      limit 1
    ),
    'viewer'
  );
$$;

-- helper: can this user write (record) data?
create or replace function can_write()
returns boolean
language sql
stable
as $$ select current_user_role() in ('admin','recorder'); $$;

-- ---- Row Level Security ----
alter table action_log enable row level security;
alter table vitals enable row level security;
alter table medications_log enable row level security;
alter table suppository_log enable row level security;
alter table app_roles enable row level security;

-- clean old policies
drop policy if exists "authenticated_select_action_log" on action_log;
drop policy if exists "authenticated_select_vitals" on vitals;
drop policy if exists "authenticated_select_medications_log" on medications_log;
drop policy if exists "authenticated_select_suppository_log" on suppository_log;
drop policy if exists "write_insert_action_log" on action_log;
drop policy if exists "write_insert_vitals" on vitals;
drop policy if exists "write_insert_medications_log" on medications_log;
drop policy if exists "write_insert_suppository_log" on suppository_log;
drop policy if exists "write_update_action_log" on action_log;
drop policy if exists "write_update_vitals" on vitals;
drop policy if exists "write_update_medications_log" on medications_log;
drop policy if exists "write_update_suppository_log" on suppository_log;
drop policy if exists "write_delete_action_log" on action_log;
drop policy if exists "write_delete_vitals" on vitals;
drop policy if exists "write_delete_medications_log" on medications_log;
drop policy if exists "write_delete_suppository_log" on suppository_log;
drop policy if exists "admin_insert_action_log" on action_log;
drop policy if exists "admin_insert_vitals" on vitals;
drop policy if exists "admin_insert_medications_log" on medications_log;
drop policy if exists "admin_insert_suppository_log" on suppository_log;
drop policy if exists "admin_update_action_log" on action_log;
drop policy if exists "admin_update_vitals" on vitals;
drop policy if exists "admin_update_medications_log" on medications_log;
drop policy if exists "admin_update_suppository_log" on suppository_log;
drop policy if exists "admin_delete_action_log" on action_log;
drop policy if exists "admin_delete_vitals" on vitals;
drop policy if exists "admin_delete_medications_log" on medications_log;
drop policy if exists "admin_delete_suppository_log" on suppository_log;
drop policy if exists "authenticated_select_app_roles" on app_roles;
drop policy if exists "admin_manage_app_roles" on app_roles;

-- everyone signed in can READ (viewers included)
create policy "authenticated_select_action_log"     on action_log     for select to authenticated using (true);
create policy "authenticated_select_vitals"         on vitals         for select to authenticated using (true);
create policy "authenticated_select_medications_log" on medications_log for select to authenticated using (true);
create policy "authenticated_select_suppository_log" on suppository_log for select to authenticated using (true);

-- only admin + recorder can WRITE (viewers cannot)
create policy "write_insert_action_log"     on action_log     for insert to authenticated with check (can_write());
create policy "write_insert_vitals"         on vitals         for insert to authenticated with check (can_write());
create policy "write_insert_medications_log" on medications_log for insert to authenticated with check (can_write());
create policy "write_insert_suppository_log" on suppository_log for insert to authenticated with check (can_write());

create policy "write_update_action_log"     on action_log     for update to authenticated using (can_write()) with check (can_write());
create policy "write_update_vitals"         on vitals         for update to authenticated using (can_write()) with check (can_write());
create policy "write_update_medications_log" on medications_log for update to authenticated using (can_write()) with check (can_write());
create policy "write_update_suppository_log" on suppository_log for update to authenticated using (can_write()) with check (can_write());

create policy "write_delete_action_log"     on action_log     for delete to authenticated using (can_write());
create policy "write_delete_vitals"         on vitals         for delete to authenticated using (can_write());
create policy "write_delete_medications_log" on medications_log for delete to authenticated using (can_write());
create policy "write_delete_suppository_log" on suppository_log for delete to authenticated using (can_write());

-- roles table: everyone can read their role; only admin can change roles
create policy "authenticated_select_app_roles" on app_roles for select to authenticated using (true);
create policy "admin_manage_app_roles" on app_roles for all to authenticated
  using (current_user_role() = 'admin') with check (current_user_role() = 'admin');

-- ============================================================
-- Live shared UI state (real-time collaborative)
-- Mirrors the app's local state (meds checkmarks, feeding steps,
-- notes, supplies, feed time, ...) so every device sees changes
-- instantly. Key/value; last write wins.
-- ============================================================
create table if not exists app_state (
  k text primary key,
  v jsonb,
  updated_at timestamptz default now(),
  client_id text
);

alter table app_state enable row level security;
drop policy if exists "authenticated_select_app_state" on app_state;
drop policy if exists "write_insert_app_state" on app_state;
drop policy if exists "write_update_app_state" on app_state;
drop policy if exists "write_delete_app_state" on app_state;
create policy "authenticated_select_app_state" on app_state for select to authenticated using (true);
create policy "write_insert_app_state" on app_state for insert to authenticated with check (can_write());
create policy "write_update_app_state" on app_state for update to authenticated using (can_write()) with check (can_write());
create policy "write_delete_app_state" on app_state for delete to authenticated using (can_write());

-- ---- Enable Realtime for the tables the app subscribes to ----
do $$ begin alter publication supabase_realtime add table app_state;  exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table action_log; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table vitals;     exception when others then null; end $$;
