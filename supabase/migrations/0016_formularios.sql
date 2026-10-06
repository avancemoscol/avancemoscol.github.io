-- =============================================================================
-- Migración 0016: Formularios, encuestas y votaciones con enlace compartible
-- El administrador crea el formulario, comparte el enlace (formulario.html?f=<slug>)
-- y cada respuesta queda "pendiente" hasta que un administrador la revisa.
-- Solo las respuestas aprobadas cuentan en los resultados.
-- =============================================================================

create table if not exists public.formularios (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  tipo text not null default 'formulario' check (tipo in ('formulario', 'encuesta', 'votacion')),
  titulo text not null,
  descripcion text not null default '',
  -- [{id, tipo: texto|parrafo|opcion|multiple|lista|numero|fecha|correo|telefono, etiqueta, requerido, opciones: [..]}]
  campos jsonb not null default '[]'::jsonb,
  abierto boolean not null default true,
  cierra_en timestamptz,
  requiere_login boolean not null default false,
  mostrar_resultados boolean not null default false,
  mensaje_final text not null default 'Gracias. Tu respuesta fue recibida y será revisada por el equipo.',
  creado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.formulario_respuestas (
  id uuid primary key default gen_random_uuid(),
  formulario_id uuid not null references public.formularios(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  nombre text,
  contacto text,
  respuestas jsonb not null default '{}'::jsonb,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  revisado_por uuid references auth.users(id) on delete set null,
  revisado_en timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists formulario_respuestas_form_idx on public.formulario_respuestas (formulario_id, estado);
-- Una sola respuesta por cuenta y formulario
create unique index if not exists formulario_respuestas_unica_cuenta
  on public.formulario_respuestas (formulario_id, user_id) where user_id is not null;

-- Acceso solo por funciones (security definer): sin políticas = nadie lee directo
alter table public.formularios enable row level security;
alter table public.formulario_respuestas enable row level security;

-- -----------------------------------------------------------------------------
-- Público: leer un formulario por su enlace
-- -----------------------------------------------------------------------------
create or replace function public.formulario_publico(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.formularios;
begin
  select * into v from public.formularios where slug = p_slug;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', v.id, 'slug', v.slug, 'tipo', v.tipo, 'titulo', v.titulo, 'descripcion', v.descripcion,
    'campos', v.campos, 'requiere_login', v.requiere_login or v.tipo = 'votacion',
    'mensaje_final', v.mensaje_final, 'mostrar_resultados', v.mostrar_resultados,
    'disponible', v.abierto and (v.cierra_en is null or v.cierra_en > now()));
end;
$$;
grant execute on function public.formulario_publico(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Público: enviar respuesta (queda pendiente de revisión)
-- -----------------------------------------------------------------------------
create or replace function public.enviar_formulario(p_slug text, p_respuestas jsonb, p_nombre text default null, p_contacto text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v public.formularios;
  c jsonb;
  val jsonb;
  limpio jsonb := '{}'::jsonb;
  txt text;
  op text;
begin
  select * into v from public.formularios where slug = p_slug;
  if not found or not v.abierto or (v.cierra_en is not null and v.cierra_en <= now()) then
    raise exception 'Este formulario ya no está recibiendo respuestas.' using errcode = 'P0002';
  end if;
  if (v.requiere_login or v.tipo = 'votacion') and auth.uid() is null then
    raise exception 'Debes iniciar sesión para responder.' using errcode = '42501';
  end if;
  if auth.uid() is not null and exists (
    select 1 from public.formulario_respuestas where formulario_id = v.id and user_id = auth.uid()) then
    raise exception 'Ya respondiste este formulario.' using errcode = '23505';
  end if;
  if jsonb_typeof(coalesce(p_respuestas, '{}'::jsonb)) <> 'object' then
    raise exception 'Respuesta inválida.' using errcode = '22023';
  end if;

  for c in select * from jsonb_array_elements(v.campos) loop
    val := p_respuestas -> (c->>'id');
    if val is null or val = 'null'::jsonb or val = '""'::jsonb or val = '[]'::jsonb then
      if coalesce((c->>'requerido')::boolean, false) then
        raise exception 'Falta responder: %', c->>'etiqueta' using errcode = '22023';
      end if;
      continue;
    end if;
    if c->>'tipo' in ('opcion', 'lista') then
      if jsonb_typeof(val) <> 'string' or not (c->'opciones') ? (val #>> '{}') then
        raise exception 'Opción inválida en: %', c->>'etiqueta' using errcode = '22023';
      end if;
    elsif c->>'tipo' = 'multiple' then
      if jsonb_typeof(val) <> 'array' then
        raise exception 'Respuesta inválida en: %', c->>'etiqueta' using errcode = '22023';
      end if;
      for op in select jsonb_array_elements_text(val) loop
        if not (c->'opciones') ? op then
          raise exception 'Opción inválida en: %', c->>'etiqueta' using errcode = '22023';
        end if;
      end loop;
    else
      txt := val #>> '{}';
      if jsonb_typeof(val) not in ('string', 'number') or length(txt) > 4000 then
        raise exception 'Respuesta inválida en: %', c->>'etiqueta' using errcode = '22023';
      end if;
    end if;
    limpio := limpio || jsonb_build_object(c->>'id', val);
  end loop;

  insert into public.formulario_respuestas (formulario_id, user_id, nombre, contacto, respuestas)
  values (v.id, auth.uid(), left(nullif(btrim(p_nombre), ''), 120), left(nullif(btrim(p_contacto), ''), 160), limpio);
  return true;
end;
$$;
grant execute on function public.enviar_formulario(text, jsonb, text, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Resultados agregados (solo respuestas aprobadas)
-- -----------------------------------------------------------------------------
create or replace function public.resultados_formulario(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.formularios; c jsonb; out jsonb := '[]'::jsonb; total int; item jsonb;
begin
  select * into v from public.formularios where slug = p_slug;
  if not found then return null; end if;
  if not (public.es_admin_nacional() or v.mostrar_resultados) then
    raise exception 'Los resultados no son públicos.' using errcode = '42501';
  end if;
  select count(*) into total from public.formulario_respuestas where formulario_id = v.id and estado = 'aprobada';
  for c in select * from jsonb_array_elements(v.campos) loop
    if c->>'tipo' in ('opcion', 'lista', 'multiple') then
      select jsonb_agg(jsonb_build_object('texto', o.t, 'votos', (
        select count(*) from public.formulario_respuestas r
        where r.formulario_id = v.id and r.estado = 'aprobada'
          and case when jsonb_typeof(r.respuestas -> (c->>'id')) = 'array'
                   then (r.respuestas -> (c->>'id')) ? o.t
                   else (r.respuestas ->> (c->>'id')) = o.t end)) order by o.n)
      into item from jsonb_array_elements_text(c->'opciones') with ordinality as o(t, n);
      out := out || jsonb_build_object('id', c->>'id', 'etiqueta', c->>'etiqueta', 'opciones', coalesce(item, '[]'::jsonb));
    end if;
  end loop;
  return jsonb_build_object('total', total, 'preguntas', out);
end;
$$;
grant execute on function public.resultados_formulario(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Administración
-- -----------------------------------------------------------------------------
create or replace function public.admin_formularios()
returns table (id uuid, slug text, tipo text, titulo text, descripcion text, campos jsonb, abierto boolean,
               cierra_en timestamptz, requiere_login boolean, mostrar_resultados boolean, mensaje_final text,
               created_at timestamptz, pendientes bigint, aprobadas bigint, rechazadas bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  return query
    select f.id, f.slug, f.tipo, f.titulo, f.descripcion, f.campos, f.abierto, f.cierra_en, f.requiere_login,
           f.mostrar_resultados, f.mensaje_final, f.created_at,
           count(r.id) filter (where r.estado = 'pendiente'),
           count(r.id) filter (where r.estado = 'aprobada'),
           count(r.id) filter (where r.estado = 'rechazada')
    from public.formularios f left join public.formulario_respuestas r on r.formulario_id = f.id
    group by f.id order by f.created_at desc;
end;
$$;
grant execute on function public.admin_formularios() to authenticated;

create or replace function public.admin_guardar_formulario(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_tipo text := coalesce(p_datos->>'tipo', 'formulario');
  v_campos jsonb := coalesce(p_datos->'campos', '[]'::jsonb);
  v_slug text;
  c jsonb;
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  if coalesce(btrim(p_datos->>'titulo'), '') = '' then
    raise exception 'El formulario necesita un título.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_campos) <> 'array' or jsonb_array_length(v_campos) = 0 then
    raise exception 'Agrega al menos una pregunta.' using errcode = '22023';
  end if;
  for c in select * from jsonb_array_elements(v_campos) loop
    if coalesce(c->>'id', '') = '' or coalesce(btrim(c->>'etiqueta'), '') = '' then
      raise exception 'Todas las preguntas necesitan texto.' using errcode = '22023';
    end if;
    if c->>'tipo' in ('opcion', 'lista', 'multiple') and jsonb_array_length(coalesce(c->'opciones', '[]'::jsonb)) < 2 then
      raise exception 'Las preguntas de opciones necesitan al menos 2 opciones.' using errcode = '22023';
    end if;
  end loop;
  -- Con respuestas recibidas no se cambian las preguntas (alteraría los resultados)
  if p_id is not null and exists (select 1 from public.formulario_respuestas where formulario_id = p_id)
     and (select campos from public.formularios where id = p_id) is distinct from v_campos then
    raise exception 'Ya hay respuestas: no se pueden cambiar las preguntas. Duplica el formulario si necesitas otra versión.' using errcode = '22023';
  end if;

  if p_id is null then
    v_slug := lower(regexp_replace(translate(btrim(p_datos->>'titulo'), 'áéíóúñÁÉÍÓÚÑ', 'aeiounAEIOUN'), '[^a-zA-Z0-9]+', '-', 'g'));
    v_slug := trim(both '-' from left(v_slug, 40)) || '-' || substr(replace(v_id::text, '-', ''), 1, 6);
  end if;

  insert into public.formularios (id, slug, tipo, titulo, descripcion, campos, abierto, cierra_en, requiere_login,
                                  mostrar_resultados, mensaje_final, creado_por)
  values (v_id, v_slug, v_tipo, btrim(p_datos->>'titulo'), coalesce(p_datos->>'descripcion', ''), v_campos,
          coalesce((p_datos->>'abierto')::boolean, true), nullif(p_datos->>'cierra_en', '')::timestamptz,
          coalesce((p_datos->>'requiere_login')::boolean, false) or v_tipo = 'votacion',
          coalesce((p_datos->>'mostrar_resultados')::boolean, false),
          coalesce(nullif(p_datos->>'mensaje_final', ''), 'Gracias. Tu respuesta fue recibida y será revisada por el equipo.'),
          auth.uid())
  on conflict (id) do update set
    tipo = excluded.tipo, titulo = excluded.titulo, descripcion = excluded.descripcion, campos = excluded.campos,
    abierto = excluded.abierto, cierra_en = excluded.cierra_en, requiere_login = excluded.requiere_login,
    mostrar_resultados = excluded.mostrar_resultados, mensaje_final = excluded.mensaje_final, updated_at = now();

  insert into public.auditoria (actor_id, accion, entidad, entidad_id, despues)
  values (auth.uid(), case when p_id is null then 'crear_formulario' else 'editar_formulario' end, 'formulario', v_id::text,
          jsonb_build_object('tipo', v_tipo, 'titulo', p_datos->>'titulo'));
  return v_id;
end;
$$;
grant execute on function public.admin_guardar_formulario(uuid, jsonb) to authenticated;

create or replace function public.admin_eliminar_formulario(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  delete from public.formularios where id = p_id;
  insert into public.auditoria (actor_id, accion, entidad, entidad_id) values (auth.uid(), 'eliminar_formulario', 'formulario', p_id::text);
  return true;
end;
$$;
grant execute on function public.admin_eliminar_formulario(uuid) to authenticated;

create or replace function public.admin_respuestas_formulario(p_id uuid, p_estado text default 'pendiente')
returns table (id uuid, nombre text, contacto text, respuestas jsonb, estado text, created_at timestamptz, usuario text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  return query
    select r.id, r.nombre, r.contacto, r.respuestas, r.estado, r.created_at, p.username::text
    from public.formulario_respuestas r left join public.perfiles p on p.id = r.user_id
    where r.formulario_id = p_id and (p_estado is null or r.estado = p_estado)
    order by r.created_at desc limit 500;
end;
$$;
grant execute on function public.admin_respuestas_formulario(uuid, text) to authenticated;

create or replace function public.admin_revisar_respuesta(p_id uuid, p_estado text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin_nacional() then raise exception 'Acceso restringido.' using errcode = '42501'; end if;
  if p_estado not in ('aprobada', 'rechazada', 'pendiente') then raise exception 'Estado inválido.' using errcode = '22023'; end if;
  update public.formulario_respuestas set estado = p_estado, revisado_por = auth.uid(), revisado_en = now() where id = p_id;
  insert into public.auditoria (actor_id, accion, entidad, entidad_id, despues)
  values (auth.uid(), 'revisar_respuesta_formulario', 'formulario_respuesta', p_id::text, jsonb_build_object('estado', p_estado));
  return true;
end;
$$;
grant execute on function public.admin_revisar_respuesta(uuid, text) to authenticated;
