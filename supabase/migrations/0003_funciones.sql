-- =============================================================================
-- Migración 0003: Funciones de Seguridad y Procedimientos Almacenados (RPC)
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Funciones Auxiliares de Seguridad (evaluación de roles y estados)
-- -----------------------------------------------------------------------------
create or replace function public.tiene_rol(r public.rol_app)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.rol = r and ur.activo
  );
$$;

create or replace function public.es_admin_nacional()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.tiene_rol('admin_nacional'::public.rol_app);
$$;

create or replace function public.es_miembro_activo()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid()) and p.estado = 'activo'
  );
$$;

create or replace function public.puede_moderar(dep text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin_nacional()
      or (dep is not null and exists (
            select 1 from public.user_roles ur
            where ur.user_id = (select auth.uid()) and ur.activo
              and ur.rol in ('admin_departamental'::public.rol_app, 'moderador'::public.rol_app)
              and ur.departamento_id = dep));
$$;

create or replace function public.es_admin_de(dep text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin_nacional()
      or (dep is not null and exists (
            select 1 from public.user_roles ur
            where ur.user_id = (select auth.uid()) and ur.activo
              and ur.rol = 'admin_departamental'::public.rol_app and ur.departamento_id = dep));
$$;

create or replace function public.puede_interactuar()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.estado = 'activo'
      and not exists (
        select 1 from public.sanciones s
        where s.user_id = p.id
          and s.tipo in ('silencio', 'suspension', 'baneo')
          and (s.hasta is null or s.hasta > now())
      )
  );
$$;

create or replace function public.exigir_mfa()
returns void language plpgsql stable set search_path = '' as $$
begin
  -- En entorno local / testing permitir si no hay mfa configurado
  if coalesce((select auth.jwt() ->> 'aal'), 'aal1') <> 'aal2' then
    -- Si es admin o moderador en producción debe exigir aal2
    -- Verificamos si tiene roles administrativos
    if exists (
      select 1 from public.user_roles ur
      where ur.user_id = (select auth.uid()) and ur.activo
        and ur.rol in ('admin_nacional'::public.rol_app, 'admin_departamental'::public.rol_app, 'moderador'::public.rol_app)
    ) then
      raise exception 'Se requiere verificación en dos pasos (AAL2)' using errcode = '42501';
    end if;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- RPCs para Miembros y Usuarios
-- -----------------------------------------------------------------------------

create or replace function public.usuario_disponible(p_username text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_clean text;
begin
  v_clean := lower(trim(p_username));
  if v_clean !~ '^[a-z0-9_]{3,30}$' then
    return false;
  end if;
  
  -- Nombres reservados de la plataforma
  if v_clean in ('avancemos', 'oficial', 'admin', 'soporte', 'colombia', 'ayuda', 'moderador') or
     exists (select 1 from public.departamentos where lower(slug) = v_clean) then
    return false;
  end if;

  return not exists (
    select 1 from public.perfiles where username = v_clean::public.citext
  );
end;
$$;

create or replace function public.mis_permisos()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_estado text;
  v_roles jsonb;
  v_es_nacional boolean;
  v_deptos_mod text[];
begin
  v_uid := auth.uid();
  if v_uid is null then
    return jsonb_build_object('autenticado', false);
  end if;

  select estado::text into v_estado from public.perfiles where id = v_uid;
  v_es_nacional := public.es_admin_nacional();

  select coalesce(jsonb_agg(jsonb_build_object(
    'rol', rol,
    'departamento_id', departamento_id,
    'municipio_id', municipio_id,
    'titulo', titulo
  )), '[]'::jsonb) into v_roles
  from public.user_roles
  where user_id = v_uid and activo;

  select array_agg(distinct departamento_id) into v_deptos_mod
  from public.user_roles
  where user_id = v_uid and activo
    and rol in ('admin_departamental'::public.rol_app, 'moderador'::public.rol_app)
    and departamento_id is not null;

  return jsonb_build_object(
    'autenticado', true,
    'user_id', v_uid,
    'estado', v_estado,
    'es_miembro_activo', v_estado = 'activo',
    'es_admin_nacional', v_es_nacional,
    'departamentos_moderacion', coalesce(v_deptos_mod, '{}'),
    'roles', v_roles,
    'puede_interactuar', public.puede_interactuar()
  );
end;
$$;

create or replace function public.feed(
  tipo text default 'nacional',
  cursor_fecha timestamptz default null,
  cursor_id uuid default null,
  limite integer default 20
)
returns table (
  id uuid,
  autor_id uuid,
  autor_nombre text,
  autor_username text,
  autor_avatar text,
  autor_insignia public.insignia,
  autor_cargo text,
  contenido text,
  categoria text,
  alcance public.alcance,
  departamento_id text,
  municipio_id text,
  visibilidad public.visibilidad,
  publicado_en timestamptz,
  es_oficial boolean,
  fijada boolean,
  enlace_url text,
  enlace_preview jsonb,
  me_gusta_n integer,
  comentarios_n integer,
  compartidos_n integer,
  le_gusta boolean,
  guardado boolean,
  media jsonb
) language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_depto text;
  v_muni text;
begin
  v_uid := auth.uid();
  if v_uid is not null then
    select departamento_id, municipio_id into v_depto, v_muni
    from public.perfiles where perfiles.id = v_uid;
  end if;

  return query
  select
    p.id,
    p.autor_id,
    pf.nombre,
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
$$;

create or replace function public.feed_publico(
  cursor_fecha timestamptz default null,
  cursor_id uuid default null,
  limite integer default 15
)
returns table (
  id uuid,
  autor_nombre text,
  autor_username text,
  autor_avatar text,
  autor_insignia public.insignia,
  contenido text,
  categoria text,
  publicado_en timestamptz,
  es_oficial boolean,
  enlace_url text,
  enlace_preview jsonb,
  me_gusta_n integer,
  comentarios_n integer,
  media jsonb
) language plpgsql stable security definer set search_path = '' as $$
begin
  return query
  select
    p.id,
    pf.nombre,
    pf.username::text,
    pf.avatar_path,
    pf.insignia,
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
$$;

create or replace function public.publicacion_publica(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb;
begin
  select jsonb_build_object(
    'id', p.id,
    'autor_nombre', pf.nombre,
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
$$;

create or replace function public.estadisticas_publicas()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_umbral int := 5;
  v_activos int;
  v_deptos int;
  v_munis int;
  v_departamentos_data jsonb;
begin
  select coalesce((valor->>'umbral_privacidad_mapa')::int, 5) into v_umbral
  from public.configuracion where clave = 'general';

  select count(*) into v_activos from public.perfiles where estado = 'activo';
  select count(distinct departamento_id) into v_deptos from public.perfiles where estado = 'activo' and departamento_id is not null;
  select count(distinct municipio_id) into v_munis from public.perfiles where estado = 'activo' and municipio_id is not null;

  with conteos as (
    select
      d.id,
      d.nombre,
      d.region,
      d.slug,
      count(p.id) as total
    from public.departamentos d
    left join public.perfiles p on p.departamento_id = d.id and p.estado = 'activo'
    group by d.id, d.nombre, d.region, d.slug
  )
  select coalesce(jsonb_object_agg(
    c.id,
    jsonb_build_object(
      'nombre', c.nombre,
      'region', c.region,
      'slug', c.slug,
      'conteo', case when c.total >= v_umbral then c.total else 0 end,
      'rotulo', case when c.total >= v_umbral then c.total::text else 'menos de ' || v_umbral end
    )
  ), '{}'::jsonb) into v_departamentos_data
  from conteos c;

  return jsonb_build_object(
    'miembros_activos', v_activos,
    'departamentos_con_presencia', v_deptos,
    'municipios_con_presencia', v_munis,
    'departamentos', coalesce(v_departamentos_data, '{}'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Procedimientos de Creación de Publicación
-- -----------------------------------------------------------------------------
create or replace function public.crear_publicacion(
  p_id uuid,
  p_contenido text,
  p_categoria text default 'opinion',
  p_alcance public.alcance default 'departamental',
  p_visibilidad public.visibilidad default 'publica',
  p_enlace_url text default null,
  p_media jsonb default '[]'::jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_depto text;
  v_muni text;
  v_depto_mod text;
  v_auto_aprobada boolean := false;
  v_item jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  if not public.puede_interactuar() then
    raise exception 'Tu cuenta no tiene permisos para interactuar o está sancionada.' using errcode = '42501';
  end if;

  select departamento_id, municipio_id into v_depto, v_muni
  from public.perfiles where id = v_uid;

  -- Si es admin o moderador se auto-aprueba según configuración
  if public.es_admin_nacional() or public.es_admin_de(v_depto) then
    v_auto_aprobada := true;
  end if;

  -- Determinar departamento de moderación: nacional = null, sino el departamento del autor
  if p_alcance = 'nacional' then
    v_depto_mod := null;
  else
    v_depto_mod := v_depto;
  end if;

  insert into public.publicaciones (
    id,
    autor_id,
    contenido,
    categoria,
    alcance,
    departamento_id,
    municipio_id,
    departamento_moderacion,
    visibilidad,
    estado,
    publicado_en,
    enlace_url
  ) values (
    p_id,
    v_uid,
    p_contenido,
    p_categoria,
    p_alcance,
    v_depto,
    v_muni,
    v_depto_mod,
    p_visibilidad,
    case when v_auto_aprobada then 'aprobado'::public.estado_revision else 'pendiente'::public.estado_revision end,
    case when v_auto_aprobada then now() else null end,
    p_enlace_url
  );

  -- Insertar media
  if jsonb_array_length(p_media) > 0 then
    for v_item in select * from jsonb_array_elements(p_media) loop
      insert into public.publicacion_media (
        publicacion_id,
        tipo,
        bucket,
        path,
        ancho,
        alto,
        duracion_s,
        alt_text,
        orden,
        generada_ia
      ) values (
        p_id,
        coalesce(v_item->>'tipo', 'imagen'),
        coalesce(v_item->>'bucket', 'media-pendiente'),
        v_item->>'path',
        (v_item->>'ancho')::int,
        (v_item->>'alto')::int,
        (v_item->>'duracion_s')::numeric,
        v_item->>'alt_text',
        coalesce((v_item->>'orden')::smallint, 0),
        coalesce((v_item->>'generada_ia')::boolean, false)
      );
    end loop;
  end if;

  return p_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Procedimientos de Mensajería
-- -----------------------------------------------------------------------------
create or replace function public.iniciar_conversacion(destinatario_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_conv_id uuid;
  v_dm_pref text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  if v_uid = destinatario_id then
    raise exception 'No puedes iniciar una conversación contigo mismo.' using errcode = '22000';
  end if;

  -- Verificar si ya existe conversación entre ambos
  select cp1.conversacion_id into v_conv_id
  from public.conversacion_participantes cp1
  join public.conversacion_participantes cp2 on cp1.conversacion_id = cp2.conversacion_id
  where cp1.user_id = v_uid and cp2.user_id = destinatario_id
  limit 1;

  if v_conv_id is not null then
    return v_conv_id;
  end if;

  -- Verificar privacidad del destinatario
  select dm_permitidos into v_dm_pref from public.perfiles where id = destinatario_id;
  if v_dm_pref = 'nadie' and not public.es_admin_nacional() then
    raise exception 'Este usuario no acepta mensajes directos.' using errcode = '42501';
  elsif v_dm_pref = 'seguidos' and not public.es_admin_nacional() then
    if not exists (select 1 from public.seguidores where seguidor_id = destinatario_id and seguido_id = v_uid) then
      raise exception 'Este usuario solo recibe mensajes de personas que sigue.' using errcode = '42501';
    end if;
  end if;

  v_conv_id := gen_random_uuid();
  insert into public.conversaciones (id) values (v_conv_id);
  insert into public.conversacion_participantes (conversacion_id, user_id) values
    (v_conv_id, v_uid),
    (v_conv_id, destinatario_id);

  return v_conv_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Procedimientos de Reportes y Apelaciones
-- -----------------------------------------------------------------------------
create or replace function public.reportar(
  p_entidad text,
  p_entidad_id text,
  p_motivo text,
  p_detalle text default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_reporte_id uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_depto_mod text;
  v_prioridad text := 'normal';
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  if p_motivo in ('amenaza_seguridad', 'violencia') then
    v_prioridad := 'alta';
  end if;

  -- Tomar snapshot del contenido
  if p_entidad = 'publicacion' then
    select jsonb_build_object(
      'autor_id', autor_id,
      'contenido', contenido,
      'departamento_id', departamento_id,
      'created_at', created_at
    ), departamento_moderacion
    into v_snapshot, v_depto_mod
    from public.publicaciones where id = p_entidad_id::uuid;
  elsif p_entidad = 'comentario' then
    select jsonb_build_object(
      'autor_id', autor_id,
      'contenido', contenido,
      'publicacion_id', publicacion_id
    ) into v_snapshot
    from public.comentarios where id = p_entidad_id::uuid;
  elsif p_entidad = 'mensaje' then
    -- Solo copia ESTE mensaje, nunca el resto de la conversación (Regla de oro de privacidad)
    select jsonb_build_object(
      'autor_id', autor_id,
      'contenido', contenido,
      'created_at', created_at
    ) into v_snapshot
    from public.mensajes where id = p_entidad_id::uuid;
  elsif p_entidad = 'perfil' then
    select jsonb_build_object(
      'username', username,
      'nombre', nombre,
      'bio', bio
    ) into v_snapshot
    from public.perfiles where id = p_entidad_id::uuid;
  end if;

  v_reporte_id := gen_random_uuid();
  insert into public.reportes (
    id,
    reportado_por,
    entidad,
    entidad_id,
    motivo,
    detalle,
    snapshot,
    departamento_moderacion,
    prioridad
  ) values (
    v_reporte_id,
    v_uid,
    p_entidad,
    p_entidad_id,
    p_motivo,
    p_detalle,
    v_snapshot,
    v_depto_mod,
    v_prioridad
  );

  return v_reporte_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Procedimientos de Verificación y Cambio de Usuario
-- -----------------------------------------------------------------------------
create or replace function public.solicitar_verificacion(
  p_insignia public.insignia,
  p_cargo text,
  p_motivo text,
  p_enlaces text[] default '{}',
  p_metodo text default 'videollamada'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_id uuid;
  v_created timestamptz;
  v_sancion boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  select created_at into v_created from public.perfiles where id = v_uid and estado = 'activo';
  if v_created is null then
    raise exception 'Solo miembros activos pueden solicitar verificación.' using errcode = '42501';
  end if;

  -- Requisito: 30 días de antigüedad
  if v_created > (now() - interval '30 days') then
    raise exception 'Tu cuenta debe tener al menos 30 días de antigüedad para solicitar insignia.' using errcode = '42501';
  end if;

  -- Requisito: Sin sanciones en los últimos 90 días
  select exists (
    select 1 from public.sanciones
    where user_id = v_uid and created_at > (now() - interval '90 days')
  ) into v_sancion;

  if v_sancion then
    raise exception 'No puedes solicitar verificación si tienes sanciones en los últimos 90 días.' using errcode = '42501';
  end if;

  v_id := gen_random_uuid();
  insert into public.solicitudes_verificacion (
    id,
    user_id,
    insignia_solicitada,
    cargo,
    motivo,
    enlaces,
    metodo_preferido
  ) values (
    v_id,
    v_uid,
    p_insignia,
    p_cargo,
    p_motivo,
    p_enlaces,
    p_metodo
  );

  return v_id;
end;
$$;

create or replace function public.cambiar_usuario(p_nuevo_usuario text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_ultimo timestamptz;
  v_clean text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  select ultimo_cambio_usuario into v_ultimo from public.perfiles where id = v_uid;
  if v_ultimo is not null and v_ultimo > (now() - interval '30 days') then
    raise exception 'Solo puedes cambiar tu nombre de usuario una vez cada 30 días.' using errcode = '42501';
  end if;

  v_clean := lower(trim(p_nuevo_usuario));
  if not public.usuario_disponible(v_clean) then
    raise exception 'El nombre de usuario no está disponible o es reservado.' using errcode = '22000';
  end if;

  update public.perfiles
  set username = v_clean::public.citext,
      ultimo_cambio_usuario = now(),
      updated_at = now()
  where id = v_uid;

  return true;
end;
$$;

create or replace function public.exportar_mis_datos()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_perfil jsonb;
  v_pubs jsonb;
  v_consentimientos jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  select to_jsonb(p) into v_perfil from public.perfiles p where p.id = v_uid;
  select coalesce(jsonb_agg(to_jsonb(pub)), '[]'::jsonb) into v_pubs
  from public.publicaciones pub where pub.autor_id = v_uid;
  select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) into v_consentimientos
  from public.consentimientos c where c.user_id = v_uid;

  return jsonb_build_object(
    'perfil', v_perfil,
    'publicaciones', v_pubs,
    'consentimientos', v_consentimientos,
    'fecha_exportacion', now()
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Procedimientos de Administración y Moderación
-- -----------------------------------------------------------------------------
create or replace function public.revisar_solicitud(
  solicitud_id uuid,
  decision text, -- 'aprobado' | 'rechazado' | 'cambios_solicitados'
  rol_asignado public.rol_app default null,
  comentario text default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_sol record;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  select * into v_sol from public.solicitudes where id = solicitud_id and estado = 'pendiente' for update;
  if not found then
    raise exception 'Solicitud no encontrada o ya resuelta.' using errcode = 'P0002';
  end if;

  if not public.puede_moderar(v_sol.departamento_id) then
    raise exception 'No tienes permisos para revisar solicitudes de este territorio.' using errcode = '42501';
  end if;

  update public.solicitudes
  set estado = decision::public.estado_revision,
      revisado_por = v_uid,
      revisado_en = now(),
      comentario_admin = comentario
  where id = solicitud_id;

  if decision = 'aprobado' then
    update public.perfiles
    set estado = 'activo', updated_at = now()
    where id = v_sol.user_id;

    -- Asignar rol
    insert into public.user_roles (
      user_id, rol, departamento_id, municipio_id, otorgado_por
    ) values (
      v_sol.user_id,
      coalesce(rol_asignado, v_sol.rol_solicitado),
      v_sol.departamento_id,
      v_sol.municipio_id,
      v_uid
    ) on conflict (user_id, rol, coalesce(departamento_id, ''), coalesce(municipio_id, '')) do nothing;

    -- Notificar al usuario
    insert into public.notificaciones (user_id, tipo, actor_id, texto)
    values (v_sol.user_id, 'aprobacion_cuenta', v_uid, '¡Bienvenido a Avancemos! Tu cuenta ha sido aprobada.');
  elsif decision = 'rechazado' then
    update public.perfiles set estado = 'rechazado', updated_at = now() where id = v_sol.user_id;
    insert into public.notificaciones (user_id, tipo, actor_id, texto)
    values (v_sol.user_id, 'rechazo_cuenta', v_uid, coalesce(comentario, 'Tu solicitud no fue aprobada.'));
  end if;

  -- Auditoría
  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (v_uid, 'revisar_solicitud', 'solicitud', solicitud_id::text, v_sol.departamento_id,
          to_jsonb(v_sol), jsonb_build_object('estado', decision, 'comentario', comentario));

  return true;
end;
$$;

create or replace function public.revisar_publicacion(
  publicacion_id uuid,
  decision text, -- 'aprobado' | 'rechazado' | 'cambios_solicitados'
  motivo text default null,
  ajuste_alcance public.alcance default null,
  ajuste_visibilidad public.visibilidad default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_pub record;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  select * into v_pub from public.publicaciones where id = publicacion_id and estado = 'pendiente' for update;
  if not found then
    raise exception 'Publicación no encontrada o ya resuelta.' using errcode = 'P0002';
  end if;

  if not public.puede_moderar(v_pub.departamento_moderacion) then
    raise exception 'No tienes permisos para moderar contenido en este departamento.' using errcode = '42501';
  end if;

  update public.publicaciones
  set estado = decision::public.estado_revision,
      motivo_revision = motivo,
      revisado_por = v_uid,
      revisado_en = now(),
      publicado_en = case when decision = 'aprobado' then coalesce(publicado_en, now()) else publicado_en end,
      alcance = coalesce(ajuste_alcance, alcance),
      visibilidad = coalesce(ajuste_visibilidad, visibilidad),
      updated_at = now()
  where id = publicacion_id;

  -- Notificación
  if decision = 'aprobado' then
    insert into public.notificaciones (user_id, tipo, actor_id, entidad, entidad_id, texto)
    values (v_pub.autor_id, 'publicacion_aprobada', v_uid, 'publicacion', publicacion_id::text, 'Tu publicación fue aprobada y ya está visible.');
  elsif decision = 'rechazado' then
    insert into public.notificaciones (user_id, tipo, actor_id, entidad, entidad_id, texto)
    values (v_pub.autor_id, 'publicacion_rechazada', v_uid, 'publicacion', publicacion_id::text, 'Tu publicación no fue aprobada: ' || coalesce(motivo, 'Revisa las normas de la comunidad.'));
  end if;

  -- Auditoría
  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (v_uid, 'revisar_publicacion', 'publicacion', publicacion_id::text, v_pub.departamento_moderacion,
          to_jsonb(v_pub), jsonb_build_object('estado', decision, 'motivo', motivo));

  return true;
end;
$$;

create or replace function public.escalar(entidad text, entidad_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  if entidad = 'publicacion' then
    update public.publicaciones
    set escalado_a_nacional = true, departamento_moderacion = null
    where id = entidad_id::uuid;
  elsif entidad = 'grupo' then
    update public.grupos_whatsapp
    set escalado_a_nacional = true, departamento_moderacion = null
    where id = entidad_id::uuid;
  elsif entidad = 'evento' then
    update public.eventos
    set escalado_a_nacional = true, departamento_moderacion = null
    where id = entidad_id::uuid;
  elsif entidad = 'reporte' then
    update public.reportes
    set escalado_a_nacional = true, departamento_moderacion = null
    where id = entidad_id::uuid;
  end if;

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, antes, despues)
  values (v_uid, 'escalar_a_nacional', entidad, entidad_id, null, jsonb_build_object('escalado_a_nacional', true));

  return true;
end;
$$;

create or replace function public.otorgar_insignia(p_user_id uuid, p_insignia public.insignia)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_target_depto text;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  select departamento_id into v_target_depto from public.perfiles where id = p_user_id;

  if p_insignia in ('dorada', 'gris') then
    if not public.es_admin_nacional() then
      raise exception 'Solo el Administrador Colombia puede otorgar insignias dorada o gris.' using errcode = '42501';
    end if;
  elsif p_insignia = 'azul' then
    if not public.puede_moderar(v_target_depto) then
      raise exception 'No tienes permisos para otorgar insignia en este departamento.' using errcode = '42501';
    end if;
  end if;

  update public.perfiles
  set insignia = p_insignia,
      insignia_otorgada_por = v_uid,
      insignia_otorgada_en = now(),
      insignia_suspendida = false,
      updated_at = now()
  where id = p_user_id;

  insert into public.notificaciones (user_id, tipo, actor_id, texto)
  values (p_user_id, 'insignia_otorgada', v_uid, '¡Felicitaciones! Has recibido la insignia de verificación ' || p_insignia::text || '.');

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (v_uid, 'otorgar_insignia', 'perfil', p_user_id::text, v_target_depto, null, jsonb_build_object('insignia', p_insignia));

  return true;
end;
$$;

create or replace function public.sancionar(
  p_user_id uuid,
  p_tipo text, -- 'advertencia', 'silencio', 'suspension', 'baneo'
  p_motivo text,
  p_dias int default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_sancion_id uuid;
  v_hasta timestamptz;
  v_target_depto text;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  select departamento_id into v_target_depto from public.perfiles where id = p_user_id;

  if p_tipo = 'baneo' then
    if not public.es_admin_nacional() then
      raise exception 'Solo el Administrador Colombia puede banear definitivamente.' using errcode = '42501';
    end if;
    update public.perfiles set estado = 'baneado', updated_at = now() where id = p_user_id;
  elsif p_tipo = 'suspension' then
    if not public.puede_moderar(v_target_depto) then
      raise exception 'No tienes permisos para suspender usuarios en este departamento.' using errcode = '42501';
    end if;
    update public.perfiles set estado = 'suspendido', updated_at = now() where id = p_user_id;
  end if;

  if p_dias is not null and p_dias > 0 then
    v_hasta := now() + (p_dias || ' days')::interval;
  end if;

  v_sancion_id := gen_random_uuid();
  insert into public.sanciones (id, user_id, tipo, motivo, hasta, impuesta_por)
  values (v_sancion_id, p_user_id, p_tipo, p_motivo, v_hasta, v_uid);

  insert into public.notificaciones (user_id, tipo, actor_id, texto)
  values (p_user_id, 'sancion_' || p_tipo, v_uid, 'Aviso de moderación (' || p_tipo || '): ' || p_motivo);

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (v_uid, 'sancionar_usuario', 'perfil', p_user_id::text, v_target_depto, null,
          jsonb_build_object('tipo', p_tipo, 'motivo', p_motivo, 'hasta', v_hasta));

  return v_sancion_id;
end;
$$;

create or replace function public.resolver_reporte(
  p_reporte_id uuid,
  p_accion text, -- 'descartar', 'ocultar', 'sancionar'
  p_resolucion text default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_rep record;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  select * into v_rep from public.reportes where id = p_reporte_id for update;
  if not found then
    raise exception 'Reporte no encontrado.' using errcode = 'P0002';
  end if;

  if not public.puede_moderar(v_rep.departamento_moderacion) then
    raise exception 'No tienes permisos para resolver este reporte territorial.' using errcode = '42501';
  end if;

  update public.reportes
  set estado = case when p_accion = 'descartar' then 'descartado' else 'resuelto' end,
      resuelto_por = v_uid,
      resolucion = coalesce(p_resolucion, p_accion)
  where id = p_reporte_id;

  if p_accion = 'ocultar' then
    if v_rep.entidad = 'publicacion' then
      update public.publicaciones set estado = 'retirado' where id = v_rep.entidad_id::uuid;
    elsif v_rep.entidad = 'comentario' then
      update public.comentarios set estado = 'oculto' where id = v_rep.entidad_id::uuid;
    end if;
  end if;

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (v_uid, 'resolver_reporte', 'reporte', p_reporte_id::text, v_rep.departamento_moderacion,
          to_jsonb(v_rep), jsonb_build_object('accion', p_accion, 'resolucion', p_resolucion));

  return true;
end;
$$;

-- -----------------------------------------------------------------------------
-- Procedimientos del Sistema de Soporte y Casos
-- -----------------------------------------------------------------------------
create or replace function public.crear_caso_soporte(
  p_nombre text,
  p_correo text,
  p_telefono text default null,
  p_categoria text default 'otro',
  p_asunto text default '',
  p_descripcion text default '',
  p_departamento_id text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_caso_id uuid;
  v_radicado text;
  v_tipo_usuario text := 'visitante';
begin
  v_uid := auth.uid();

  if v_uid is not null then
    select case when estado = 'activo' then 'miembro_activo' else 'inscrito_pendiente' end
    into v_tipo_usuario
    from public.perfiles where id = v_uid;
  end if;

  -- Generar radicado único (ej: RAD-2026-XXXX)
  v_radicado := 'RAD-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 900000 + 100000)::text, 6, '0');
  v_caso_id := gen_random_uuid();

  insert into public.casos_soporte (
    id,
    numero_radicado,
    user_id,
    nombre_contacto,
    correo_contacto,
    telefono_contacto,
    tipo_usuario,
    categoria,
    asunto,
    descripcion,
    departamento_id
  ) values (
    v_caso_id,
    v_radicado,
    v_uid,
    trim(p_nombre),
    lower(trim(p_correo))::public.citext,
    p_telefono,
    v_tipo_usuario,
    p_categoria,
    trim(p_asunto),
    trim(p_descripcion),
    p_departamento_id
  );

  -- Registrar primer mensaje en el historial del caso
  insert into public.caso_mensajes (caso_id, autor_id, es_equipo, es_ia, mensaje)
  values (v_caso_id, v_uid, false, false, p_descripcion);

  return jsonb_build_object(
    'caso_id', v_caso_id,
    'numero_radicado', v_radicado,
    'mensaje', 'Tu caso ha sido radicado exitosamente. Guarda tu número de radicado para hacer seguimiento.'
  );
end;
$$;

create or replace function public.consultar_caso_soporte(
  p_radicado text,
  p_correo text
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_caso record;
  v_mensajes jsonb;
begin
  select * into v_caso
  from public.casos_soporte
  where numero_radicado = upper(trim(p_radicado))
    and correo_contacto = lower(trim(p_correo))::public.citext;

  if not found then
    return jsonb_build_object('encontrado', false, 'mensaje', 'No se encontró ningún caso con los datos proporcionados.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', cm.id,
    'es_equipo', cm.es_equipo,
    'es_ia', cm.es_ia,
    'mensaje', cm.mensaje,
    'created_at', cm.created_at
  ) order by cm.created_at), '[]'::jsonb) into v_mensajes
  from public.caso_mensajes cm
  where cm.caso_id = v_caso.id;

  return jsonb_build_object(
    'encontrado', true,
    'caso', jsonb_build_object(
      'id', v_caso.id,
      'numero_radicado', v_caso.numero_radicado,
      'nombre_contacto', v_caso.nombre_contacto,
      'categoria', v_caso.categoria,
      'asunto', v_caso.asunto,
      'estado', v_caso.estado,
      'prioridad', v_caso.prioridad,
      'respuesta_oficial', v_caso.respuesta_oficial,
      'created_at', v_caso.created_at,
      'updated_at', v_caso.updated_at
    ),
    'mensajes', v_mensajes
  );
end;
$$;

create or replace function public.agregar_mensaje_caso(
  p_caso_id uuid,
  p_mensaje text,
  p_correo text default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_es_equipo boolean := false;
  v_caso record;
begin
  v_uid := auth.uid();
  select * into v_caso from public.casos_soporte where id = p_caso_id;
  if not found then
    raise exception 'Caso no encontrado.' using errcode = 'P0002';
  end if;

  if v_uid is not null and (public.es_admin_nacional() or public.puede_moderar(v_caso.departamento_id)) then
    v_es_equipo := true;
  else
    -- Si es el usuario debe coincidir su id o su correo
    if v_uid is not null and v_caso.user_id = v_uid then
      v_es_equipo := false;
    elsif p_correo is not null and v_caso.correo_contacto = lower(trim(p_correo))::public.citext then
      v_es_equipo := false;
    else
      raise exception 'No autorizado para responder en este caso.' using errcode = '42501';
    end if;
  end if;

  insert into public.caso_mensajes (caso_id, autor_id, es_equipo, es_ia, mensaje)
  values (p_caso_id, v_uid, v_es_equipo, false, trim(p_mensaje));

  update public.casos_soporte
  set estado = case when v_es_equipo then 'esperando_usuario' else 'en_proceso' end,
      updated_at = now()
  where id = p_caso_id;

  return true;
end;
$$;

create or replace function public.resolver_caso_soporte(
  p_caso_id uuid,
  p_estado text, -- 'en_proceso', 'esperando_usuario', 'resuelto', 'cerrado'
  p_respuesta text default null,
  p_prioridad text default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_caso record;
begin
  v_uid := auth.uid();
  perform public.exigir_mfa();

  select * into v_caso from public.casos_soporte where id = p_caso_id;
  if not found then
    raise exception 'Caso no encontrado.' using errcode = 'P0002';
  end if;

  if not (public.es_admin_nacional() or public.puede_moderar(v_caso.departamento_id)) then
    raise exception 'No tienes permisos para gestionar casos de este departamento.' using errcode = '42501';
  end if;

  update public.casos_soporte
  set estado = p_estado,
      respuesta_oficial = coalesce(p_respuesta, respuesta_oficial),
      prioridad = coalesce(p_prioridad, prioridad),
      resuelto_por = case when p_estado in ('resuelto', 'cerrado') then v_uid else resuelto_por end,
      resuelto_en = case when p_estado in ('resuelto', 'cerrado') then now() else resuelto_en end,
      updated_at = now()
  where id = p_caso_id;

  if p_respuesta is not null and length(trim(p_respuesta)) > 0 then
    insert into public.caso_mensajes (caso_id, autor_id, es_equipo, es_ia, mensaje)
    values (p_caso_id, v_uid, true, false, trim(p_respuesta));
  end if;

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (v_uid, 'gestionar_caso_soporte', 'casos_soporte', p_caso_id::text, v_caso.departamento_id,
          to_jsonb(v_caso), jsonb_build_object('estado', p_estado, 'respuesta', p_respuesta));

  return true;
end;
$$;
