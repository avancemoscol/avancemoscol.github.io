-- Migración 0010: Lectura de media de publicaciones aprobadas
-- La media se sube a 'media-pendiente' (privado). Cuando la publicación queda aprobada
-- sus archivos deben poder verse según la visibilidad de la publicación, sin depender
-- de que una Edge Function los mueva de bucket. La verificación se hace en una función
-- security definer porque visitantes anónimos no pueden leer publicaciones por RLS.

create or replace function public.media_publicacion_visible(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.publicacion_media pm
    join public.publicaciones p on p.id = pm.publicacion_id
    where pm.bucket = 'media-pendiente'
      and pm.path = p_path
      and p.estado = 'aprobado'
      and p.eliminado_en is null
      and (p.visibilidad = 'publica' or public.es_miembro_activo())
  );
$$;
grant execute on function public.media_publicacion_visible(text) to anon, authenticated;

drop policy if exists "leer_media_aprobada" on storage.objects;
create policy "leer_media_aprobada" on storage.objects
  for select using (
    bucket_id = 'media-pendiente' and public.media_publicacion_visible(name)
  );

-- es_participante se evalúa dentro de otras políticas (p. ej. storage 'leer_media_mensajes')
-- también para visitantes; para anon siempre devuelve false porque auth.uid() es null.
grant execute on function public.es_participante(uuid) to anon;
