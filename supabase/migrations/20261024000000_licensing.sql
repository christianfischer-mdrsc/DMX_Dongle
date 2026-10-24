-- =====================================================================
-- DMX Control – Konten & Freischaltung
--
-- Einspielen: Supabase Dashboard → SQL Editor → diesen Inhalt ausführen
-- (oder mit der Supabase CLI: supabase db push).
--
-- Prinzip
--   * Login/Registrierung macht Supabase Auth (auth.users).
--   * Die App darf nur LESEN, welche Pakete ihr Konto besitzt.
--   * Codes sind für die App unsichtbar. Eingelöst wird ausschließlich
--     über die Funktion redeem_code(), die serverseitig prüft.
--   * Codes erzeugst du im SQL Editor mit admin_create_codes().
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------

-- Freischaltbare Pakete (IDs müssen zu `requires:` in der App passen)
create table if not exists public.packs (
  id          text primary key,
  name        text not null,
  description text not null default '',
  created_at  timestamptz not null default now()
);

-- Freischaltcodes. Gespeichert normalisiert: Großbuchstaben, ohne Bindestriche.
create table if not exists public.unlock_codes (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique check (code ~ '^[A-Z0-9]{8,32}$'),
  pack_ids         text[] not null check (cardinality(pack_ids) > 0),
  max_redemptions  integer not null default 1 check (max_redemptions > 0),
  redemption_count integer not null default 0 check (redemption_count >= 0),
  expires_at       timestamptz,
  active           boolean not null default true,
  note             text,
  created_at       timestamptz not null default now()
);

