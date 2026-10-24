-- Tests für den Admin-Bereich. Läuft nach local_stub.sql + allen Migrationen.
\set ON_ERROR_STOP on

create or replace function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false);
$$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-00000000000a', 'admin@test.de', '{"display_name":"Ada"}'),
  ('10000000-0000-0000-0000-00000000000b', 'kunde@test.de', '{}');

insert into public.admins (user_id) values ('10000000-0000-0000-0000-00000000000a');

set role authenticated;

-- Kunde: kein Admin, alle Admin-Funktionen gesperrt
select pg_temp.as_user('10000000-0000-0000-0000-00000000000b');
do $$ begin
  if public.is_admin() then raise exception 'Kunde gilt als Admin'; end if;
  begin
    perform public.admin_stats();
    raise exception 'admin_stats ohne Rechte';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_generate_codes(array['pack.pro'], 1);
    raise exception 'admin_generate_codes ohne Rechte';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_set_admin('10000000-0000-0000-0000-00000000000b', true);
    raise exception 'Kunde konnte sich zum Admin machen';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.admins (user_id) values ('10000000-0000-0000-0000-00000000000b');
    raise exception 'admins direkt beschreibbar';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.app_settings (key, value) values ('announcement', '"x"');
    raise exception 'app_settings direkt beschreibbar';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Admin
select pg_temp.as_user('10000000-0000-0000-0000-00000000000a');
do $$
declare
  c text; cid uuid; s jsonb; n int;
begin
  if not public.is_admin() then raise exception 'Admin nicht erkannt'; end if;

  select count(*) into n from public.admin_generate_codes(array['pack.pro'], 3, 2, null, 'Messe');
  if n <> 3 then raise exception 'generate lieferte %', n; end if;

  select code, id into c, cid from public.admin_list_codes('messe') limit 1;
  if c is null then raise exception 'Suche nach Notiz findet nichts'; end if;
  if (select count(*) from public.admin_list_codes(c)) <> 1 then
    raise exception 'Suche nach Code % findet nicht genau einen', c;
  end if;

  perform public.admin_set_code_active(cid, false);
  if (select active from public.admin_list_codes(c)) then raise exception 'Code nicht gesperrt'; end if;
  perform public.admin_set_code_active(cid, true);

  perform public.admin_set_entitlement('10000000-0000-0000-0000-00000000000b', 'pack.pro', true);
  if (select packs from public.admin_list_users('kunde')) <> '{pack.pro}' then
    raise exception 'Paket nicht vergeben';
  end if;
  perform public.admin_set_entitlement('10000000-0000-0000-0000-00000000000b', 'pack.pro', false);
  if (select cardinality(packs) from public.admin_list_users('kunde')) <> 0 then
    raise exception 'Paket nicht entzogen';
  end if;
  begin
    perform public.admin_set_entitlement('10000000-0000-0000-0000-00000000000b', 'pack.gibtsnicht', true);
    raise exception 'unbekanntes Paket vergeben';
  exception when raise_exception then
    if sqlerrm not like 'Paket%' then raise; end if;
  end;

  if (select display_name from public.admin_list_users('ada')) <> 'Ada' then
    raise exception 'Suche nach Name';
  end if;

  begin
    perform public.admin_set_admin('10000000-0000-0000-0000-00000000000a', false);
    raise exception 'Admin konnte sich selbst entziehen';
  exception when raise_exception then
    if sqlerrm not like 'Du kannst%' then raise; end if;
  end;
  perform public.admin_set_admin('10000000-0000-0000-0000-00000000000b', true);
  if not (select is_admin from public.admin_list_users('kunde')) then raise exception 'Ernennen'; end if;
  perform public.admin_set_admin('10000000-0000-0000-0000-00000000000b', false);

  perform public.admin_set_setting('announcement', '{"text":"Wartung am Sonntag"}');
  if (select value->>'text' from public.app_settings where key = 'announcement') <> 'Wartung am Sonntag' then
    raise exception 'Hinweis nicht gespeichert';
  end if;
  begin
    perform public.admin_set_setting('beliebig', '"x"');
    raise exception 'unbekannter Schlüssel gespeichert';
  exception when check_violation then null;
  end;

  perform public.admin_update_pack('pack.pro', 'Profi-Paket', 'Neu');
  if (select name from public.packs where id = 'pack.pro') <> 'Profi-Paket' then raise exception 'Paket umbenennen'; end if;

  s := public.admin_stats();
  if (s->>'codes')::int < 3 or jsonb_array_length(s->'packs') < 1 then raise exception 'Statistik: %', s; end if;

  select count(*) into n from public.admin_list_log(50);
  if n < 8 then raise exception 'Protokoll hat nur % Einträge', n; end if;
end $$;

-- Hinweis ist für alle lesbar, auch ohne Anmeldung
reset role;
set role anon;
do $$ begin
  if (select count(*) from public.app_settings) <> 1 then raise exception 'anon liest Einstellungen nicht'; end if;
  begin
    perform public.is_admin();
    raise exception 'anon darf is_admin aufrufen';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\echo 'Alle Admin-Tests bestanden.'
