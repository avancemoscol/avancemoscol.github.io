-- =============================================================================
-- Migración 0019: Línea de tiempo del movimiento ("lo que se ha hecho / lo que sigue")
-- Hitos creados por el administrador + eventos aprobados y públicos, en un solo
-- listado abierto a visitantes, más unas cifras generales del movimiento.
-- =============================================================================

create table if not exists public.hitos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text not null default '',
  estado text not null default 'logrado' check (estado in ('logrado', 'en_curso', 'proximo')),
  fecha date not null default (now() at time zone 'America/Bogota')::date,
  departamento_id text references public.departamentos(id),
  enlace text check (enlace is null or enlace ~ '^https://'),
  publicado boolean not null default true,
  creado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists hitos_fecha_idx on public.hitos (fecha desc);
alter table public.hitos enable row level security; -- acceso solo por funciones

-- Público: historial y próximos pasos
create or replace function public.linea_tiempo(p_limite int default 30)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_lim int := least(greatest(coalesce(p_limite, 30), 1), 100);
begin
  return jsonb_build_object(
    'proximo', coalesce((
      select jsonb_agg(x order by x->>'fecha') from (select x from (
        select jsonb_build_object('origen', 'hito', 'id', h.id, 'titulo', h.titulo, 'descripcion', h.descripcion,
               'estado', h.estado, 'fecha', h.fecha::timestamptz, 'enlace', h.enlace,
               'departamento', d.nombre) x
        from public.hitos h left join public.departamentos d on d.id = h.departamento_id
        where h.publicado and h.estado in ('proximo', 'en_curso')
        union all
        select jsonb_build_object('origen', 'evento', 'id', e.id, 'titulo', e.titulo, 'descripcion', e.descripcion,
               'estado', 'proximo', 'fecha', e.inicio, 'lugar', e.lugar, 'modalidad', e.modalidad,
               'departamento', d.nombre)
        from public.eventos e left join public.departamentos d on d.id = e.departamento_id
        where e.estado = 'aprobado' and e.visibilidad = 'publica' and e.inicio >= now()
        ) u order by x->>'fecha' limit v_lim) t), '[]'::jsonb),
    'historial', coalesce((
      select jsonb_agg(x order by x->>'fecha' desc) from (select x from (
        select jsonb_build_object('origen', 'hito', 'id', h.id, 'titulo', h.titulo, 'descripcion', h.descripcion,
               'estado', 'logrado', 'fecha', h.fecha::timestamptz, 'enlace', h.enlace,
               'departamento', d.nombre) x
        from public.hitos h left join public.departamentos d on d.id = h.departamento_id
        where h.publicado and h.estado = 'logrado'
        union all
        select jsonb_build_object('origen', 'evento', 'id', e.id, 'titulo', e.titulo, 'descripcion', e.descripcion,
               'estado', 'logrado', 'fecha', e.inicio, 'lugar', e.lugar, 'modalidad', e.modalidad,
               'departamento', d.nombre)
        from public.eventos e left join public.departamentos d on d.id = e.departamento_id
        where e.estado = 'aprobado' and e.visibilidad = 'publica' and e.inicio < now()
        ) u order by x->>'fecha' desc limit v_lim) t), '[]'::jsonb),
    'cifras', jsonb_build_object(
      'miembros', (select count(*) from public.perfiles where estado = 'activo'),
      'departamentos', (select count(distinct departamento_id) from public.perfiles where estado = 'activo' and departamento_id is not null),
      'eventos_realizados', (select count(*) from public.eventos where estado = 'aprobado' and visibilidad = 'publica' and inicio < now()),
      'eventos_proximos', (select count(*) from public.eventos where estado = 'aprobado' and visibilidad = 'publica' and inicio >= now()))
  );
end;
$$;
grant execute on function public.linea_tiempo(int) to anon, authenticated;

-- Administración
create or replace function public.admin_hitos()
returns setof public.hitos language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  return query select * from public.hitos order by fecha desc, created_at desc;
end;
$$;
grant execute on function public.admin_hitos() to authenticated;

create or replace function public.admin_guardar_hito(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  if coalesce(btrim(p_datos->>'titulo'), '') = '' then
    raise exception 'El hito necesita un título.' using errcode = '22023';
  end if;
  insert into public.hitos (id, titulo, descripcion, estado, fecha, departamento_id, enlace, publicado, creado_por)
  values (v_id, btrim(p_datos->>'titulo'), coalesce(p_datos->>'descripcion', ''),
          coalesce(nullif(p_datos->>'estado', ''), 'logrado'),
          coalesce(nullif(p_datos->>'fecha', '')::date, (now() at time zone 'America/Bogota')::date),
          nullif(p_datos->>'departamento_id', ''), nullif(btrim(p_datos->>'enlace'), ''),
          coalesce((p_datos->>'publicado')::boolean, true), auth.uid())
  on conflict (id) do update set
    titulo = excluded.titulo, descripcion = excluded.descripcion, estado = excluded.estado, fecha = excluded.fecha,
    departamento_id = excluded.departamento_id, enlace = excluded.enlace, publicado = excluded.publicado;
  insert into public.auditoria (actor_id, accion, entidad, entidad_id, despues)
  values (auth.uid(), case when p_id is null then 'crear_hito' else 'editar_hito' end, 'hito', v_id::text,
          jsonb_build_object('titulo', p_datos->>'titulo'));
  return v_id;
end;
$$;
grant execute on function public.admin_guardar_hito(uuid, jsonb) to authenticated;

create or replace function public.admin_eliminar_hito(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  delete from public.hitos where id = p_id;
  insert into public.auditoria (actor_id, accion, entidad, entidad_id) values (auth.uid(), 'eliminar_hito', 'hito', p_id::text);
  return true;
end;
$$;
grant execute on function public.admin_eliminar_hito(uuid) to authenticated;
