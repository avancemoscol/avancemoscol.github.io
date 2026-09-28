-- =============================================================================
-- Migración 0006: Configuración de Buckets de Storage y Políticas de Acceso
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Creación de Buckets
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatares', 'avatares', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('portadas', 'portadas', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('media-pendiente', 'media-pendiente', false, 52428800, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime']),
  ('media-publica', 'media-publica', true, 52428800, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime']),
  ('media-miembros', 'media-miembros', false, 52428800, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime']),
  ('mensajes', 'mensajes', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('ia-media', 'ia-media', true, 52428800, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']),
  ('sitio', 'sitio', true, 20971520, array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml', 'application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- -----------------------------------------------------------------------------
-- 2. Políticas de Seguridad de Storage (storage.objects)
-- -----------------------------------------------------------------------------
create policy "avatares_lectura_publica" on storage.objects
  for select using (bucket_id in ('avatares', 'portadas', 'media-publica', 'ia-media', 'sitio'));

create policy "subir_avatar_propio" on storage.objects
  for insert with check (
    bucket_id in ('avatares', 'portadas') and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "actualizar_avatar_propio" on storage.objects
  for update using (
    bucket_id in ('avatares', 'portadas') and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "eliminar_avatar_propio" on storage.objects
  for delete using (
    bucket_id in ('avatares', 'portadas') and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Media Pendiente
create policy "leer_media_pendiente" on storage.objects
  for select using (
    bucket_id = 'media-pendiente' and (
      (storage.foldername(name))[2] = (select auth.uid())::text
      or public.puede_moderar(nullif((storage.foldername(name))[1], 'nacional'))
    )
  );

create policy "subir_media_pendiente" on storage.objects
  for insert with check (
    bucket_id = 'media-pendiente' and
    (storage.foldername(name))[2] = (select auth.uid())::text
  );

-- Media Miembros (Solo miembros activos con cuenta aprobada)
create policy "leer_media_miembros" on storage.objects
  for select using (
    bucket_id = 'media-miembros' and (select public.es_miembro_activo())
  );

-- Mensajes Privados (Solo los participantes de la conversación)
create policy "leer_media_mensajes" on storage.objects
  for select using (
    bucket_id = 'mensajes' and exists (
      select 1 from public.conversacion_participantes cp
      where cp.conversacion_id = (storage.foldername(name))[1]::uuid
        and cp.user_id = (select auth.uid())
    )
  );

create policy "subir_media_mensajes" on storage.objects
  for insert with check (
    bucket_id = 'mensajes' and exists (
      select 1 from public.conversacion_participantes cp
      where cp.conversacion_id = (storage.foldername(name))[1]::uuid
        and cp.user_id = (select auth.uid())
    ) and (select public.puede_interactuar())
  );
