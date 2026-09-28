-- =============================================================================
-- Migración 0012 (parte 1): privacidad de nombres, perfil, mensajes y publicaciones
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Solo el primer nombre es visible para otros usuarios
--    La columna `nombre` deja de ser legible por la API; se expone `primer_nombre`.
--    El propio usuario lo obtiene con mi_perfil() y los admins con sus RPCs.
-- -----------------------------------------------------------------------------
alter table public.perfiles
  add column if not exists primer_nombre text
  generated always as (split_part(btrim(nombre), ' ', 1)) stored;

revoke select on public.perfiles from anon, authenticated;
grant select (
  id, tipo_cuenta, username, primer_nombre, bio, avatar_path, portada_path,
  departamento_id, municipio_id, localidad_id, cargo_titulo, ocupacion, intereses, redes,
  estado, insignia, insignia_suspendida, insignia_otorgada_en, perfil_publico,
  mostrar_municipio, dm_permitidos, seguidores_n, siguiendo_n, publicaciones_n, created_at
) on public.perfiles to anon, authenticated;

-- 2. El usuario solo puede editar su biografía
revoke update on public.perfiles from anon, authenticated;
grant update (bio) on public.perfiles to authenticated;

-- Perfil completo del usuario autenticado (incluye nombre completo, datos privados y roles)
create or replace function public.mi_perfil()
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null else (
    select to_jsonb(p) || jsonb_build_object(
      'privado', (select to_jsonb(pp) from public.perfiles_privados pp where pp.id = p.id),
      'roles', coalesce((select jsonb_agg(to_jsonb(r)) from public.user_roles r where r.user_id = p.id and r.activo), '[]'::jsonb),
      'departamento_nombre', (select d.nombre from public.departamentos d where d.id = p.departamento_id),
      'municipio_nombre', (select m.nombre from public.municipios m where m.id = p.municipio_id)
    )
    from public.perfiles p where p.id = auth.uid()
  ) end;
