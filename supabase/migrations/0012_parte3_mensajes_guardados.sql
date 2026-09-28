-- =============================================================================
-- Migración 0012 (parte 3): vista previa y notificación de mensajes, guardados
-- =============================================================================

create or replace function public.tras_insertar_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.conversaciones
  set ultimo_mensaje_en = new.created_at,
      ultimo_mensaje_preview = left(new.contenido, 80)
  where id = new.conversacion_id;

  insert into public.notificaciones (user_id, tipo, actor_id, entidad, entidad_id, texto)
  select cp.user_id, 'mensaje', new.autor_id, 'conversacion', new.conversacion_id::text,
         'Te envió un mensaje: ' || left(new.contenido, 60)
  from public.conversacion_participantes cp
  where cp.conversacion_id = new.conversacion_id and cp.user_id <> new.autor_id;
  return new;
end;
$$;

drop trigger if exists trg_tras_insertar_mensaje on public.mensajes;
create trigger trg_tras_insertar_mensaje after insert on public.mensajes
  for each row execute function public.tras_insertar_mensaje();

-- Publicaciones guardadas por el usuario (todas, no solo las del feed reciente)
create or replace function public.mis_guardados()
returns table (
  id uuid, autor_id uuid, autor_nombre text, autor_username text, autor_avatar text, autor_insignia public.insignia,
  autor_cargo text, contenido text, categoria text, publicado_en timestamptz, es_oficial boolean,
  me_gusta_n integer, comentarios_n integer, le_gusta boolean, guardado boolean, media jsonb
) language sql stable security definer set search_path = '' as $$
  select p.id, p.autor_id, pf.primer_nombre, pf.username::text, pf.avatar_path, pf.insignia, pf.cargo_titulo,
         p.contenido, p.categoria, p.publicado_en, p.es_oficial, p.me_gusta_n, p.comentarios_n,
         exists (select 1 from public.me_gusta mg where mg.publicacion_id = p.id and mg.user_id = auth.uid()),
         true,
         coalesce((select jsonb_agg(jsonb_build_object('id', pm.id, 'tipo', pm.tipo, 'path', pm.path, 'bucket', pm.bucket, 'alt_text', pm.alt_text) order by pm.orden)
                   from public.publicacion_media pm where pm.publicacion_id = p.id), '[]'::jsonb)
  from public.guardados g
  join public.publicaciones p on p.id = g.publicacion_id
  join public.perfiles pf on pf.id = p.autor_id
  where g.user_id = auth.uid() and p.estado = 'aprobado' and p.eliminado_en is null
  order by g.created_at desc
  limit 100;
$$;
grant execute on function public.mis_guardados() to authenticated;

-- Correo oficial de contacto en el contenido del CMS
update public.paginas set contenido_md = replace(replace(contenido_md, 'contacto@avancemos.co', 'abulingo.help@gmail.com'), 'datos@avancemos.co', 'abulingo.help@gmail.com')
where contenido_md like '%@avancemos.co%';

-- Archivos M4A de iPhone
update storage.buckets set allowed_mime_types = array_append(allowed_mime_types, 'audio/x-m4a')
where id in ('media-pendiente','media-publica','media-miembros','sitio') and not ('audio/x-m4a' = any(allowed_mime_types));
