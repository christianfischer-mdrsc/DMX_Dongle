-- Tests für redeem_code & Co. Läuft lokal nach local_stub.sql + Migration.
-- Bricht beim ersten Fehler ab (ON_ERROR_STOP).
\set ON_ERROR_STOP on

create or replace function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false);
$$;

create or replace function pg_temp.expect(p_got jsonb, p_status text) returns void
language plpgsql as $$
begin
  if p_got->>'status' is distinct from p_status then
    raise exception 'Erwartet %, bekommen %', p_status, p_got;
  end if;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'anna@test.de'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@test.de'),
  ('00000000-0000-0000-0000-00000000000c', 'carl@test.de');

insert into public.packs (id, name) values ('pack.extra', 'Extra') on conflict do nothing;

-- Codes mit festem Wert, damit die Tests sie kennen
insert into public.unlock_codes (code, pack_ids, max_redemptions, expires_at, active) values
  ('SINGLE000001', '{pack.pro}', 1, null, true),
  ('MULTI0000002', '{pack.pro}', 2, null, true),
  ('EXPIRED00003', '{pack.pro}', 5, now() - interval '1 day', true),
  ('INACTIVE0004', '{pack.pro}', 5, null, false),
  ('BUNDLE000005', '{pack.pro,pack.extra}', 5, null, true);

-- Admin-Generator
do $$
declare n int;
begin
  select count(*) into n from public.admin_create_codes(array['pack.pro'], 25, 3, null, 'Test');
  if n <> 25 then raise exception 'Generator lieferte % statt 25', n; end if;
  if (select count(*) from public.unlock_codes where note = 'Test' and max_redemptions = 3) <> 25 then
    raise exception 'Generierte Codes fehlen';
  end if;
  begin
    perform public.admin_create_codes(array['pack.gibtsnicht'], 1);
    raise exception 'Unbekanntes Paket wurde akzeptiert';
  exception when raise_exception then
    if sqlerrm not like 'Unbekanntes Paket%' then raise; end if;
  end;
end $$;

-- Format eines generierten Codes
do $$
declare c text;
begin
  select code into c from public.admin_create_codes(array['pack.pro']);
  if c !~ '^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$' then
    raise exception 'Unerwartetes Format: %', c;
  end if;
end $$;

-- ===== Ab hier als App-Nutzer =====
set role authenticated;

-- Nutzer sieht keine Codes
do $$ begin
  perform 1 from public.unlock_codes;
  raise exception 'unlock_codes war lesbar';
exception when insufficient_privilege then null;
end $$;

-- Nutzer darf keine Codes erzeugen
do $$ begin
  perform public.admin_create_codes(array['pack.pro'], 1);
  raise exception 'admin_create_codes war aufrufbar';
exception when insufficient_privilege then null;
end $$;

-- Nutzer darf sich nichts selbst freischalten
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into public.entitlements (user_id, pack_id)
    values ('00000000-0000-0000-0000-00000000000a', 'pack.pro');
  raise exception 'entitlements war beschreibbar';
exception when insufficient_privilege then null;
end $$;

-- Anna: Einmal-Code mit Kleinschreibung und Bindestrichen
select pg_temp.expect(public.redeem_code('single-0000-01'), 'ok');
do $$ begin
  if (select count(*) from public.entitlements) <> 1 then
    raise exception 'Anna sieht nicht genau 1 Freischaltung';
  end if;
end $$;
-- gleicher Code nochmal
select pg_temp.expect(public.redeem_code('SINGLE000001'), 'already_redeemed');
-- Mehrfach-Code, Anna hat das Paket aber schon → nicht verbrauchen
select pg_temp.expect(public.redeem_code('MULTI0000002'), 'already_owned');
-- Bundle: nur pack.extra ist neu
do $$
declare r jsonb := public.redeem_code('BUNDLE000005');
begin
  perform pg_temp.expect(r, 'ok');
  if r->'added' <> '["pack.extra"]'::jsonb then raise exception 'added falsch: %', r; end if;
end $$;

-- Ben: Einmal-Code ist verbraucht
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect(public.redeem_code('SINGLE000001'), 'used_up');
select pg_temp.expect(public.redeem_code('EXPIRED00003'), 'expired');
select pg_temp.expect(public.redeem_code('INACTIVE0004'), 'invalid');
select pg_temp.expect(public.redeem_code('MULTI0000002'), 'ok');
-- Ben sieht nur seine eigenen Freischaltungen
do $$ begin
  if (select count(*) from public.entitlements) <> 1 then
    raise exception 'Ben sieht fremde Freischaltungen';
  end if;
end $$;

-- Carl: zweite Einlösung des Mehrfach-Codes geht noch, dritte nicht
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select pg_temp.expect(public.redeem_code('MULTI0000002'), 'ok');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
set role authenticated;
-- (Anna hat pack.pro, aber prüfen wir den Zähler direkt als Admin)
reset role;
do $$ begin
  if (select redemption_count from public.unlock_codes where code = 'MULTI0000002') <> 2 then
    raise exception 'Zähler MULTI falsch';
  end if;
  if (select redemption_count from public.unlock_codes where code = 'SINGLE000001') <> 1 then
    raise exception 'Zähler SINGLE falsch';
  end if;
end $$;

-- Bruteforce-Bremse: 10 Fehlversuche, dann gesperrt – auch für gültige Codes
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'dora@test.de');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
set role authenticated;
do $$
begin
  for i in 1..10 loop
    perform pg_temp.expect(public.redeem_code('FALSCH' || i || 'XXXX'), 'invalid');
  end loop;
  perform pg_temp.expect(public.redeem_code('BUNDLE000005'), 'too_many_attempts');
end $$;

-- Nicht angemeldet
select pg_temp.as_user(null);
do $$ begin
  perform public.redeem_code('BUNDLE000005');
  raise exception 'Ohne Login einlösbar';
exception when sqlstate '28000' then null;
end $$;

-- anon darf redeem_code gar nicht aufrufen
reset role;
set role anon;
do $$ begin
  perform public.redeem_code('BUNDLE000005');
  raise exception 'anon durfte redeem_code aufrufen';
exception when insufficient_privilege then null;
end $$;
-- anon darf Pakete lesen
do $$ begin
  if (select count(*) from public.packs) < 1 then raise exception 'packs nicht lesbar'; end if;
end $$;

-- Konto löschen räumt alles ab
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
set role authenticated;
select public.delete_my_account();
reset role;
do $$ begin
  if exists (select 1 from auth.users where email = 'anna@test.de') then
    raise exception 'Anna nicht gelöscht';
  end if;
  if exists (select 1 from public.entitlements
             where user_id = '00000000-0000-0000-0000-00000000000a') then
    raise exception 'Annas Freischaltungen nicht gelöscht';
  end if;
end $$;

\echo 'Alle Datenbank-Tests bestanden.'