$$;
grant execute on function public.mi_perfil() to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Mensajes directos: solo puedes escribir a personas que sigues
-- -----------------------------------------------------------------------------
create or replace function public.iniciar_conversacion(destinatario_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_conv_id uuid;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  if v_uid = destinatario_id then
    raise exception 'No puedes iniciar una conversación contigo mismo.' using errcode = '22000';
  end if;
  if not public.puede_interactuar() then
    raise exception 'Tu cuenta aún no puede enviar mensajes.' using errcode = '42501';
  end if;
  if not public.es_admin_nacional() and not exists (
    select 1 from public.seguidores where seguidor_id = v_uid and seguido_id = destinatario_id
  ) then
    raise exception 'Solo puedes enviar mensajes a personas que sigues.' using errcode = '42501';
  end if;

  select cp1.conversacion_id into v_conv_id
  from public.conversacion_participantes cp1
  join public.conversacion_participantes cp2 on cp1.conversacion_id = cp2.conversacion_id
  where cp1.user_id = v_uid and cp2.user_id = destinatario_id
  limit 1;
  if v_conv_id is not null then
    return v_conv_id;
  end if;

  v_conv_id := gen_random_uuid();
  insert into public.conversaciones (id) values (v_conv_id);
  insert into public.conversacion_participantes (conversacion_id, user_id) values
    (v_conv_id, v_uid), (v_conv_id, destinatario_id);
  return v_conv_id;
end;
$$;

-- ¿El usuario actual sigue a la otra persona de la conversación?
create or replace function public.puede_escribir_en(p_conversacion_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin_nacional() or exists (
    select 1
    from public.conversacion_participantes otro
    join public.seguidores s on s.seguido_id = otro.user_id and s.seguidor_id = auth.uid()
    where otro.conversacion_id = p_conversacion_id and otro.user_id <> auth.uid()
  );
$$;
grant execute on function public.puede_escribir_en(uuid) to authenticated;

drop policy if exists "participante_enviar_mensaje" on public.mensajes;
create policy "participante_enviar_mensaje" on public.mensajes for insert with check (
  autor_id = (select auth.uid())
  and public.es_participante(conversacion_id)
  and public.puede_escribir_en(conversacion_id)
  and (select public.puede_interactuar())
);

-- Datos visibles del otro participante en cada conversación
create or replace function public.mis_conversaciones()
returns table (
  conversacion_id uuid, ultimo_mensaje_en timestamptz, ultimo_mensaje_preview text,
  otro_id uuid, otro_nombre text, otro_username text, otro_avatar text, otro_insignia public.insignia,
  puedo_escribir boolean
) language sql stable security definer set search_path = '' as $$
  select c.id, c.ultimo_mensaje_en, c.ultimo_mensaje_preview,
         o.id, o.primer_nombre, o.username::text, o.avatar_path, o.insignia,
         public.puede_escribir_en(c.id)
  from public.conversacion_participantes yo
  join public.conversaciones c on c.id = yo.conversacion_id
  join public.conversacion_participantes cp on cp.conversacion_id = c.id and cp.user_id <> yo.user_id
  join public.perfiles o on o.id = cp.user_id
  where yo.user_id = auth.uid()
  order by c.ultimo_mensaje_en desc nulls last;
$$;
grant execute on function public.mis_conversaciones() to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Publicaciones: el autor no puede cambiar columnas directamente
--    (antes podía auto-aprobarse). Editar y eliminar va por RPC.
-- -----------------------------------------------------------------------------
drop policy if exists "actualizar_publicaciones" on public.publicaciones;

create or replace function public.editar_publicacion(p_id uuid, p_contenido text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_pub record;
  v_auto boolean;
begin
  select * into v_pub from public.publicaciones where id = p_id and eliminado_en is null for update;
  if not found then
    raise exception 'Publicación no encontrada.' using errcode = 'P0002';
  end if;
  if v_pub.autor_id <> v_uid then
    raise exception 'Solo el autor puede editar esta publicación.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_contenido), '') = '' or char_length(p_contenido) > 3000 then
    raise exception 'El contenido debe tener entre 1 y 3000 caracteres.' using errcode = '22023';
  end if;

  -- Administradores publican directo; los demás vuelven a revisión
  v_auto := public.es_admin_nacional() or public.es_admin_de(v_pub.departamento_id);
  update public.publicaciones
  set contenido = btrim(p_contenido),
      estado = case when v_auto then estado else 'pendiente'::public.estado_revision end,
      updated_at = now()
  where id = p_id;

  return case when v_auto then v_pub.estado::text else 'pendiente' end;
end;
$$;
grant execute on function public.editar_publicacion(uuid, text) to authenticated;

create or replace function public.eliminar_publicacion(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_pub record;
begin
  select * into v_pub from public.publicaciones where id = p_id and eliminado_en is null;
  if not found then
    raise exception 'Publicación no encontrada.' using errcode = 'P0002';
  end if;
  if v_pub.autor_id <> auth.uid() and not public.puede_moderar(v_pub.departamento_moderacion) then
    raise exception 'No tienes permisos para eliminar esta publicación.' using errcode = '42501';
  end if;

  update public.publicaciones set eliminado_en = now(), updated_at = now() where id = p_id;

  if v_pub.autor_id <> auth.uid() then
    insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes)
    values (auth.uid(), 'eliminar_publicacion', 'publicacion', p_id::text, v_pub.departamento_moderacion, to_jsonb(v_pub));
  end if;
  return true;
end;
$$;
grant execute on function public.eliminar_publicacion(uuid) to authenticated;

-- Publicaciones de un perfil: el dueño ve todas (con estado), los demás solo las aprobadas
create or replace function public.publicaciones_de_perfil(p_username text, p_limite integer default 30)
returns table (
  id uuid, autor_id uuid, autor_nombre text, autor_username text, autor_avatar text,
  autor_insignia public.insignia, autor_cargo text, contenido text, categoria text,
  estado public.estado_revision, motivo_revision text, publicado_en timestamptz, created_at timestamptz,
  es_oficial boolean, me_gusta_n integer, comentarios_n integer, le_gusta boolean, guardado boolean, media jsonb
) language sql stable security definer set search_path = '' as $$
  select p.id, p.autor_id, pf.primer_nombre, pf.username::text, pf.avatar_path, pf.insignia, pf.cargo_titulo,
         p.contenido, p.categoria, p.estado, p.motivo_revision, coalesce(p.publicado_en, p.created_at), p.created_at,
         p.es_oficial, p.me_gusta_n, p.comentarios_n,
         exists (select 1 from public.me_gusta mg where mg.publicacion_id = p.id and mg.user_id = auth.uid()),
         exists (select 1 from public.guardados g where g.publicacion_id = p.id and g.user_id = auth.uid()),
         coalesce((select jsonb_agg(jsonb_build_object('id', pm.id, 'tipo', pm.tipo, 'path', pm.path, 'bucket', pm.bucket, 'alt_text', pm.alt_text) order by pm.orden)
                   from public.publicacion_media pm where pm.publicacion_id = p.id), '[]'::jsonb)
  from public.publicaciones p
  join public.perfiles pf on pf.id = p.autor_id
  where pf.username = p_username::public.citext
    and p.eliminado_en is null
    and (
      p.autor_id = auth.uid()
      or (p.estado = 'aprobado' and p.publicado_en <= now()
          and (p.visibilidad = 'publica' or public.es_miembro_activo()))
    )
  order by p.created_at desc
  limit least(coalesce(p_limite, 30), 100);
$$;
grant execute on function public.publicaciones_de_perfil(text, integer) to anon, authenticated;

-- Seguidores y seguidos de un perfil
create or replace function public.relaciones_de_perfil(p_username text, p_tipo text)
returns table (id uuid, nombre text, username text, avatar_path text, insignia public.insignia, cargo_titulo text, lo_sigo boolean)
language sql stable security definer set search_path = '' as $$
  select o.id, o.primer_nombre, o.username::text, o.avatar_path, o.insignia, o.cargo_titulo,
         exists (select 1 from public.seguidores s2 where s2.seguidor_id = auth.uid() and s2.seguido_id = o.id)
  from public.perfiles yo
  join public.seguidores s on (case when p_tipo = 'seguidores' then s.seguido_id else s.seguidor_id end) = yo.id
  join public.perfiles o on o.id = (case when p_tipo = 'seguidores' then s.seguidor_id else s.seguido_id end)
  where yo.username = p_username::public.citext and o.estado = 'activo'
  order by s.created_at desc
  limit 200;
$$;
grant execute on function public.relaciones_de_perfil(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Feeds con primer nombre y etiqueta (cargo_titulo) del autor
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.feed(tipo text DEFAULT 'nacional'::text, cursor_fecha timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_id uuid DEFAULT NULL::uuid, limite integer DEFAULT 20)
 RETURNS TABLE(id uuid, autor_id uuid, autor_nombre text, autor_username text, autor_avatar text, autor_insignia insignia, autor_cargo text, contenido text, categoria text, alcance alcance, departamento_id text, municipio_id text, visibilidad visibilidad, publicado_en timestamp with time zone, es_oficial boolean, fijada boolean, enlace_url text, enlace_preview jsonb, me_gusta_n integer, comentarios_n integer, compartidos_n integer, le_gusta boolean, guardado boolean, media jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid uuid;
  v_depto text;
  v_muni text;
begin
  v_uid := auth.uid();
  if v_uid is not null then
    select p.departamento_id, p.municipio_id into v_depto, v_muni
    from public.perfiles p where p.id = v_uid;
  end if;

  return query
  select
    p.id,
    p.autor_id,
    pf.primer_nombre,
    pf.username::text,
    pf.avatar_path,
    pf.insignia,
    pf.cargo_titulo,
    p.contenido,
    p.categoria,
    p.alcance,
    p.departamento_id,
    p.municipio_id,
    p.visibilidad,
    p.publicado_en,
    p.es_oficial,
    p.fijada,
    p.enlace_url,
    p.enlace_preview,
    p.me_gusta_n,
    p.comentarios_n,
    p.compartidos_n,
    case when v_uid is not null then exists (select 1 from public.me_gusta mg where mg.publicacion_id = p.id and mg.user_id = v_uid) else false end as le_gusta,
    case when v_uid is not null then exists (select 1 from public.guardados gd where gd.publicacion_id = p.id and gd.user_id = v_uid) else false end as guardado,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pm.id,
        'tipo', pm.tipo,
        'path', pm.path,
        'bucket', pm.bucket,
        'ancho', pm.ancho,
        'alto', pm.alto,
        'alt_text', pm.alt_text,
        'generada_ia', pm.generada_ia
      ) order by pm.orden)
      from public.publicacion_media pm
      where pm.publicacion_id = p.id
    ), '[]'::jsonb) as media
  from public.publicaciones p
  join public.perfiles pf on pf.id = p.autor_id
  where p.estado = 'aprobado'
    and p.eliminado_en is null
    and p.publicado_en <= now()
    and (p.visibilidad = 'publica' or (v_uid is not null and exists (select 1 from public.perfiles where id = v_uid and estado = 'activo')))
    and (
      case
        when tipo = 'mi_departamento' then p.departamento_id = v_depto
        when tipo = 'mi_municipio' then p.municipio_id = v_muni
        when tipo = 'siguiendo' then v_uid is not null and exists (select 1 from public.seguidores s where s.seguidor_id = v_uid and s.seguido_id = p.autor_id)
        else true -- nacional
      end
    )
    and (
      cursor_fecha is null or
      p.publicado_en < cursor_fecha or
      (p.publicado_en = cursor_fecha and p.id < cursor_id)
    )
  order by p.fijada desc, p.publicado_en desc, p.id desc
  limit coalesce(limite, 20);
end;
$function$;

drop function if exists public.feed_publico(timestamp with time zone, uuid, integer);
CREATE OR REPLACE FUNCTION public.feed_publico(cursor_fecha timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_id uuid DEFAULT NULL::uuid, limite integer DEFAULT 15)
 RETURNS TABLE(id uuid, autor_nombre text, autor_username text, autor_avatar text, autor_insignia insignia, autor_cargo text, contenido text, categoria text, publicado_en timestamp with time zone, es_oficial boolean, enlace_url text, enlace_preview jsonb, me_gusta_n integer, comentarios_n integer, media jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  select
    p.id,
    pf.primer_nombre,
    pf.username::text,
    pf.avatar_path,
    pf.insignia,
    pf.cargo_titulo,
    p.contenido,
    p.categoria,
    p.publicado_en,
    p.es_oficial,
    p.enlace_url,
    p.enlace_preview,
    p.me_gusta_n,
    p.comentarios_n,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo', pm.tipo,
        'path', pm.path,
        'bucket', pm.bucket,
        'alt_text', pm.alt_text,
        'generada_ia', pm.generada_ia
      ) order by pm.orden)
      from public.publicacion_media pm
      where pm.publicacion_id = p.id
    ), '[]'::jsonb) as media
  from public.publicaciones p
  join public.perfiles pf on pf.id = p.autor_id
  where p.estado = 'aprobado'
    and p.visibilidad = 'publica'
    and p.eliminado_en is null
    and p.publicado_en <= now()
    and (
      cursor_fecha is null or
      p.publicado_en < cursor_fecha or
      (p.publicado_en = cursor_fecha and p.id < cursor_id)
    )
  order by p.fijada desc, p.publicado_en desc, p.id desc
  limit coalesce(limite, 15);
