-- =====================================================================
-- DMX Control – Admin-Bereich
--
-- Admins sind Konten in public.admins. Jede admin_*-Funktion prüft das
-- selbst auf dem Server; die App kann sich Admin-Rechte nicht geben.
--
-- Ersten Admin anlegen (SQL Editor, E-Mail anpassen):
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'du@example.com';
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------

create table if not exists public.admins (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now(),
  added_by uuid references auth.users(id) on delete set null
);

-- Einstellungen, die die App lesen darf (z. B. Hinweis an alle)
create table if not exists public.app_settings (
  key        text primary key check (key in ('announcement', 'support_email')),
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

-- Wer hat wann was im Admin-Bereich geändert
create table if not exists public.admin_log (
  id       bigint generated always as identity primary key,
  at       timestamptz not null default now(),
  admin_id uuid references auth.users(id) on delete set null,
  action   text not null,
  detail   jsonb not null default '{}'
);
create index if not exists admin_log_at on public.admin_log (at desc);

alter table public.admins       enable row level security;
alter table public.app_settings enable row level security;
alter table public.admin_log    enable row level security;

drop policy if exists "einstellungen lesbar" on public.app_settings;
create policy "einstellungen lesbar" on public.app_settings
  for select to anon, authenticated using (true);

revoke all on public.admins, public.admin_log from anon, authenticated;
revoke insert, update, delete on public.app_settings from anon, authenticated;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Bricht ab, wenn der Aufrufer kein Admin ist. Nur intern genutzt.
create or replace function public._require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'Keine Admin-Rechte' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

revoke all on function public._require_admin() from public, anon, authenticated;

create or replace function public._admin_log(p_action text, p_detail jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.admin_log (admin_id, action, detail) values (auth.uid(), p_action, p_detail);
$$;

revoke all on function public._admin_log(text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Übersicht
-- ---------------------------------------------------------------------

create or replace function public.admin_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  return jsonb_build_object(
    'users',           (select count(*) from auth.users),
    'users_confirmed', (select count(*) from auth.users where email_confirmed_at is not null),
    'users_7d',        (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'codes',           (select count(*) from public.unlock_codes),
    'codes_open',      (select count(*) from public.unlock_codes
                        where active and redemption_count < max_redemptions
                          and (expires_at is null or expires_at > now())),
    'redemptions',     (select count(*) from public.code_redemptions),
    'redemptions_7d',  (select count(*) from public.code_redemptions where redeemed_at > now() - interval '7 days'),
    'packs', coalesce((select jsonb_agg(jsonb_build_object(
                'id', p.id, 'name', p.name,
                'owners', (select count(*) from public.entitlements e where e.pack_id = p.id))
              order by p.id) from public.packs p), '[]')
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Codes
-- ---------------------------------------------------------------------

create or replace function public.admin_list_codes(p_search text default null, p_limit integer default 200)
returns table (
  id uuid, code text, pack_ids text[], max_redemptions integer, redemption_count integer,
  expires_at timestamptz, active boolean, note text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := upper(regexp_replace(coalesce(p_search, ''), '[^A-Za-z0-9]', '', 'g'));
  v_note text := lower(coalesce(trim(p_search), ''));
begin
  perform public._require_admin();
  return query
    select c.id,
           substr(c.code, 1, 4) || '-' || substr(c.code, 5, 4) || '-' || substr(c.code, 9),
           c.pack_ids, c.max_redemptions, c.redemption_count, c.expires_at, c.active, c.note, c.created_at
    from public.unlock_codes c
    where v_note = ''
       or c.code like '%' || v_q || '%' and v_q <> ''
       or lower(coalesce(c.note, '')) like '%' || v_note || '%'
    order by c.created_at desc
    limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end;
$$;

create or replace function public.admin_generate_codes(
  p_pack_ids text[], p_count integer, p_max_redemptions integer default 1,
  p_expires_at timestamptz default null, p_note text default null
)
returns setof text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  if p_count < 1 or p_count > 500 then
    raise exception 'Bitte zwischen 1 und 500 Codes auf einmal erzeugen';
  end if;
  if p_max_redemptions < 1 then
    raise exception 'Einlösungen pro Code muss mindestens 1 sein';
  end if;
  perform public._admin_log('codes_erzeugt', jsonb_build_object(
    'pakete', p_pack_ids, 'anzahl', p_count, 'einloesungen', p_max_redemptions,
    'gueltig_bis', p_expires_at, 'notiz', p_note));
  return query
    select g.code from public.admin_create_codes(p_pack_ids, p_count, p_max_redemptions, p_expires_at, p_note) g;
end;
$$;

create or replace function public.admin_set_code_active(p_code_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_code text;
begin
  perform public._require_admin();
  update public.unlock_codes set active = p_active where id = p_code_id returning code into v_code;
  if v_code is null then raise exception 'Code nicht gefunden'; end if;
  perform public._admin_log(case when p_active then 'code_aktiviert' else 'code_gesperrt' end,
                            jsonb_build_object('code', v_code));
end;
$$;

create or replace function public.admin_code_redemptions(p_code_id uuid)
returns table (user_id uuid, email text, redeemed_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  return query
    select r.user_id, u.email::text, r.redeemed_at
    from public.code_redemptions r join auth.users u on u.id = r.user_id
    where r.code_id = p_code_id
    order by r.redeemed_at desc;
end;
$$;

-- ---------------------------------------------------------------------
-- Nutzer
-- ---------------------------------------------------------------------

create or replace function public.admin_list_users(p_search text default null, p_limit integer default 200)
returns table (
  id uuid, email text, display_name text, created_at timestamptz, confirmed boolean,
  last_sign_in_at timestamptz, packs text[], is_admin boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_q text := lower(coalesce(trim(p_search), ''));
begin
  perform public._require_admin();
  return query
    select u.id, u.email::text, coalesce(u.raw_user_meta_data->>'display_name', ''),
           u.created_at, u.email_confirmed_at is not null, u.last_sign_in_at,
           coalesce((select array_agg(e.pack_id order by e.pack_id) from public.entitlements e
                     where e.user_id = u.id), '{}'),
           exists (select 1 from public.admins a where a.user_id = u.id)
    from auth.users u
    where v_q = '' or lower(u.email) like '%' || v_q || '%'
       or lower(coalesce(u.raw_user_meta_data->>'display_name', '')) like '%' || v_q || '%'
    order by u.created_at desc
    limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end;
$$;

create or replace function public.admin_set_entitlement(p_user_id uuid, p_pack_id text, p_granted boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_email text;
begin
  perform public._require_admin();
  select email into v_email from auth.users where id = p_user_id;
  if v_email is null then raise exception 'Nutzer nicht gefunden'; end if;
  if not exists (select 1 from public.packs where id = p_pack_id) then
    raise exception 'Paket % gibt es nicht', p_pack_id;
  end if;
  if p_granted then
    insert into public.entitlements (user_id, pack_id) values (p_user_id, p_pack_id)
    on conflict do nothing;
  else
    delete from public.entitlements where user_id = p_user_id and pack_id = p_pack_id;
  end if;
  perform public._admin_log(case when p_granted then 'paket_vergeben' else 'paket_entzogen' end,
                            jsonb_build_object('nutzer', v_email, 'paket', p_pack_id));
end;
$$;

create or replace function public.admin_set_admin(p_user_id uuid, p_admin boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public._require_admin(); v_email text;
begin
  select email into v_email from auth.users where id = p_user_id;
  if v_email is null then raise exception 'Nutzer nicht gefunden'; end if;
  if p_admin then
    insert into public.admins (user_id, added_by) values (p_user_id, v_me) on conflict do nothing;
  else
    if p_user_id = v_me then
      raise exception 'Du kannst dir die Admin-Rechte nicht selbst entziehen';
    end if;
    delete from public.admins where user_id = p_user_id;
  end if;
  perform public._admin_log(case when p_admin then 'admin_ernannt' else 'admin_entzogen' end,
                            jsonb_build_object('nutzer', v_email));
end;
$$;

-- ---------------------------------------------------------------------
-- Pakete
-- ---------------------------------------------------------------------

create or replace function public.admin_update_pack(p_id text, p_name text, p_description text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  if coalesce(trim(p_name), '') = '' then raise exception 'Name darf nicht leer sein'; end if;
  update public.packs set name = trim(p_name), description = coalesce(trim(p_description), '')
  where id = p_id;
  if not found then raise exception 'Paket % gibt es nicht', p_id; end if;
  perform public._admin_log('paket_geaendert', jsonb_build_object('paket', p_id, 'name', p_name));
end;
$$;

-- ---------------------------------------------------------------------
-- App-Einstellungen
-- ---------------------------------------------------------------------

create or replace function public.admin_set_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  if p_value is null or p_value = 'null'::jsonb then
    delete from public.app_settings where key = p_key;
  else
    insert into public.app_settings (key, value, updated_at, updated_by)
    values (p_key, p_value, now(), auth.uid())
    on conflict (key) do update
      set value = excluded.value, updated_at = now(), updated_by = auth.uid();
  end if;
  perform public._admin_log('einstellung_geaendert', jsonb_build_object('key', p_key, 'wert', p_value));
end;
$$;

-- ---------------------------------------------------------------------
-- Protokoll
-- ---------------------------------------------------------------------

create or replace function public.admin_list_log(p_limit integer default 100)
returns table (at timestamptz, admin_email text, action text, detail jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  return query
    select l.at, u.email::text, l.action, l.detail
    from public.admin_log l left join auth.users u on u.id = l.admin_id
    order by l.at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

-- ---------------------------------------------------------------------
-- Rechte: Admin-Funktionen nur für angemeldete Nutzer aufrufbar,
-- die Admin-Prüfung steckt in jeder Funktion selbst.
-- ---------------------------------------------------------------------

do $$
declare f text;
begin
  foreach f in array array[
    'public.admin_stats()',
    'public.admin_list_codes(text, integer)',
    'public.admin_generate_codes(text[], integer, integer, timestamptz, text)',
    'public.admin_set_code_active(uuid, boolean)',
    'public.admin_code_redemptions(uuid)',
    'public.admin_list_users(text, integer)',
    'public.admin_set_entitlement(uuid, text, boolean)',
    'public.admin_set_admin(uuid, boolean)',
    'public.admin_update_pack(text, text, text)',
    'public.admin_set_setting(text, jsonb)',
    'public.admin_list_log(integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
