-- =============================================================================
-- Migración 0005: Disparadores (Triggers) y Automatizaciones
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger de Registro: crear_perfil_nuevo_usuario
-- -----------------------------------------------------------------------------
create or replace function public.tr_crear_perfil_nuevo_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_meta jsonb;
  v_nombre text;
  v_username text;
  v_base_username text;
  v_depto text;
  v_muni text;
  v_loc smallint;
  v_rol_solicitado public.rol_app := 'simpatizante'::public.rol_app;
  v_motivo text;
  v_telefono text;
  v_intereses text[];
  v_ocupacion text;
  v_suffix integer := 1;
begin
  v_meta := coalesce(new.raw_user_meta_data, '{}'::jsonb);

  v_nombre := coalesce(trim(v_meta->>'nombre'), split_part(new.email, '@', 1));
  v_base_username := lower(regexp_replace(coalesce(v_meta->>'username', split_part(new.email, '@', 1)), '[^a-z0-9_]', '', 'g'));
  if length(v_base_username) < 3 then
    v_base_username := 'usuario_' || substr(md5(random()::text), 1, 6);
  end if;

  v_username := v_base_username;
  -- Generar username libre si ya existe
  while exists (select 1 from public.perfiles where username = v_username::public.citext) loop
    v_username := substr(v_base_username, 1, 24) || '_' || v_suffix;
    v_suffix := v_suffix + 1;
  end loop;

  v_depto := v_meta->>'departamento_id';
  v_muni := v_meta->>'municipio_id';
  if (v_meta->>'localidad_id') is not null then
    v_loc := (v_meta->>'localidad_id')::smallint;
  end if;

  if (v_meta->>'rol_solicitado') in ('simpatizante', 'voluntario', 'lider') then
    v_rol_solicitado := (v_meta->>'rol_solicitado')::public.rol_app;
  end if;

  v_motivo := v_meta->>'motivo';
  v_telefono := v_meta->>'telefono';
  v_ocupacion := v_meta->>'ocupacion';

  -- Crear perfil
  insert into public.perfiles (
    id,
    nombre,
    username,
    departamento_id,
    municipio_id,
    localidad_id,
    ocupacion,
    estado
  ) values (
    new.id,
    v_nombre,
    v_username::public.citext,
    v_depto,
    v_muni,
    v_loc,
    v_ocupacion,
    'pendiente'::public.estado_cuenta
  );

  -- Perfil privado con teléfono
  if v_telefono is not null and length(trim(v_telefono)) > 0 then
    insert into public.perfiles_privados (id, telefono)
    values (new.id, trim(v_telefono));
  end if;

  -- Crear solicitud de ingreso
  insert into public.solicitudes (
    user_id,
    tipo,
    rol_solicitado,
    departamento_id,
    municipio_id,
    motivo,
    estado
  ) values (
    new.id,
    'ingreso',
    v_rol_solicitado,
    v_depto,
    v_muni,
    v_motivo,
    'pendiente'::public.estado_revision
  );

  -- Registrar consentimientos obligatorios según Ley 1581
  insert into public.consentimientos (
    user_id,
    version_politica,
    acepta_terminos,
    autoriza_datos_sensibles,
    mayor_de_edad,
    user_agent
  ) values (
    new.id,
    coalesce(v_meta->>'version_politica', '1.0'),
    coalesce((v_meta->>'acepta_terminos')::boolean, true),
    coalesce((v_meta->>'autoriza_datos_sensibles')::boolean, true),
    coalesce((v_meta->>'mayor_de_edad')::boolean, true),
    v_meta->>'user_agent'
  );

  return new;
exception when others then
  -- Nunca romper el registro de auth
  return new;
end;
$$;

-- Trigger sobre auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.tr_crear_perfil_nuevo_usuario();

-- -----------------------------------------------------------------------------
-- 2. Trigger de Publicaciones: forzar estado, autor y departamento
-- -----------------------------------------------------------------------------
create or replace function public.tr_publicaciones_validar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_palabra record;
begin
  v_uid := auth.uid();
  if v_uid is not null then
    new.autor_id := v_uid;
  end if;

  -- Chequeo de palabras bloqueadas
  for v_palabra in select palabra, nivel from public.palabras_bloqueadas loop
    if new.contenido ~* ('\y' || v_palabra.palabra || '\y') then
      if v_palabra.nivel = 'bloquear' then
        raise exception 'Tu publicación contiene términos no permitidos por las normas de la comunidad.' using errcode = '22000';
      end if;
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists on_publicacion_validar on public.publicaciones;
create trigger on_publicacion_validar
  before insert or update of contenido on public.publicaciones
  for each row execute function public.tr_publicaciones_validar();

-- -----------------------------------------------------------------------------
-- 3. Extracción de Hashtags y Menciones al Aprobar Publicación
-- -----------------------------------------------------------------------------
create or replace function public.tr_publicacion_aprobada_extraer_tags()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_tag text;
  v_user text;
  v_target_id uuid;