end;
$function$;

CREATE OR REPLACE FUNCTION public.publicacion_publica(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_res jsonb;
begin
  select jsonb_build_object(
    'id', p.id,
    'autor_nombre', pf.primer_nombre,
    'autor_cargo', pf.cargo_titulo,
    'autor_id', p.autor_id,
    'autor_username', pf.username::text,
    'autor_avatar', pf.avatar_path,
    'autor_insignia', pf.insignia,
    'contenido', p.contenido,
    'categoria', p.categoria,
    'publicado_en', p.publicado_en,
    'es_oficial', p.es_oficial,
    'enlace_url', p.enlace_url,
    'enlace_preview', p.enlace_preview,
    'me_gusta_n', p.me_gusta_n,
    'comentarios_n', p.comentarios_n,
    'media', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo', pm.tipo,
        'path', pm.path,
        'bucket', pm.bucket,
        'alt_text', pm.alt_text,
        'generada_ia', pm.generada_ia
      ) order by pm.orden)
      from public.publicacion_media pm
      where pm.publicacion_id = p.id
    ), '[]'::jsonb)
  ) into v_res
  from public.publicaciones p
  join public.perfiles pf on pf.id = p.autor_id
  where p.id = p_id
    and p.estado = 'aprobado'
    and p.visibilidad = 'publica'
    and p.eliminado_en is null;

  return v_res;
end;
$function$;
grant execute on function public.feed_publico(timestamp with time zone, uuid, integer) to anon, authenticated;
