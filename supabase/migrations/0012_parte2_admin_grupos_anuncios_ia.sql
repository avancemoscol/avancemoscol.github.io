-- =============================================================================
-- Migración 0012 (parte 2): administración, grupos, eventos, anuncios/encuestas,
-- límites de uso de IA y soporte de audio
-- =============================================================================

-- Moderador o admin de cualquier territorio
create or replace function public.es_moderador_alguno()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin_nacional() or exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.activo
      and ur.rol in ('admin_departamental'::public.rol_app, 'moderador'::public.rol_app));
$$;
grant execute on function public.es_moderador_alguno() to authenticated;

-- -----------------------------------------------------------------------------
-- 1. Gestión de usuarios por administradores
-- -----------------------------------------------------------------------------
create or replace function public.admin_listar_usuarios(p_busqueda text default null, p_depto text default null, p_estado text default null, p_limite integer default 50)
returns table (
  id uuid, nombre text, username text, correo text, telefono text, bio text, cargo_titulo text,
  ocupacion text, estado public.estado_cuenta, insignia public.insignia,
  departamento_id text, departamento text, municipio_id text, municipio text,
  roles jsonb, seguidores_n integer, publicaciones_n integer, notas_admin text,
  created_at timestamptz, ultimo_ingreso timestamptz
) language plpgsql stable security definer set search_path = '' as $$
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
         p.created_at, u.last_sign_in_at
  from public.perfiles p
  join auth.users u on u.id = p.id
  left join public.perfiles_privados pp on pp.id = p.id
  left join public.departamentos d on d.id = p.departamento_id
  left join public.municipios m on m.id = p.municipio_id
  where (public.puede_moderar(p.departamento_id))
    and (p_depto is null or p.departamento_id = p_depto)
    and (p_estado is null or p.estado::text = p_estado)
    and (p_busqueda is null or p_busqueda = ''
         or p.nombre ilike '%' || p_busqueda || '%'
         or p.username::text ilike '%' || p_busqueda || '%'
         or u.email ilike '%' || p_busqueda || '%')
  order by p.created_at desc
  limit least(coalesce(p_limite, 50), 200);
end;
$$;
grant execute on function public.admin_listar_usuarios(text, text, text, integer) to authenticated;

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
grant execute on function public.admin_actualizar_usuario(uuid, jsonb) to authenticated;

create or replace function public.admin_asignar_rol(p_user_id uuid, p_rol public.rol_app, p_departamento_id text default null, p_titulo text default null, p_activo boolean default true)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_depto_usuario text;
begin
  perform public.exigir_mfa();
  select departamento_id into v_depto_usuario from public.perfiles where id = p_user_id;
  if not found then
    raise exception 'Usuario no encontrado.' using errcode = 'P0002';
  end if;
  -- Roles de administración solo los otorga el admin nacional
  if p_rol in ('admin_nacional', 'admin_departamental') and not public.es_admin_nacional() then
    raise exception 'Solo el administrador nacional puede otorgar roles de administración.' using errcode = '42501';
  end if;
  if not public.es_admin_de(coalesce(p_departamento_id, v_depto_usuario)) then
    raise exception 'No tienes permisos para asignar roles en este territorio.' using errcode = '42501';
  end if;
  if p_rol in ('moderador', 'admin_departamental') and p_departamento_id is null then
    raise exception 'Los roles de moderador y admin departamental requieren un departamento.' using errcode = '22023';
  end if;

  if p_activo then
    -- La restricción única no aplica con departamento NULL, por eso se actualiza primero
    update public.user_roles set activo = true, titulo = nullif(btrim(p_titulo), ''), otorgado_por = auth.uid()
    where user_id = p_user_id and rol = p_rol and departamento_id is not distinct from p_departamento_id and municipio_id is null;
    if not found then
      insert into public.user_roles (user_id, rol, departamento_id, titulo, activo, otorgado_por)
      values (p_user_id, p_rol, p_departamento_id, nullif(btrim(p_titulo), ''), true, auth.uid());
    end if;
  else
    update public.user_roles set activo = false
    where user_id = p_user_id and rol = p_rol and departamento_id is not distinct from p_departamento_id;
  end if;

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, despues)
  values (auth.uid(), case when p_activo then 'asignar_rol' else 'quitar_rol' end, 'perfil', p_user_id::text,
          coalesce(p_departamento_id, v_depto_usuario), jsonb_build_object('rol', p_rol, 'departamento_id', p_departamento_id, 'titulo', p_titulo));
  return true;
end;
$$;
grant execute on function public.admin_asignar_rol(uuid, public.rol_app, text, text, boolean) to authenticated;