-- Wer hat welchen Code wann eingelöst (ein Konto pro Code höchstens einmal)
create table if not exists public.code_redemptions (
  id          bigint generated always as identity primary key,
  code_id     uuid not null references public.unlock_codes(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  unique (code_id, user_id)
);

-- Was ein Konto besitzt – das liest die App
create table if not exists public.entitlements (
  user_id    uuid not null references auth.users(id) on delete cascade,
  pack_id    text not null references public.packs(id) on delete cascade,
  code_id    uuid references public.unlock_codes(id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (user_id, pack_id)
);

-- Fehlversuche fürs Bremsen von Code-Raten
create table if not exists public.redeem_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index if not exists redeem_attempts_user_time
  on public.redeem_attempts (user_id, attempted_at);

-- ---------------------------------------------------------------------
-- Zugriffsrechte (Row Level Security)
-- ---------------------------------------------------------------------

alter table public.packs            enable row level security;
alter table public.unlock_codes     enable row level security;
alter table public.code_redemptions enable row level security;
alter table public.entitlements     enable row level security;
alter table public.redeem_attempts  enable row level security;

-- Pakete darf jeder sehen (Namen/Beschreibung für die App)
drop policy if exists "packs lesbar" on public.packs;
create policy "packs lesbar" on public.packs
  for select to anon, authenticated using (true);

-- Eigene Freischaltungen lesen – nichts schreiben
drop policy if exists "eigene entitlements lesen" on public.entitlements;
create policy "eigene entitlements lesen" on public.entitlements
  for select to authenticated using (user_id = (select auth.uid()));

-- unlock_codes, code_redemptions, redeem_attempts: KEINE Policies
-- → für App-Nutzer komplett unsichtbar.

revoke all on public.unlock_codes, public.code_redemptions, public.redeem_attempts
  from anon, authenticated;
revoke insert, update, delete on public.entitlements, public.packs
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- redeem_code: Code einlösen
--
-- Rückgabe (jsonb):
--   {"status":"ok","added":["pack.pro"]}
--   {"status":"invalid"}            Code unbekannt oder deaktiviert
--   {"status":"expired"}
--   {"status":"used_up"}            maximale Einlösungen erreicht
--   {"status":"already_redeemed"}   dieses Konto hat den Code schon
--   {"status":"already_owned"}      Konto besitzt alle Pakete schon
--   {"status":"too_many_attempts"}  zu viele Fehlversuche (1 h Sperre)
--
-- Bewusst kein RAISE bei Fehlern: sonst würde der Fehlversuch-Zähler
-- mit zurückgerollt.
-- ---------------------------------------------------------------------

create or replace function public.redeem_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_norm     text;
  v_code     public.unlock_codes%rowtype;
  v_missing  text[];
  v_max_fail constant integer := 10;
begin
  if v_uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;

  if (select count(*) from public.redeem_attempts
      where user_id = v_uid and attempted_at > now() - interval '1 hour') >= v_max_fail then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;

  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  -- Zeile sperren: gleichzeitige Einlösungen zählen korrekt
  select * into v_code from public.unlock_codes where code = v_norm for update;

  if not found or not v_code.active then
    insert into public.redeem_attempts (user_id) values (v_uid);
    return jsonb_build_object('status', 'invalid');
  end if;

  if v_code.expires_at is not null and v_code.expires_at < now() then
    return jsonb_build_object('status', 'expired');
  end if;

  if exists (select 1 from public.code_redemptions
             where code_id = v_code.id and user_id = v_uid) then
    return jsonb_build_object('status', 'already_redeemed');
  end if;

  if v_code.redemption_count >= v_code.max_redemptions then
    return jsonb_build_object('status', 'used_up');
  end if;

  select coalesce(array_agg(p), '{}') into v_missing
  from unnest(v_code.pack_ids) as p
  where not exists (select 1 from public.entitlements e
                    where e.user_id = v_uid and e.pack_id = p);

  -- Nichts Neues dabei → Code nicht verbrauchen
  if cardinality(v_missing) = 0 then
    return jsonb_build_object('status', 'already_owned');
  end if;

  insert into public.code_redemptions (code_id, user_id) values (v_code.id, v_uid);
  update public.unlock_codes set redemption_count = redemption_count + 1 where id = v_code.id;
  insert into public.entitlements (user_id, pack_id, code_id)
    select v_uid, p, v_code.id from unnest(v_missing) as p
  on conflict do nothing;

  return jsonb_build_object('status', 'ok', 'added', to_jsonb(v_missing));
end;
$$;

revoke all on function public.redeem_code(text) from public, anon;
grant execute on function public.redeem_code(text) to authenticated;

-- ---------------------------------------------------------------------
-- delete_my_account: Konto samt allen Daten löschen
-- (Pflicht für den Play Store, wenn die App Konten anbietet)
-- ---------------------------------------------------------------------

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------
-- admin_create_codes: Codes erzeugen (nur im SQL Editor / mit Service-Key)
--
-- Beispiele:
--   select * from admin_create_codes(array['pack.pro'], 20);
--     → 20 Einmal-Codes für Pro-Geräte
--   select * from admin_create_codes(array['pack.pro'], 1, 100,
--                                    now() + interval '30 days', 'Messe 2026');
--     → 1 Code, 100× einlösbar, 30 Tage gültig
-- ---------------------------------------------------------------------

create or replace function public.admin_create_codes(
  p_pack_ids        text[],
  p_count           integer default 1,
  p_max_redemptions integer default 1,
  p_expires_at      timestamptz default null,
  p_note            text default null
)
returns table (code text, max_redemptions integer, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- ohne 0/O, 1/I/L: gut abzutippen
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_raw   text;
  v_bytes bytea;
  i int;
  j int;
begin
  if p_count < 1 or p_count > 10000 then
    raise exception 'p_count muss zwischen 1 und 10000 liegen';
  end if;
  if exists (select 1 from unnest(p_pack_ids) p
             where not exists (select 1 from public.packs where id = p)) then
    raise exception 'Unbekanntes Paket in %', p_pack_ids;
  end if;

  for i in 1..p_count loop
    loop
      v_bytes := extensions.gen_random_bytes(12);
      v_raw := '';
      for j in 0..11 loop
        v_raw := v_raw || substr(v_alpha, (get_byte(v_bytes, j) % length(v_alpha)) + 1, 1);
      end loop;
      begin
        insert into public.unlock_codes (code, pack_ids, max_redemptions, expires_at, note)
        values (v_raw, p_pack_ids, p_max_redemptions, p_expires_at, p_note);
        exit;
      exception when unique_violation then
        -- extrem unwahrscheinlich, einfach neu würfeln
      end;
    end loop;

    code := substr(v_raw, 1, 4) || '-' || substr(v_raw, 5, 4) || '-' || substr(v_raw, 9, 4);
    max_redemptions := p_max_redemptions;
    expires_at := p_expires_at;
    return next;
  end loop;
end;
$$;

revoke all on function public.admin_create_codes(text[], integer, integer, timestamptz, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Übersicht für dich im Dashboard (Table Editor → code_overview)
-- ---------------------------------------------------------------------

create or replace view public.code_overview
with (security_invoker = true) as
select
  substr(c.code, 1, 4) || '-' || substr(c.code, 5, 4) || '-' || substr(c.code, 9) as code,
  c.pack_ids,
  c.redemption_count || ' / ' || c.max_redemptions as eingeloest,
  c.expires_at,
  c.active,
  c.note,
  c.created_at
from public.unlock_codes c
order by c.created_at desc;

revoke all on public.code_overview from anon, authenticated;

-- ---------------------------------------------------------------------
-- Startdaten
-- ---------------------------------------------------------------------

insert into public.packs (id, name, description) values
  ('pack.pro', 'Pro-Geräte',
   'LED-Bars mit Einzelsegmenten und Moving Heads mit 16-Bit-Positionierung.')
on conflict (id) do update
  set name = excluded.name, description = excluded.description;
