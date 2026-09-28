-- =============================================================================
-- Migración 0014: Área en la que cada persona puede apoyar al movimiento
-- Se pregunta al registrarse. Es un dato privado: solo lo ven la persona (mi_perfil)
-- y los administradores (no se concede SELECT sobre estas columnas a anon/authenticated).
-- =============================================================================

alter table public.perfiles
  add column if not exists area_apoyo text,
  add column if not exists area_apoyo_otro text check (char_length(area_apoyo_otro) <= 120);

alter table public.perfiles drop constraint if exists perfiles_area_apoyo_check;
alter table public.perfiles add constraint perfiles_area_apoyo_check
  check (area_apoyo is null or area_apoyo in ('voluntariado_territorial','logistica_eventos','comunicaciones','diseno_audiovisual','tecnologia','politicas_publicas','juridico','formacion','defensa_voto','recoleccion_firmas','finanzas','liderazgo_comunitario','otro'));

create index if not exists perfiles_area_apoyo_idx on public.perfiles (area_apoyo);

-- Trigger de registro: guarda el área elegida en el formulario
CREATE OR REPLACE FUNCTION public.tr_crear_perfil_nuevo_usuario()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_area text;
  v_area_otro text;
  v_suffix integer := 1;
begin
  v_meta := coalesce(new.raw_user_meta_data, '{}'::jsonb);

  v_nombre := coalesce(nullif(trim(v_meta->>'nombre'), ''), split_part(new.email, '@', 1));
  v_base_username := lower(regexp_replace(coalesce(nullif(trim(v_meta->>'username'), ''), split_part(new.email, '@', 1)), '[^a-z0-9_]', '', 'g'));
  if length(v_base_username) < 3 then
    v_base_username := 'usuario_' || substr(md5(random()::text), 1, 6);
  end if;

  v_username := v_base_username;
  while exists (select 1 from public.perfiles where username = v_username::public.citext) loop
    v_username := substr(v_base_username, 1, 24) || '_' || v_suffix;
    v_suffix := v_suffix + 1;
  end loop;

  v_depto := nullif(trim(v_meta->>'departamento_id'), '');
  v_muni := nullif(trim(v_meta->>'municipio_id'), '');
  if nullif(trim(v_meta->>'localidad_id'), '') is not null then
    begin
      v_loc := (v_meta->>'localidad_id')::smallint;
    exception when others then
      v_loc := null;
    end;
  end if;

  if (v_meta->>'rol_solicitado') in ('simpatizante', 'voluntario', 'lider') then
    v_rol_solicitado := (v_meta->>'rol_solicitado')::public.rol_app;
  end if;

  v_motivo := v_meta->>'motivo';
  v_telefono := nullif(trim(v_meta->>'telefono'), '');
  v_ocupacion := nullif(trim(v_meta->>'ocupacion'), '');

  -- Área en la que la persona puede apoyar al movimiento
  v_area := nullif(trim(v_meta->>'area_apoyo'), '');
  if v_area is not null and v_area not in ('voluntariado_territorial','logistica_eventos','comunicaciones','diseno_audiovisual','tecnologia','politicas_publicas','juridico','formacion','defensa_voto','recoleccion_firmas','finanzas','liderazgo_comunitario','otro') then
    v_area := null;
  end if;
  v_area_otro := case when v_area = 'otro' then left(nullif(trim(v_meta->>'area_apoyo_otro'), ''), 120) end;

  -- Crear perfil
  insert into public.perfiles (
    id,
    nombre,
    username,
    departamento_id,
    municipio_id,
    localidad_id,
    ocupacion,
    area_apoyo,
    area_apoyo_otro,
    estado
  ) values (
    new.id,
    v_nombre,
    v_username::public.citext,
    v_depto,
    v_muni,
    v_loc,
    v_ocupacion,
    v_area,
    v_area_otro,
    'pendiente'::public.estado_cuenta
  );

  -- Perfil privado con teléfono
  if v_telefono is not null then
    insert into public.perfiles_privados (id, telefono)
    values (new.id, v_telefono);
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
  raise notice 'Error en trigger: %', SQLERRM;
  return new;
end;
$function$;

-- Listado de usuarios para el panel: incluye el área y permite filtrar por ella
drop function if exists public.admin_listar_usuarios(text, text, text, integer);
CREATE OR REPLACE FUNCTION public.admin_listar_usuarios(p_busqueda text DEFAULT NULL::text, p_depto text DEFAULT NULL::text, p_estado text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_area text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, nombre text, username text, correo text, telefono text, bio text, cargo_titulo text, ocupacion text, estado estado_cuenta, insignia insignia, departamento_id text, departamento text, municipio_id text, municipio text, roles jsonb, seguidores_n integer, publicaciones_n integer, notas_admin text, created_at timestamp with time zone, ultimo_ingreso timestamp with time zone, area_apoyo text, area_apoyo_otro text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido a administradores y moderadores.' using errcode = '42501';
  end if;
  return query
  select p.id, p.nombre, p.username::text, u.email::text, pp.telefono, p.bio, p.cargo_titulo,
         p.ocupacion, p.estado, p.insignia,
         p.departamento_id, d.nombre, p.municipio_id, m.nombre,
         coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'rol', r.rol, 'departamento_id', r.departamento_id, 'titulo', r.titulo) order by r.created_at)
                   from public.user_roles r where r.user_id = p.id and r.activo), '[]'::jsonb),
         p.seguidores_n, p.publicaciones_n, pp.notas_admin,
         p.created_at, u.last_sign_in_at, p.area_apoyo, p.area_apoyo_otro
  from public.perfiles p
  join auth.users u on u.id = p.id
  left join public.perfiles_privados pp on pp.id = p.id
  left join public.departamentos d on d.id = p.departamento_id
  left join public.municipios m on m.id = p.municipio_id
  where (public.puede_moderar(p.departamento_id))
    and (p_depto is null or p.departamento_id = p_depto)
    and (p_estado is null or p.estado::text = p_estado)
    and (p_area is null or p_area = '' or p.area_apoyo = p_area)
    and (p_busqueda is null or p_busqueda = ''
         or p.nombre ilike '%' || p_busqueda || '%'
         or p.username::text ilike '%' || p_busqueda || '%'
         or u.email ilike '%' || p_busqueda || '%')
  order by p.created_at desc
  limit least(coalesce(p_limite, 50), 200);
