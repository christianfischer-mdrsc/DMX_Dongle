-- =====================================================================
-- DMX Control – Firmware-Updates
--
-- Einspielen: nach *_licensing.sql und *_admin.sql, genauso über den
-- SQL Editor oder `supabase db push`.
--
-- Prinzip
--   * Admins (public.admins, siehe *_admin.sql) veröffentlichen Firmware aus
--     der App: Datei in den Storage-Bucket `firmware`, Eintrag in
--     firmware_releases.
--   * Alle anderen sehen nur veröffentlichte Einträge und laden die Datei
--     über die öffentliche URL des Buckets – auch ohne Konto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Firmware-Versionen
-- ---------------------------------------------------------------------

create table if not exists public.firmware_releases (
  id           bigint generated always as identity primary key,
  version      text not null unique check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  -- Zum Sortieren: 1.2.3 → 10203. Wird vor dem CHECK berechnet, darf bei
  -- ungültiger Version also nicht selbst abbrechen (dann greift der CHECK).
  version_code integer generated always as (
    coalesce(nullif(substring(split_part(version, '.', 1) from '^[0-9]{1,4}$'), '')::integer, 0) * 10000
    + coalesce(nullif(substring(split_part(version, '.', 2) from '^[0-9]{1,2}$'), '')::integer, 0) * 100
    + coalesce(nullif(substring(split_part(version, '.', 3) from '^[0-9]{1,2}$'), '')::integer, 0)
  ) stored,
  channel      text not null default 'stable' check (channel in ('stable', 'beta')),
  notes        text not null default '',
  storage_path text not null,                       -- Pfad im Bucket `firmware`
  size_bytes   integer not null check (size_bytes > 0 and size_bytes <= 4194304),
  md5          text not null check (md5 ~ '^[0-9a-f]{32}$'),
  published    boolean not null default false,
  created_by   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now()
);
create index if not exists firmware_releases_published
  on public.firmware_releases (published, channel, version_code desc);

alter table public.firmware_releases enable row level security;

-- anon darf is_admin() nicht aufrufen, daher zwei getrennte Regeln
drop policy if exists "firmware lesen" on public.firmware_releases;
drop policy if exists "firmware lesen anon" on public.firmware_releases;
create policy "firmware lesen anon" on public.firmware_releases
  for select to anon
  using (published);

drop policy if exists "firmware lesen angemeldet" on public.firmware_releases;
create policy "firmware lesen angemeldet" on public.firmware_releases
  for select to authenticated
  using (published or (select public.is_admin()));

drop policy if exists "firmware anlegen" on public.firmware_releases;
create policy "firmware anlegen" on public.firmware_releases
  for insert to authenticated
  with check ((select public.is_admin()));

drop policy if exists "firmware ändern" on public.firmware_releases;
create policy "firmware ändern" on public.firmware_releases
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "firmware löschen" on public.firmware_releases;
create policy "firmware löschen" on public.firmware_releases
  for delete to authenticated
  using ((select public.is_admin()));

grant select on public.firmware_releases to anon, authenticated;
grant insert, update, delete on public.firmware_releases to authenticated;

-- ---------------------------------------------------------------------
-- Storage-Bucket `firmware` (öffentlich lesbar, nur Admins schreiben)
-- Nur in Supabase vorhanden; die lokalen Tests überspringen das.
-- ---------------------------------------------------------------------

do $outer$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage-Schema fehlt (lokaler Test) – Bucket übersprungen';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('firmware', 'firmware', true, 4194304, array['application/octet-stream'])
  on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  execute $p$drop policy if exists "firmware hochladen" on storage.objects$p$;
  execute $p$create policy "firmware hochladen" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'firmware' and (select public.is_admin()))$p$;

  execute $p$drop policy if exists "firmware überschreiben" on storage.objects$p$;
  execute $p$create policy "firmware überschreiben" on storage.objects
    for update to authenticated
    using (bucket_id = 'firmware' and (select public.is_admin()))$p$;

  execute $p$drop policy if exists "firmware entfernen" on storage.objects$p$;
  execute $p$create policy "firmware entfernen" on storage.objects
    for delete to authenticated
    using (bucket_id = 'firmware' and (select public.is_admin()))$p$;
end
$outer$;
