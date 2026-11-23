-- Tests für firmware_releases & is_admin(). Läuft lokal nach local_stub.sql,
-- allen Migrationen.
\set ON_ERROR_STOP on

create or replace function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'admin@test.de'),
  ('00000000-0000-0000-0000-0000000000f2', 'user@test.de');
insert into public.admins (user_id) values ('00000000-0000-0000-0000-0000000000f1');

-- Admin legt zwei Versionen an, eine davon veröffentlicht
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
set role authenticated;
do $$ begin
  if not public.is_admin() then raise exception 'Admin nicht erkannt'; end if;
end $$;
insert into public.firmware_releases (version, notes, storage_path, size_bytes, md5, published)
values ('1.1.0', 'OTA', '1.1.0/firmware.bin', 800000, repeat('a', 32), true),
       ('1.2.0', 'Test', '1.2.0/firmware.bin', 800000, repeat('b', 32), false);
do $$ begin
  if (select count(*) from public.firmware_releases) <> 2 then
    raise exception 'Admin sieht nicht alle Versionen';
  end if;
  if (select version_code from public.firmware_releases where version = '1.2.0') <> 10200 then
    raise exception 'version_code falsch';
  end if;
end $$;

-- Normaler Nutzer: nur Veröffentlichtes, nichts schreiben
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
set role authenticated;
do $$ begin
  if public.is_admin() then raise exception 'Nutzer gilt als Admin'; end if;
  if (select count(*) from public.firmware_releases) <> 1 then
    raise exception 'Nutzer sieht unveröffentlichte Version';
  end if;
end $$;
do $$ begin
  insert into public.firmware_releases (version, storage_path, size_bytes, md5)
  values ('9.9.9', 'x', 1, repeat('c', 32));
  raise exception 'Nutzer durfte Firmware anlegen';
exception when insufficient_privilege then null;
end $$;
update public.firmware_releases set published = true where version = '1.2.0';
delete from public.firmware_releases;
reset role;
do $$ begin
  if (select published from public.firmware_releases where version = '1.2.0') then
    raise exception 'Nutzer durfte veröffentlichen';
  end if;
  if (select count(*) from public.firmware_releases) <> 2 then
    raise exception 'Nutzer durfte löschen';
  end if;
end $$;

-- Anonym: nur Veröffentlichtes (ohne is_admin()-Aufruf), nichts schreiben
select pg_temp.as_user(null);
set role anon;
do $$ begin
  if (select count(*) from public.firmware_releases) <> 1 then
    raise exception 'anon sieht falsche Anzahl';
  end if;
end $$;
do $$ begin
  insert into public.firmware_releases (version, storage_path, size_bytes, md5)
  values ('8.8.8', 'x', 1, repeat('e', 32));
  raise exception 'anon durfte Firmware anlegen';
exception when insufficient_privilege then null;
end $$;
reset role;

-- Ungültige Versionsnummer
do $$ begin
  insert into public.firmware_releases (version, storage_path, size_bytes, md5)
  values ('1.2', 'x', 1, repeat('d', 32));
  raise exception 'Version 1.2 akzeptiert';
exception when check_violation then null;
end $$;

\echo 'Alle Firmware-Tests bestanden.'