end;
$function$;
grant execute on function public.admin_listar_usuarios(text, text, text, integer, text) to authenticated;

-- Solicitudes de ingreso con el área de apoyo
drop function if exists public.admin_solicitudes_pendientes(text);
CREATE OR REPLACE FUNCTION public.admin_solicitudes_pendientes(p_depto text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, user_id uuid, rol_solicitado rol_app, motivo text, created_at timestamp with time zone, departamento_id text, departamento text, municipio text, nombre text, username text, correo text, ocupacion text, area_apoyo text, area_apoyo_otro text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query
  select s.id, s.user_id, s.rol_solicitado, s.motivo, s.created_at, s.departamento_id, d.nombre, m.nombre,
         p.nombre, p.username::text, u.email::text, p.ocupacion, p.area_apoyo, p.area_apoyo_otro
  from public.solicitudes s
  join public.perfiles p on p.id = s.user_id
  join auth.users u on u.id = s.user_id
  left join public.departamentos d on d.id = s.departamento_id
  left join public.municipios m on m.id = s.municipio_id
  where s.estado = 'pendiente' and public.puede_moderar(s.departamento_id)
    and (p_depto is null or s.departamento_id = p_depto)
  order by s.created_at;
end;
$function$;
grant execute on function public.admin_solicitudes_pendientes(text) to authenticated;

-- Los administradores pueden corregir el área de apoyo desde la ficha del usuario
create or replace function public.admin_actualizar_usuario(p_id uuid, p_datos jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_antes record;
begin
  perform public.exigir_mfa();
  select * into v_antes from public.perfiles where id = p_id for update;
  if not found then
    raise exception 'Usuario no encontrado.' using errcode = 'P0002';
  end if;
  if not public.es_admin_de(v_antes.departamento_id) then
    raise exception 'Solo administradores del territorio pueden editar este usuario.' using errcode = '42501';
  end if;
  if p_datos ? 'estado' and not (p_datos->>'estado' in ('pendiente', 'activo', 'rechazado', 'suspendido', 'baneado')) then
    raise exception 'Estado no válido.' using errcode = '22023';
  end if;
  -- Cambiar de departamento solo lo hace el admin nacional
  if p_datos ? 'departamento_id' and p_datos->>'departamento_id' is distinct from v_antes.departamento_id
     and not public.es_admin_nacional() then
    raise exception 'Solo el administrador nacional puede cambiar el departamento.' using errcode = '42501';
  end if;

  update public.perfiles set
    nombre          = coalesce(nullif(btrim(p_datos->>'nombre'), ''), nombre),
    bio             = case when p_datos ? 'bio' then nullif(btrim(p_datos->>'bio'), '') else bio end,
    cargo_titulo    = case when p_datos ? 'cargo_titulo' then nullif(btrim(p_datos->>'cargo_titulo'), '') else cargo_titulo end,
    ocupacion       = case when p_datos ? 'ocupacion' then nullif(btrim(p_datos->>'ocupacion'), '') else ocupacion end,
    estado          = coalesce((p_datos->>'estado')::public.estado_cuenta, estado),
    departamento_id = case when p_datos ? 'departamento_id' then p_datos->>'departamento_id' else departamento_id end,
    municipio_id    = case when p_datos ? 'municipio_id' then p_datos->>'municipio_id' else municipio_id end,
    area_apoyo      = case when p_datos ? 'area_apoyo' then nullif(p_datos->>'area_apoyo', '') else area_apoyo end,
    area_apoyo_otro = case when p_datos ? 'area_apoyo' then
                        case when p_datos->>'area_apoyo' = 'otro' then left(nullif(btrim(p_datos->>'area_apoyo_otro'), ''), 120) end
                      else area_apoyo_otro end,
    updated_at      = now()
  where id = p_id;

  if p_datos ? 'telefono' or p_datos ? 'notas_admin' then
    insert into public.perfiles_privados (id, telefono, notas_admin)
    values (p_id, nullif(p_datos->>'telefono', ''), nullif(p_datos->>'notas_admin', ''))
    on conflict (id) do update set
      telefono = case when p_datos ? 'telefono' then excluded.telefono else public.perfiles_privados.telefono end,
      notas_admin = case when p_datos ? 'notas_admin' then excluded.notas_admin else public.perfiles_privados.notas_admin end;
  end if;

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, antes, despues)
  values (auth.uid(), 'actualizar_usuario', 'perfil', p_id::text, v_antes.departamento_id,
          to_jsonb(v_antes), p_datos - 'notas_admin');
  return true;
end;
$$;