begin
  if new.estado = 'aprobado' and (old.estado is null or old.estado <> 'aprobado') then
    -- Extraer hashtags (#palabra)
    for v_tag in select distinct lower(m[1]) from regexp_matches(new.contenido, '#([a-zA-Z0-9_]{2,50})', 'g') as m loop
      insert into public.hashtags (tag) values (v_tag) on conflict do nothing;
      insert into public.publicacion_hashtags (publicacion_id, tag)
      values (new.id, v_tag) on conflict do nothing;
    end loop;

    -- Extraer menciones (@usuario)
    for v_user in select distinct lower(m[1]) from regexp_matches(new.contenido, '@([a-zA-Z0-9_]{3,30})', 'g') as m loop
      select id into v_target_id from public.perfiles where username = v_user::public.citext;
      if v_target_id is not null and v_target_id <> new.autor_id then
        insert into public.menciones (publicacion_id, mencionado_id)
        values (new.id, v_target_id);

        insert into public.notificaciones (user_id, tipo, actor_id, entidad, entidad_id, texto)
        values (v_target_id, 'mencion', new.autor_id, 'publicacion', new.id::text, 'Te ha mencionado en una publicación.');
      end if;
    end loop;

    -- Incrementar contador de publicaciones del autor
    update public.perfiles
    set publicaciones_n = publicaciones_n + 1
    where id = new.autor_id;
  end if;

  return new;
end;
$$;

drop trigger if exists on_publicacion_aprobada_tags on public.publicaciones;
create trigger on_publicacion_aprobada_tags
  after insert or update of estado on public.publicaciones
  for each row execute function public.tr_publicacion_aprobada_extraer_tags();

-- -----------------------------------------------------------------------------
-- 4. Recálculo de Contadores (Me gusta, Comentarios, Seguidores)
-- -----------------------------------------------------------------------------
create or replace function public.tr_me_gusta_recalcular()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_pub_id uuid;
  v_autor_id uuid;
begin
  v_pub_id := coalesce(new.publicacion_id, old.publicacion_id);

  if tg_op = 'INSERT' then
    update public.publicaciones set me_gusta_n = me_gusta_n + 1 where id = v_pub_id;
    select autor_id into v_autor_id from public.publicaciones where id = v_pub_id;
    if v_autor_id is not null and v_autor_id <> new.user_id then
      insert into public.notificaciones (user_id, tipo, actor_id, entidad, entidad_id, texto)
      values (v_autor_id, 'me_gusta', new.user_id, 'publicacion', v_pub_id::text, 'Le ha gustado tu publicación.');
    end if;
  elsif tg_op = 'DELETE' then
    update public.publicaciones set me_gusta_n = greatest(0, me_gusta_n - 1) where id = v_pub_id;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists on_me_gusta_contador on public.me_gusta;
create trigger on_me_gusta_contador
  after insert or delete on public.me_gusta
  for each row execute function public.tr_me_gusta_recalcular();

create or replace function public.tr_comentario_recalcular()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_pub_id uuid;
  v_autor_id uuid;
begin
  v_pub_id := coalesce(new.publicacion_id, old.publicacion_id);

  if tg_op = 'INSERT' then
    update public.publicaciones set comentarios_n = comentarios_n + 1 where id = v_pub_id;
    select autor_id into v_autor_id from public.publicaciones where id = v_pub_id;
    if v_autor_id is not null and v_autor_id <> new.autor_id then
      insert into public.notificaciones (user_id, tipo, actor_id, entidad, entidad_id, texto)
      values (v_autor_id, 'comentario', new.autor_id, 'publicacion', v_pub_id::text, 'Ha comentado en tu publicación: ' || substr(new.contenido, 1, 50));
    end if;
  elsif tg_op = 'DELETE' then
    update public.publicaciones set comentarios_n = greatest(0, comentarios_n - 1) where id = v_pub_id;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists on_comentario_contador on public.comentarios;
create trigger on_comentario_contador
  after insert or delete on public.comentarios
  for each row execute function public.tr_comentario_recalcular();

create or replace function public.tr_seguidores_recalcular()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    update public.perfiles set siguiendo_n = siguiendo_n + 1 where id = new.seguidor_id;
    update public.perfiles set seguidores_n = seguidores_n + 1 where id = new.seguido_id;

    insert into public.notificaciones (user_id, tipo, actor_id, texto)
    values (new.seguido_id, 'nuevo_seguidor', new.seguidor_id, 'Ha comenzado a seguirte.');
  elsif tg_op = 'DELETE' then
    update public.perfiles set siguiendo_n = greatest(0, siguiendo_n - 1) where id = old.seguidor_id;
    update public.perfiles set seguidores_n = greatest(0, seguidores_n - 1) where id = old.seguido_id;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists on_seguidores_contador on public.seguidores;
create trigger on_seguidores_contador
  after insert or delete on public.seguidores
  for each row execute function public.tr_seguidores_recalcular();

-- -----------------------------------------------------------------------------
-- 5. Suspensión Automática de Insignia si cambia Datos Críticos
-- -----------------------------------------------------------------------------
create or replace function public.tr_perfil_suspender_insignia()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.insignia <> 'ninguna' and not old.insignia_suspendida then
    if (new.nombre <> old.nombre) or (new.username <> old.username) or
       (coalesce(new.avatar_path, '') <> coalesce(old.avatar_path, '')) then
      new.insignia_suspendida := true;

      -- Crear solicitud de revalidación
      insert into public.solicitudes_verificacion (
        user_id,
        insignia_solicitada,
        cargo,
        motivo,
        es_revalidacion
      ) values (
        new.id,
        old.insignia,
        coalesce(new.cargo_titulo, 'Revalidación'),
        'Revalidación automática por modificación de nombre o fotografía.',
        true
      );

      insert into public.notificaciones (user_id, tipo, texto)
      values (new.id, 'insignia_suspendida', 'Tu insignia fue suspendida temporalmente por cambio en tus datos de perfil. Se ha abierto una solicitud de revalidación.');
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_perfil_cambio_critico on public.perfiles;
create trigger on_perfil_cambio_critico
  before update of nombre, username, avatar_path on public.perfiles
  for each row execute function public.tr_perfil_suspender_insignia();