-- Solicitudes pendientes con nombre completo (solo moderadores)
create or replace function public.admin_solicitudes_pendientes(p_depto text default null)
returns table (id uuid, user_id uuid, rol_solicitado public.rol_app, motivo text, created_at timestamptz,
               departamento_id text, departamento text, municipio text, nombre text, username text, correo text, ocupacion text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query
  select s.id, s.user_id, s.rol_solicitado, s.motivo, s.created_at, s.departamento_id, d.nombre, m.nombre,
         p.nombre, p.username::text, u.email::text, p.ocupacion
  from public.solicitudes s
  join public.perfiles p on p.id = s.user_id
  join auth.users u on u.id = s.user_id
  left join public.departamentos d on d.id = s.departamento_id
  left join public.municipios m on m.id = s.municipio_id
  where s.estado = 'pendiente' and public.puede_moderar(s.departamento_id)
    and (p_depto is null or s.departamento_id = p_depto)
  order by s.created_at;
end;
$$;
grant execute on function public.admin_solicitudes_pendientes(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Publicaciones y comentarios para administradores (todas, con autor completo)
-- -----------------------------------------------------------------------------
create or replace function public.admin_publicaciones(p_estado text default null, p_depto text default null, p_busqueda text default null, p_limite integer default 50)
returns table (
  id uuid, autor_id uuid, autor_nombre text, autor_username text, autor_avatar text, autor_insignia public.insignia,
  autor_cargo text, contenido text, categoria text, alcance public.alcance, visibilidad public.visibilidad,
  estado public.estado_revision, motivo_revision text, departamento text, created_at timestamptz,
  publicado_en timestamptz, eliminado_en timestamptz, me_gusta_n integer, comentarios_n integer, media jsonb
) language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query
  select p.id, p.autor_id, pf.nombre, pf.username::text, pf.avatar_path, pf.insignia, pf.cargo_titulo,
         p.contenido, p.categoria, p.alcance, p.visibilidad, p.estado, p.motivo_revision, d.nombre,
         p.created_at, p.publicado_en, p.eliminado_en, p.me_gusta_n, p.comentarios_n,
         coalesce((select jsonb_agg(jsonb_build_object('id', pm.id, 'tipo', pm.tipo, 'path', pm.path, 'bucket', pm.bucket) order by pm.orden)
                   from public.publicacion_media pm where pm.publicacion_id = p.id), '[]'::jsonb)
  from public.publicaciones p
  join public.perfiles pf on pf.id = p.autor_id
  left join public.departamentos d on d.id = p.departamento_id
  where public.puede_moderar(p.departamento_moderacion)
    and (p_estado is null or p_estado = '' or (p_estado = 'eliminada' and p.eliminado_en is not null)
         or (p_estado <> 'eliminada' and p.estado::text = p_estado and p.eliminado_en is null))
    and (p_depto is null or p.departamento_id = p_depto)
    and (p_busqueda is null or p_busqueda = '' or p.contenido ilike '%' || p_busqueda || '%' or pf.username::text ilike '%' || p_busqueda || '%')
  order by p.created_at desc
  limit least(coalesce(p_limite, 50), 200);
end;
$$;
grant execute on function public.admin_publicaciones(text, text, text, integer) to authenticated;

create or replace function public.admin_comentarios(p_publicacion_id uuid)
returns table (id uuid, contenido text, estado text, created_at timestamptz, autor_id uuid, autor_nombre text, autor_username text, autor_insignia public.insignia)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.publicaciones p where p.id = p_publicacion_id and public.puede_moderar(p.departamento_moderacion)) then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query
  select c.id, c.contenido, c.estado, c.created_at, c.autor_id, pf.nombre, pf.username::text, pf.insignia
  from public.comentarios c join public.perfiles pf on pf.id = c.autor_id
  where c.publicacion_id = p_publicacion_id
  order by c.created_at;
end;
$$;
grant execute on function public.admin_comentarios(uuid) to authenticated;

create or replace function public.admin_moderar_comentario(p_id uuid, p_estado text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_dep text;
begin
  if p_estado not in ('visible', 'oculto', 'eliminado') then
    raise exception 'Estado no válido.' using errcode = '22023';
  end if;
  select p.departamento_moderacion into v_dep
  from public.comentarios c join public.publicaciones p on p.id = c.publicacion_id where c.id = p_id;
  if not found or not public.puede_moderar(v_dep) then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  update public.comentarios set estado = p_estado where id = p_id;
  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, despues)
  values (auth.uid(), 'moderar_comentario', 'comentario', p_id::text, v_dep, jsonb_build_object('estado', p_estado));
  return true;
end;
$$;
grant execute on function public.admin_moderar_comentario(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Grupos: WhatsApp, Telegram y Discord, visibles para todos cuando están aprobados
-- -----------------------------------------------------------------------------
alter table public.grupos_whatsapp drop constraint if exists grupos_whatsapp_url_check;
alter table public.grupos_whatsapp add constraint grupos_whatsapp_url_check check (
  url ~ '^https://chat\.whatsapp\.com/[A-Za-z0-9]{20,24}$' or
  url ~ '^https://(www\.)?whatsapp\.com/channel/[A-Za-z0-9]+$' or
  url ~ '^https://t\.me/\+?[A-Za-z0-9_-]+$' or
  url ~ '^https://discord\.gg/[A-Za-z0-9]+$'
);
alter table public.grupos_whatsapp add column if not exists plataforma text not null default 'whatsapp'
  check (plataforma in ('whatsapp', 'telegram', 'discord'));
alter table public.grupos_whatsapp add column if not exists orden smallint not null default 100;

drop policy if exists "ver_grupos_whatsapp" on public.grupos_whatsapp;
create policy "ver_grupos_whatsapp" on public.grupos_whatsapp for select using (
  estado = 'aprobado'
  or creado_por = (select auth.uid())
  or (select public.puede_moderar(grupos_whatsapp.departamento_moderacion))
);

-- Carga de los grupos oficiales publicados en beacons.ai/avancemoscol
do $$
declare v_admin uuid;
begin
  select id into v_admin from auth.users where email = 'admin@avancemos.co';
  if v_admin is null then
    select user_id into v_admin from public.user_roles where rol = 'admin_nacional' and activo limit 1;
  end if;
  if v_admin is null then return; end if;

  insert into public.grupos_whatsapp (nombre, descripcion, tipo, tema, alcance, departamento_id, departamento_moderacion, url, plataforma, orden, creado_por, estado, revisado_por, revisado_en)
  select g.nombre, g.descripcion, g.tipo, g.tema, g.alcance::public.alcance, g.depto, g.depto, g.url, g.plataforma, g.orden, v_admin, 'aprobado', v_admin, now()
  from (values
    ('Comunidad Avancemos en Discord', 'Espacio nacional de conversación, foros por temas y coordinación de voluntariado.', 'comunidad', 'nacional', 'nacional', null, 'https://discord.gg/bwgtzu4Vnb', 'discord', 1),
    ('Canal Avancemos en Telegram', 'Canal nacional de noticias y convocatorias del movimiento.', 'canal', 'nacional', 'nacional', null, 'https://t.me/+OAEKucZTUzFlY2Ux', 'telegram', 2),
    ('Avancemos Internacional', 'Grupo para colombianos y colombianas en el exterior.', 'grupo', 'internacional', 'nacional', null, 'https://chat.whatsapp.com/Hx82zqfGfpTKrE7wwTDd7J', 'whatsapp', 3),
    ('Avancemos Amazonas', null, 'grupo', 'general', 'departamental', '91', 'https://chat.whatsapp.com/EvHDDS6yPWA11e3wyRw7gS', 'whatsapp', 100),
    ('Avancemos Antioquia', null, 'grupo', 'general', 'departamental', '05', 'https://chat.whatsapp.com/I58ZvkU6i8hI1f7ABRTx9l', 'whatsapp', 100),
    ('Avancemos Arauca', null, 'grupo', 'general', 'departamental', '81', 'https://chat.whatsapp.com/HyDhbtZIZAb1Bptewy0TZo', 'whatsapp', 100),
    ('Avancemos Atlántico', null, 'grupo', 'general', 'departamental', '08', 'https://chat.whatsapp.com/BXIWeqnrKuNDlMSRvYrfgV', 'whatsapp', 100),
    ('Avancemos Bogotá D. C.', null, 'grupo', 'general', 'departamental', '11', 'https://chat.whatsapp.com/HJLj09wYfQyKoFoHQ5pB3R', 'whatsapp', 100),
    ('Avancemos Bolívar', null, 'grupo', 'general', 'departamental', '13', 'https://chat.whatsapp.com/CWursusuYDaFmeAVvsJRvP', 'whatsapp', 100),
    ('Avancemos Boyacá', null, 'grupo', 'general', 'departamental', '15', 'https://chat.whatsapp.com/H4ZUSv5Sh2lHpImKCizfAe', 'whatsapp', 100),
    ('Avancemos Caldas', null, 'grupo', 'general', 'departamental', '17', 'https://chat.whatsapp.com/Kl0sqDHWBgLEmS4aFaHXEV', 'whatsapp', 100),
    ('Avancemos Caquetá', null, 'grupo', 'general', 'departamental', '18', 'https://chat.whatsapp.com/G8K6ONSi9YIHXdNhUG5xev', 'whatsapp', 100),
    ('Avancemos Casanare', null, 'grupo', 'general', 'departamental', '85', 'https://chat.whatsapp.com/HooU4tRhnEf2tNJQ9LWDxJ', 'whatsapp', 100),
    ('Avancemos Cauca', null, 'grupo', 'general', 'departamental', '19', 'https://chat.whatsapp.com/Dh8qFX78vHLIlE5Yk5rBZ7', 'whatsapp', 100),
    ('Avancemos Cesar', null, 'grupo', 'general', 'departamental', '20', 'https://chat.whatsapp.com/D4r8YBvgFZSBIDanW5pwbu', 'whatsapp', 100),
    ('Avancemos Chocó', null, 'grupo', 'general', 'departamental', '27', 'https://chat.whatsapp.com/Hsjdde3yXZI74pJbbtidDC', 'whatsapp', 100),
    ('Avancemos Córdoba', null, 'grupo', 'general', 'departamental', '23', 'https://chat.whatsapp.com/LHX7quOngSGKbVsJRTgRZK', 'whatsapp', 100),
    ('Avancemos Cundinamarca', null, 'grupo', 'general', 'departamental', '25', 'https://chat.whatsapp.com/IiccFaAf9AlGdxomp5SgxB', 'whatsapp', 100),
    ('Avancemos Guainía', null, 'grupo', 'general', 'departamental', '94', 'https://chat.whatsapp.com/JzpCzrk2hun9mWz98YEiRh', 'whatsapp', 100),
    ('Avancemos Guaviare', null, 'grupo', 'general', 'departamental', '95', 'https://chat.whatsapp.com/Ez8o30v8Peh38jKhvGmCf5', 'whatsapp', 100),
    ('Avancemos Huila', null, 'grupo', 'general', 'departamental', '41', 'https://chat.whatsapp.com/GJ5zlWe2exG7c0LTPgFDQL', 'whatsapp', 100),
    ('Avancemos La Guajira', null, 'grupo', 'general', 'departamental', '44', 'https://chat.whatsapp.com/FjPgCmbxuZWJroHXWHaaDf', 'whatsapp', 100),
    ('Avancemos Magdalena', null, 'grupo', 'general', 'departamental', '47', 'https://chat.whatsapp.com/KZrIvuNixIb6mqRDWXlQgy', 'whatsapp', 100),
    ('Avancemos Meta', null, 'grupo', 'general', 'departamental', '50', 'https://chat.whatsapp.com/CiXmO8ny1CMECxeO1vXq17', 'whatsapp', 100),
    ('Avancemos Nariño', null, 'grupo', 'general', 'departamental', '52', 'https://chat.whatsapp.com/FjizqiaC08rB8G5JwTlvhi', 'whatsapp', 100),
    ('Avancemos Norte de Santander', null, 'grupo', 'general', 'departamental', '54', 'https://chat.whatsapp.com/Gcl1ICWEgLnHCHv0s2s4FJ', 'whatsapp', 100),
    ('Avancemos Putumayo', null, 'grupo', 'general', 'departamental', '86', 'https://chat.whatsapp.com/JR9Zly9cONVHPzKcQyS8wn', 'whatsapp', 100),
    ('Avancemos Quindío', null, 'grupo', 'general', 'departamental', '63', 'https://chat.whatsapp.com/BbI29dRPPHU4Xhurzbu6Am', 'whatsapp', 100),
    ('Avancemos Risaralda', null, 'grupo', 'general', 'departamental', '66', 'https://chat.whatsapp.com/L9KZ74blyInHycJRyU6cDd', 'whatsapp', 100),
    ('Avancemos San Andrés y Providencia', null, 'grupo', 'general', 'departamental', '88', 'https://chat.whatsapp.com/L4LxINDCjSM87JrH9FE6XR', 'whatsapp', 100),
    ('Avancemos Santander', null, 'grupo', 'general', 'departamental', '68', 'https://chat.whatsapp.com/KYETbj1aJlW1esMimiHB7D', 'whatsapp', 100),
    ('Avancemos Sucre', null, 'grupo', 'general', 'departamental', '70', 'https://chat.whatsapp.com/KxDsW4HboFZ73RzruhcSXk', 'whatsapp', 100),
    ('Avancemos Tolima', null, 'grupo', 'general', 'departamental', '73', 'https://chat.whatsapp.com/IJrxB375vbF6ZFuC6xz0Jo', 'whatsapp', 100),
    ('Avancemos Valle del Cauca', null, 'grupo', 'general', 'departamental', '76', 'https://chat.whatsapp.com/CsdR4bMAQje5biWcDz5FSw', 'whatsapp', 100),
    ('Avancemos Vaupés', null, 'grupo', 'general', 'departamental', '97', 'https://chat.whatsapp.com/Ertk25XihND5LpdUVqqOC2', 'whatsapp', 100),
    ('Avancemos Vichada', null, 'grupo', 'general', 'departamental', '99', 'https://chat.whatsapp.com/C8U0A3ccM8bJKCQZ6UuWbe', 'whatsapp', 100)
  ) as g(nombre, descripcion, tipo, tema, alcance, depto, url, plataforma, orden)
  on conflict (url) do nothing;
end $$;

-- Crear o editar grupos directamente desde el panel (aprobados)
create or replace function public.admin_guardar_grupo(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_depto text := nullif(p_datos->>'departamento_id', '');
begin
  if not public.es_admin_de(v_depto) then
    raise exception 'No tienes permisos para gestionar grupos en este territorio.' using errcode = '42501';
  end if;
  insert into public.grupos_whatsapp (id, nombre, descripcion, tipo, tema, alcance, departamento_id, departamento_moderacion, url, plataforma, orden, creado_por, estado, revisado_por, revisado_en)
  values (v_id, btrim(p_datos->>'nombre'), nullif(btrim(p_datos->>'descripcion'), ''), coalesce(p_datos->>'tipo', 'grupo'),
          coalesce(p_datos->>'tema', 'general'), case when v_depto is null then 'nacional' else 'departamental' end::public.alcance,
          v_depto, v_depto, btrim(p_datos->>'url'), coalesce(p_datos->>'plataforma', 'whatsapp'),
          coalesce((p_datos->>'orden')::smallint, 100), auth.uid(), 'aprobado', auth.uid(), now())
  on conflict (id) do update set
    nombre = excluded.nombre, descripcion = excluded.descripcion, tipo = excluded.tipo, tema = excluded.tema,
    alcance = excluded.alcance, departamento_id = excluded.departamento_id, departamento_moderacion = excluded.departamento_moderacion,
    url = excluded.url, plataforma = excluded.plataforma, orden = excluded.orden;
  return v_id;
end;
$$;
grant execute on function public.admin_guardar_grupo(uuid, jsonb) to authenticated;

create or replace function public.admin_eliminar_grupo(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_dep text;
begin
  select departamento_moderacion into v_dep from public.grupos_whatsapp where id = p_id;
  if not found or not public.es_admin_de(v_dep) then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  delete from public.grupos_whatsapp where id = p_id;
  return true;
end;
$$;
grant execute on function public.admin_eliminar_grupo(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Eventos creados por administradores (quedan aprobados)
-- -----------------------------------------------------------------------------
create or replace function public.admin_guardar_evento(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_depto text := nullif(p_datos->>'departamento_id', '');
begin
  if not public.es_admin_de(v_depto) then
    raise exception 'No tienes permisos para crear eventos en este territorio.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_datos->>'titulo'), '') = '' or (p_datos->>'inicio') is null then
    raise exception 'El evento necesita título y fecha de inicio.' using errcode = '22023';
  end if;

  insert into public.eventos (id, titulo, descripcion, tipo, inicio, fin, modalidad, lugar, direccion, url_virtual, cupo,
                              imagen_path, alcance, departamento_id, departamento_moderacion, visibilidad, organizador_id,
                              estado, revisado_por, revisado_en)
  values (v_id, btrim(p_datos->>'titulo'), coalesce(nullif(btrim(p_datos->>'descripcion'), ''), btrim(p_datos->>'titulo')),
          coalesce(p_datos->>'tipo', 'reunion'), (p_datos->>'inicio')::timestamptz, nullif(p_datos->>'fin', '')::timestamptz,
          coalesce(p_datos->>'modalidad', 'presencial'), nullif(p_datos->>'lugar', ''), nullif(p_datos->>'direccion', ''),
          nullif(p_datos->>'url_virtual', ''), nullif(p_datos->>'cupo', '')::integer, nullif(p_datos->>'imagen_path', ''),
          case when v_depto is null then 'nacional' else 'departamental' end::public.alcance, v_depto, v_depto,
          coalesce(p_datos->>'visibilidad', 'publica')::public.visibilidad, auth.uid(), 'aprobado', auth.uid(), now())
  on conflict (id) do update set
    titulo = excluded.titulo, descripcion = excluded.descripcion, tipo = excluded.tipo, inicio = excluded.inicio,
    fin = excluded.fin, modalidad = excluded.modalidad, lugar = excluded.lugar, direccion = excluded.direccion,
    url_virtual = excluded.url_virtual, cupo = excluded.cupo, imagen_path = excluded.imagen_path,
    alcance = excluded.alcance, departamento_id = excluded.departamento_id,
    departamento_moderacion = excluded.departamento_moderacion, visibilidad = excluded.visibilidad;
  return v_id;
end;
$$;
grant execute on function public.admin_guardar_evento(uuid, jsonb) to authenticated;

create or replace function public.admin_resolver_evento(p_id uuid, p_accion text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_dep text;
begin
  select departamento_moderacion into v_dep from public.eventos where id = p_id;
  if not found or not public.puede_moderar(v_dep) then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  if p_accion = 'eliminar' then
    delete from public.eventos where id = p_id;
  elsif p_accion in ('aprobado', 'rechazado') then
    update public.eventos set estado = p_accion::public.estado_revision, revisado_por = auth.uid(), revisado_en = now() where id = p_id;
  else
    raise exception 'Acción no válida.' using errcode = '22023';
  end if;
  return true;
end;
$$;
grant execute on function public.admin_resolver_evento(uuid, text) to authenticated;

create or replace function public.admin_eventos()
returns setof public.eventos language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query select * from public.eventos e where public.puede_moderar(e.departamento_moderacion) order by e.inicio desc limit 200;
end;
$$;
grant execute on function public.admin_eventos() to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Anuncios: comunicados, encuestas y votaciones (con imagen, video o audio)
-- -----------------------------------------------------------------------------
alter table public.anuncios
  add column if not exists tipo text not null default 'comunicado' check (tipo in ('comunicado', 'encuesta', 'votacion')),
  add column if not exists opciones jsonb not null default '[]'::jsonb,
  add column if not exists multiple boolean not null default false,
  add column if not exists permite_comentario boolean not null default false,
  add column if not exists obligatorio boolean not null default false,
  add column if not exists mostrar_resultados boolean not null default true,
  add column if not exists media jsonb not null default '[]'::jsonb,
  add column if not exists activo boolean not null default true,
  add column if not exists inicia_en timestamptz not null default now(),
  add column if not exists termina_en timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.anuncio_respuestas (
  anuncio_id uuid not null references public.anuncios(id) on delete cascade,
  user_id uuid not null references public.perfiles(id) on delete cascade,
  opciones smallint[] not null default '{}',
  comentario text check (char_length(comentario) <= 500),
  created_at timestamptz not null default now(),
  primary key (anuncio_id, user_id)
);
alter table public.anuncio_respuestas enable row level security;
drop policy if exists "ver_propias_respuestas" on public.anuncio_respuestas;
create policy "ver_propias_respuestas" on public.anuncio_respuestas for select using (user_id = (select auth.uid()));

-- Los anuncios se leen por RPC (para respetar vigencia y audiencia)
drop policy if exists "ver_anuncios" on public.anuncios;
create policy "ver_anuncios" on public.anuncios for select using (
  activo and inicia_en <= now() and (termina_en is null or termina_en > now())
);

create or replace function public.anuncios_pendientes()
returns table (id uuid, tipo text, titulo text, cuerpo text, opciones jsonb, multiple boolean, permite_comentario boolean,
               obligatorio boolean, media jsonb, termina_en timestamptz, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id, a.tipo, a.titulo, a.cuerpo, a.opciones, a.multiple, a.permite_comentario, a.obligatorio, a.media, a.termina_en, a.created_at
  from public.anuncios a
  join public.perfiles yo on yo.id = auth.uid()
  where a.activo and a.inicia_en <= now() and (a.termina_en is null or a.termina_en > now())
    and (a.departamento_id is null or a.departamento_id = yo.departamento_id)
    and not exists (select 1 from public.anuncio_respuestas r where r.anuncio_id = a.id and r.user_id = yo.id)
  order by a.obligatorio desc, a.created_at;
$$;
grant execute on function public.anuncios_pendientes() to authenticated;

create or replace function public.responder_anuncio(p_anuncio_id uuid, p_opciones smallint[] default '{}', p_comentario text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_a record;
  v_n int := coalesce(array_length(p_opciones, 1), 0);
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  select * into v_a from public.anuncios where id = p_anuncio_id and activo
    and inicia_en <= now() and (termina_en is null or termina_en > now());
  if not found then
    raise exception 'Este anuncio ya no está disponible.' using errcode = 'P0002';
  end if;
  if v_a.tipo in ('encuesta', 'votacion') then
    if v_n = 0 then
      raise exception 'Debes elegir una opción.' using errcode = '22023';
    end if;
    if v_n > 1 and not (v_a.tipo = 'encuesta' and v_a.multiple) then
      raise exception 'Solo puedes elegir una opción.' using errcode = '22023';
    end if;
    if exists (select 1 from unnest(p_opciones) o where o < 0 or o >= jsonb_array_length(v_a.opciones)) then
      raise exception 'Opción no válida.' using errcode = '22023';
    end if;
  end if;

  insert into public.anuncio_respuestas (anuncio_id, user_id, opciones, comentario)
  values (p_anuncio_id, auth.uid(), coalesce(p_opciones, '{}'),
          case when v_a.permite_comentario then nullif(btrim(p_comentario), '') else null end)
  on conflict (anuncio_id, user_id) do nothing;
  return true;
end;
$$;
grant execute on function public.responder_anuncio(uuid, smallint[], text) to authenticated;

-- Resultados: admins siempre; usuarios solo si ya respondieron y el anuncio los muestra
create or replace function public.resultados_anuncio(p_anuncio_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_a record;
  v_total int;
begin
  select * into v_a from public.anuncios where id = p_anuncio_id;
  if not found then return null; end if;
  if not (public.es_admin_de(v_a.departamento_id)
          or (v_a.mostrar_resultados and exists (select 1 from public.anuncio_respuestas r where r.anuncio_id = p_anuncio_id and r.user_id = auth.uid()))) then
    raise exception 'Resultados no disponibles.' using errcode = '42501';
  end if;
  select count(*) into v_total from public.anuncio_respuestas where anuncio_id = p_anuncio_id;
  return jsonb_build_object(
    'total', v_total,
    'opciones', coalesce((
      select jsonb_agg(jsonb_build_object('indice', i - 1, 'texto', o.val->>'texto',
             'votos', (select count(*) from public.anuncio_respuestas r where r.anuncio_id = p_anuncio_id and (i - 1)::smallint = any (r.opciones)))
             order by i)
      from jsonb_array_elements(v_a.opciones) with ordinality as o(val, i)
    ), '[]'::jsonb),
    'comentarios', case when public.es_admin_de(v_a.departamento_id) then coalesce((
      select jsonb_agg(r.comentario order by r.created_at desc) from public.anuncio_respuestas r
      where r.anuncio_id = p_anuncio_id and r.comentario is not null), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;
grant execute on function public.resultados_anuncio(uuid) to authenticated;

create or replace function public.admin_anuncios()
returns table (id uuid, tipo text, titulo text, cuerpo text, opciones jsonb, multiple boolean, permite_comentario boolean,
               obligatorio boolean, mostrar_resultados boolean, media jsonb, activo boolean, inicia_en timestamptz,
               termina_en timestamptz, departamento_id text, respuestas bigint, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query
  select a.id, a.tipo, a.titulo, a.cuerpo, a.opciones, a.multiple, a.permite_comentario, a.obligatorio, a.mostrar_resultados,
         a.media, a.activo, a.inicia_en, a.termina_en, a.departamento_id,
         (select count(*) from public.anuncio_respuestas r where r.anuncio_id = a.id), a.created_at
  from public.anuncios a
  where public.puede_moderar(a.departamento_id) or public.es_admin_nacional()
  order by a.created_at desc;
end;
$$;
grant execute on function public.admin_anuncios() to authenticated;

create or replace function public.admin_guardar_anuncio(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_depto text := nullif(p_datos->>'departamento_id', '');
  v_tipo text := coalesce(p_datos->>'tipo', 'comunicado');
  v_opciones jsonb := coalesce(p_datos->'opciones', '[]'::jsonb);
begin
  if not public.es_admin_de(v_depto) then
    raise exception 'Solo administradores pueden publicar anuncios en este territorio.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_datos->>'titulo'), '') = '' then
    raise exception 'El anuncio necesita un título.' using errcode = '22023';
  end if;
  if v_tipo in ('encuesta', 'votacion') and jsonb_array_length(v_opciones) < 2 then
    raise exception 'Las encuestas y votaciones necesitan al menos 2 opciones.' using errcode = '22023';
  end if;
  -- Una vez hay respuestas no se pueden cambiar las opciones (alteraría los resultados)
  if p_id is not null and exists (select 1 from public.anuncio_respuestas where anuncio_id = p_id)
     and (select opciones from public.anuncios where id = p_id) is distinct from v_opciones then
    raise exception 'Este anuncio ya tiene respuestas: no se pueden cambiar las opciones.' using errcode = '22023';
  end if;

  insert into public.anuncios (id, autor_id, titulo, cuerpo, departamento_id, tipo, opciones, multiple, permite_comentario,
                               obligatorio, mostrar_resultados, media, activo, inicia_en, termina_en, updated_at)
  values (v_id, auth.uid(), btrim(p_datos->>'titulo'), coalesce(p_datos->>'cuerpo', ''), v_depto, v_tipo, v_opciones,
          coalesce((p_datos->>'multiple')::boolean, false), coalesce((p_datos->>'permite_comentario')::boolean, false),
          coalesce((p_datos->>'obligatorio')::boolean, false), coalesce((p_datos->>'mostrar_resultados')::boolean, true),
          coalesce(p_datos->'media', '[]'::jsonb), coalesce((p_datos->>'activo')::boolean, true),
          coalesce(nullif(p_datos->>'inicia_en', '')::timestamptz, now()), nullif(p_datos->>'termina_en', '')::timestamptz, now())
  on conflict (id) do update set
    titulo = excluded.titulo, cuerpo = excluded.cuerpo, departamento_id = excluded.departamento_id, tipo = excluded.tipo,
    opciones = excluded.opciones, multiple = excluded.multiple, permite_comentario = excluded.permite_comentario,
    obligatorio = excluded.obligatorio, mostrar_resultados = excluded.mostrar_resultados, media = excluded.media,
    activo = excluded.activo, inicia_en = excluded.inicia_en, termina_en = excluded.termina_en, updated_at = now();

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, departamento_id, despues)
  values (auth.uid(), case when p_id is null then 'crear_anuncio' else 'editar_anuncio' end, 'anuncio', v_id::text, v_depto,
          jsonb_build_object('tipo', v_tipo, 'titulo', p_datos->>'titulo'));
  return v_id;
end;
$$;
grant execute on function public.admin_guardar_anuncio(uuid, jsonb) to authenticated;

create or replace function public.admin_eliminar_anuncio(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_dep text;
begin
  select departamento_id into v_dep from public.anuncios where id = p_id;
  if not found or not public.es_admin_de(v_dep) then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  delete from public.anuncios where id = p_id;
  return true;
end;
$$;
grant execute on function public.admin_eliminar_anuncio(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Límites de uso del asistente de IA (lo usa la Edge Function con service_role)
-- -----------------------------------------------------------------------------
create table if not exists public.uso_ia (
  clave text not null,           -- 'u:<user_id>' o 'ip:<hash>'
  dia date not null default (now() at time zone 'America/Bogota')::date,
  conteo integer not null default 0,
  primary key (clave, dia)
);
alter table public.uso_ia enable row level security;  -- sin políticas: solo service_role

create or replace function public.consumir_uso_ia(p_clave text, p_limite integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_dia date := (now() at time zone 'America/Bogota')::date;
  v_conteo integer;
begin
  insert into public.uso_ia (clave, dia, conteo) values (p_clave, v_dia, 1)
  on conflict (clave, dia) do update set conteo = public.uso_ia.conteo + 1
  where public.uso_ia.conteo < p_limite
  returning conteo into v_conteo;
  -- null = límite alcanzado; si no, devuelve los usos restantes
  return case when v_conteo is null then null else p_limite - v_conteo end;
end;
$$;
revoke all on function public.consumir_uso_ia(text, integer) from public, anon, authenticated;
grant execute on function public.consumir_uso_ia(text, integer) to service_role;

-- -----------------------------------------------------------------------------
-- 7. Audio en publicaciones y anuncios; subida de media de anuncios por admins
-- -----------------------------------------------------------------------------
alter table public.publicacion_media drop constraint if exists publicacion_media_tipo_check;
alter table public.publicacion_media add constraint publicacion_media_tipo_check check (tipo in ('imagen', 'video', 'audio'));

update storage.buckets set allowed_mime_types = array[
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm',
  'audio/webm', 'audio/ogg', 'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav', 'audio/x-wav'
] where id in ('media-pendiente', 'media-publica', 'media-miembros');

update storage.buckets set
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml', 'application/pdf',
                             'video/mp4', 'video/webm', 'audio/webm', 'audio/ogg', 'audio/mpeg', 'audio/mp4', 'audio/aac'],
  file_size_limit = 52428800
where id = 'sitio';

drop policy if exists "admin_subir_sitio" on storage.objects;
create policy "admin_subir_sitio" on storage.objects for insert with check (
  bucket_id = 'sitio' and (select public.es_moderador_alguno())
);
drop policy if exists "admin_borrar_sitio" on storage.objects;
create policy "admin_borrar_sitio" on storage.objects for delete using (
  bucket_id = 'sitio' and (select public.es_moderador_alguno())
);
