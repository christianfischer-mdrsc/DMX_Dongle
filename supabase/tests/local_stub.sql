-- Minimaler Nachbau der Supabase-Umgebung für lokale Tests mit einem
-- normalen Postgres. NICHT in Supabase ausführen.
create schema if not exists auth;
create schema if not exists extensions;

do $$ begin
  create role anon nologin;          exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role nologin;  exception when duplicate_object then null; end $$;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb default '{}',
  email_confirmed_at timestamptz,
  last_sign_in_at    timestamptz,
  created_at         timestamptz default now()
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth, public, extensions to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
-- Supabase vergibt diese Tabellenrechte standardmäßig, RLS schützt.
alter default privileges in schema public grant all on tables to anon, authenticated;
