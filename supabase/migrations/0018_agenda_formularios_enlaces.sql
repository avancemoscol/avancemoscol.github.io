-- Avancemos Internacional · agenda (calendario), formularios y enlaces/redes
create table if not exists public.int_eventos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (length(titulo) between 2 and 160),
  descripcion text check (length(descripcion) <= 4000),
  tipo text not null default 'reunion' check (tipo in ('reunion','evento','campana','redes','otro')),
  inicio timestamptz not null,
  fin timestamptz,
  lugar text check (length(lugar) <= 200),
  enlace text check (enlace ~ '^https://'),
  realizado boolean not null default false,
  resumen text check (length(resumen) <= 4000),
  continente text, pais_id text references public.int_paises(id),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists int_eventos_inicio on public.int_eventos (inicio);

create table if not exists public.int_asistencias (
  evento_id uuid not null references public.int_eventos(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (evento_id, user_id)
);

create table if not exists public.int_enlaces (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (length(titulo) between 1 and 120),
  url text not null check (url ~ '^https://'),
  categoria text not null default 'redes' check (categoria in ('redes','grupos','documentos','otros')),
  orden int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.int_formularios (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (length(titulo) between 2 and 160),
  descripcion text check (length(descripcion) <= 4000),
  campos jsonb not null check (jsonb_typeof(campos) = 'array' and jsonb_array_length(campos) between 1 and 40),
  cierra_en timestamptz,
  cerrado boolean not null default false,
  continente text, pais_id text references public.int_paises(id),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.int_respuestas (
  formulario_id uuid not null references public.int_formularios(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  datos jsonb not null check (jsonb_typeof(datos) = 'array'),
  created_at timestamptz not null default now(),
  primary key (formulario_id, user_id)
);

alter table public.int_eventos enable row level security;
alter table public.int_asistencias enable row level security;
alter table public.int_enlaces enable row level security;
alter table public.int_formularios enable row level security;
alter table public.int_respuestas enable row level security;

drop policy if exists int_ev_leer on public.int_eventos;
create policy int_ev_leer on public.int_eventos for select to authenticated
  using (public.int_es_activo() and public.int_me_aplica(continente, pais_id));
drop policy if exists int_ev_gestion on public.int_eventos;
create policy int_ev_gestion on public.int_eventos for all to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord());

drop policy if exists int_asis_leer on public.int_asistencias;
create policy int_asis_leer on public.int_asistencias for select to authenticated
  using (user_id = (select auth.uid()) or public.int_es_coord());
drop policy if exists int_asis_marcar on public.int_asistencias;
create policy int_asis_marcar on public.int_asistencias for insert to authenticated
  with check (user_id = (select auth.uid()) and public.int_es_activo());
drop policy if exists int_asis_quitar on public.int_asistencias;
create policy int_asis_quitar on public.int_asistencias for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists int_enl_leer on public.int_enlaces;
create policy int_enl_leer on public.int_enlaces for select to authenticated using (public.int_es_activo());
drop policy if exists int_enl_gestion on public.int_enlaces;
create policy int_enl_gestion on public.int_enlaces for all to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord());

drop policy if exists int_form_leer on public.int_formularios;
create policy int_form_leer on public.int_formularios for select to authenticated
  using (public.int_es_activo() and public.int_me_aplica(continente, pais_id));
drop policy if exists int_form_gestion on public.int_formularios;
create policy int_form_gestion on public.int_formularios for all to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord());

drop policy if exists int_resp_leer on public.int_respuestas;
create policy int_resp_leer on public.int_respuestas for select to authenticated
  using (user_id = (select auth.uid()) or public.int_es_coord());
drop policy if exists int_resp_enviar on public.int_respuestas;
create policy int_resp_enviar on public.int_respuestas for insert to authenticated
  with check (user_id = (select auth.uid()) and public.int_es_activo()
    and exists (select 1 from public.int_formularios f where f.id = formulario_id and not f.cerrado
                and (f.cierra_en is null or f.cierra_en > now())));

-- Asistentes de un evento y respuestas de un formulario, con nombre (solo coordinación)
create or replace function public.int_asistentes(p_evento uuid)
returns table (nombre text, telefono text, pais_id text) language sql stable security definer set search_path = '' as $$
  select m.nombre, m.telefono, m.pais_id from public.int_asistencias a join public.int_miembros m on m.user_id = a.user_id
  where a.evento_id = p_evento and public.int_es_coord() order by m.nombre;
$$;
create or replace function public.int_respuestas_de(p_form uuid)
returns table (nombre text, telefono text, pais_id text, datos jsonb, created_at timestamptz) language sql stable security definer set search_path = '' as $$
  select coalesce(m.nombre, '—'), m.telefono, m.pais_id, r.datos, r.created_at from public.int_respuestas r
  left join public.int_miembros m on m.user_id = r.user_id
  where r.formulario_id = p_form and public.int_es_coord() order by r.created_at;
$$;
create or replace function public.int_conteo_asistencia()
returns table (evento_id uuid, n bigint) language sql stable security definer set search_path = '' as $$
  select evento_id, count(*) from public.int_asistencias where public.int_es_activo() group by evento_id;
$$;
revoke execute on function public.int_asistentes(uuid), public.int_respuestas_de(uuid), public.int_conteo_asistencia() from anon, public;
grant execute on function public.int_asistentes(uuid), public.int_respuestas_de(uuid), public.int_conteo_asistencia() to authenticated;
