-- =============================================================================
-- Migración 0017: Plataforma Internacional de Avancemos (sitio aparte)
-- Miembros en el exterior, tablero de anuncios/acuerdos con control de lectura,
-- votaciones y encuestas, y organigrama por continente / país / ciudad / sector.
-- Mismo proyecto Supabase: las cuentas de Avancemos sirven para entrar.
-- =============================================================================

create table if not exists public.int_paises (
  id text primary key references public.municipios(id),   -- 'EX-ES'
  nombre text not null,
  continente text not null check (continente in ('Norteamérica','Centroamérica y Caribe','Sudamérica','Europa','África','Asia','Oceanía'))
);

create table if not exists public.int_miembros (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null check (char_length(nombre) between 2 and 120),
  pais_id text not null references public.int_paises(id),
  ciudad text check (char_length(ciudad) <= 80),
  telefono text check (char_length(telefono) <= 30),
  sector text check (char_length(sector) <= 80),
  rol text not null default 'miembro' check (rol in ('miembro', 'coordinador', 'admin')),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'activo', 'suspendido')),
  revisado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Organigrama: cada nodo es un cargo; puede estar vacante (user_id null)
create table if not exists public.int_cargos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (char_length(titulo) between 2 and 100),
  nivel text not null check (nivel in ('global', 'continente', 'pais', 'ciudad', 'sector')),
  continente text,
  pais_id text references public.int_paises(id),
  ciudad text,
  sector text,
  padre_id uuid references public.int_cargos(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  orden integer not null default 0,
  created_at timestamptz not null default now()
);

-- Tablero: lo importante no se pierde como en el chat
create table if not exists public.int_publicaciones (
  id uuid primary key default gen_random_uuid(),
  tipo text not null default 'anuncio' check (tipo in ('anuncio', 'acuerdo', 'acta', 'tarea', 'recurso')),
  titulo text not null check (char_length(titulo) between 3 and 160),
  cuerpo text not null default '' check (char_length(cuerpo) <= 8000),
  enlace text check (enlace is null or enlace ~ '^https://'),
  fijado boolean not null default false,
  continente text,             -- null = para todos
  pais_id text references public.int_paises(id),
  vence_en timestamptz,        -- tareas
  autor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.int_lecturas (
  publicacion_id uuid not null references public.int_publicaciones(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  leido_en timestamptz not null default now(),
  primary key (publicacion_id, user_id)
);

create table if not exists public.int_encuestas (
  id uuid primary key default gen_random_uuid(),
  tipo text not null default 'votacion' check (tipo in ('votacion', 'encuesta')),  -- votación: 1 opción; encuesta: varias
  titulo text not null check (char_length(titulo) between 3 and 200),
  descripcion text not null default '' check (char_length(descripcion) <= 4000),
  opciones jsonb not null check (jsonb_typeof(opciones) = 'array' and jsonb_array_length(opciones) between 2 and 20),
  permite_comentario boolean not null default false,
  resultados text not null default 'al_votar' check (resultados in ('siempre', 'al_votar', 'al_cerrar')),
  continente text,
  pais_id text references public.int_paises(id),
  cierra_en timestamptz,
  cerrada boolean not null default false,
  autor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.int_votos (
  encuesta_id uuid not null references public.int_encuestas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  opciones integer[] not null,
  comentario text check (char_length(comentario) <= 500),
  created_at timestamptz not null default now(),
  primary key (encuesta_id, user_id)
);

create index if not exists int_publicaciones_fecha on public.int_publicaciones (fijado desc, created_at desc);
create index if not exists int_encuestas_fecha on public.int_encuestas (created_at desc);
create index if not exists int_miembros_pais on public.int_miembros (pais_id, estado);

-- -----------------------------------------------------------------------------
-- Permisos
-- -----------------------------------------------------------------------------
create or replace function public.int_mi_rol()
returns text language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin_nacional() then 'admin'
    else (select case when m.estado = 'activo' then m.rol end from public.int_miembros m where m.user_id = (select auth.uid()))
  end;
$$;
create or replace function public.int_es_activo() returns boolean language sql stable security definer set search_path = '' as $$
  select public.int_mi_rol() is not null; $$;
create or replace function public.int_es_coord() returns boolean language sql stable security definer set search_path = '' as $$
  select public.int_mi_rol() in ('coordinador', 'admin'); $$;
create or replace function public.int_es_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select public.int_mi_rol() = 'admin'; $$;

-- ¿La publicación/encuesta va dirigida a mí? (null = todos; coordinadores ven todo)
create or replace function public.int_me_aplica(p_continente text, p_pais text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.int_es_coord() or (p_continente is null and p_pais is null) or exists (
    select 1 from public.int_miembros m join public.int_paises p on p.id = m.pais_id
    where m.user_id = (select auth.uid()) and (p_pais is null or m.pais_id = p_pais) and (p_continente is null or p.continente = p_continente));
$$;

alter table public.int_paises enable row level security;
alter table public.int_miembros enable row level security;
alter table public.int_cargos enable row level security;
alter table public.int_publicaciones enable row level security;
alter table public.int_lecturas enable row level security;
alter table public.int_encuestas enable row level security;
alter table public.int_votos enable row level security;

drop policy if exists int_paises_leer on public.int_paises;
create policy int_paises_leer on public.int_paises for select to anon, authenticated using (true);

drop policy if exists int_miembros_leer on public.int_miembros;
create policy int_miembros_leer on public.int_miembros for select to authenticated
  using (user_id = (select auth.uid()) or public.int_es_coord());
drop policy if exists int_miembros_editar on public.int_miembros;
create policy int_miembros_editar on public.int_miembros for update to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord() and (rol = 'miembro' or public.int_es_admin()));
drop policy if exists int_miembros_borrar on public.int_miembros;
create policy int_miembros_borrar on public.int_miembros for delete to authenticated using (public.int_es_admin());

drop policy if exists int_cargos_gestion on public.int_cargos;
create policy int_cargos_gestion on public.int_cargos for all to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord());

drop policy if exists int_pub_leer on public.int_publicaciones;
create policy int_pub_leer on public.int_publicaciones for select to authenticated
  using (public.int_es_activo() and public.int_me_aplica(continente, pais_id));
drop policy if exists int_pub_gestion on public.int_publicaciones;
create policy int_pub_gestion on public.int_publicaciones for all to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord());

drop policy if exists int_lect_propia on public.int_lecturas;
create policy int_lect_propia on public.int_lecturas for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists int_lect_marcar on public.int_lecturas;
create policy int_lect_marcar on public.int_lecturas for insert to authenticated
  with check (user_id = (select auth.uid()) and public.int_es_activo());

drop policy if exists int_enc_leer on public.int_encuestas;
create policy int_enc_leer on public.int_encuestas for select to authenticated
  using (public.int_es_activo() and public.int_me_aplica(continente, pais_id));
drop policy if exists int_enc_gestion on public.int_encuestas;
create policy int_enc_gestion on public.int_encuestas for all to authenticated
  using (public.int_es_coord()) with check (public.int_es_coord());

-- Votos: cada quien ve el suyo; se vota solo por función
drop policy if exists int_votos_propio on public.int_votos;
create policy int_votos_propio on public.int_votos for select to authenticated using (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- Registro: al crear la cuenta desde el sitio internacional (metadata origen = internacional)
-- -----------------------------------------------------------------------------
create or replace function public.tr_int_nuevo_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if v->>'origen' = 'internacional' and exists (select 1 from public.int_paises where id = v->>'municipio_id') then
    insert into public.int_miembros (user_id, nombre, pais_id, ciudad, telefono, sector)
    values (new.id, left(coalesce(nullif(trim(v->>'nombre'), ''), split_part(new.email, '@', 1)), 120), v->>'municipio_id',
            left(nullif(trim(v->>'ciudad'), ''), 80), left(nullif(trim(v->>'telefono'), ''), 30), left(nullif(trim(v->>'sector'), ''), 80))
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_int on auth.users;
create trigger on_auth_user_created_int after insert on auth.users
  for each row execute function public.tr_int_nuevo_usuario();

-- Cuentas que ya existen en Avancemos: se suman a la red internacional
create or replace function public.int_unirme(p_nombre text, p_pais text, p_ciudad text, p_telefono text, p_sector text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.' using errcode = '42501'; end if;
  if not exists (select 1 from public.int_paises where id = p_pais) then raise exception 'País inválido.' using errcode = '22023'; end if;
  insert into public.int_miembros (user_id, nombre, pais_id, ciudad, telefono, sector)
  values (auth.uid(), left(trim(p_nombre), 120), p_pais, left(nullif(trim(p_ciudad), ''), 80), left(nullif(trim(p_telefono), ''), 30), left(nullif(trim(p_sector), ''), 80))
  on conflict (user_id) do update set nombre = excluded.nombre, pais_id = excluded.pais_id, ciudad = excluded.ciudad,
    telefono = excluded.telefono, sector = excluded.sector;
  return true;
end;
$$;

-- -----------------------------------------------------------------------------
-- Votar (valida apertura, opciones y una sola vez)
-- -----------------------------------------------------------------------------
create or replace function public.int_votar(p_encuesta uuid, p_opciones integer[], p_comentario text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare e public.int_encuestas; n integer; o integer;
begin
  if not public.int_es_activo() then raise exception 'Tu cuenta aún no está aprobada.' using errcode = '42501'; end if;
  select * into e from public.int_encuestas where id = p_encuesta;
  if not found or not public.int_me_aplica(e.continente, e.pais_id) then raise exception 'Votación no encontrada.' using errcode = 'P0002'; end if;
  if e.cerrada or (e.cierra_en is not null and e.cierra_en <= now()) then raise exception 'Esta votación ya cerró.' using errcode = 'P0002'; end if;
  n := jsonb_array_length(e.opciones);
  if p_opciones is null or cardinality(p_opciones) = 0 then raise exception 'Elige una opción.' using errcode = '22023'; end if;
  if e.tipo = 'votacion' and cardinality(p_opciones) <> 1 then raise exception 'Solo puedes elegir una opción.' using errcode = '22023'; end if;
  foreach o in array p_opciones loop
    if o < 0 or o >= n then raise exception 'Opción inválida.' using errcode = '22023'; end if;
  end loop;
  insert into public.int_votos (encuesta_id, user_id, opciones, comentario)
  values (p_encuesta, auth.uid(), (select array_agg(distinct x order by x) from unnest(p_opciones) x),
          case when e.permite_comentario then left(nullif(trim(p_comentario), ''), 500) end);
  return true;
exception when unique_violation then
  raise exception 'Ya votaste en esta votación.' using errcode = '23505';
end;
$$;

-- Resultados (respeta la regla de visibilidad; coordinadores siempre los ven)
create or replace function public.int_resultados(p_encuesta uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e public.int_encuestas; ya boolean; cerr boolean;
begin
  if not public.int_es_activo() then return null; end if;
  select * into e from public.int_encuestas where id = p_encuesta;
  if not found or not public.int_me_aplica(e.continente, e.pais_id) then return null; end if;
  ya := exists (select 1 from public.int_votos where encuesta_id = e.id and user_id = auth.uid());
  cerr := e.cerrada or (e.cierra_en is not null and e.cierra_en <= now());
  if not (public.int_es_coord() or e.resultados = 'siempre' or (e.resultados = 'al_votar' and (ya or cerr)) or cerr) then
    return jsonb_build_object('oculto', true, 'votantes', (select count(*) from public.int_votos where encuesta_id = e.id));
  end if;
  return jsonb_build_object(
    'votantes', (select count(*) from public.int_votos where encuesta_id = e.id),
    'conteo', (select jsonb_agg(coalesce((select count(*) from public.int_votos v where v.encuesta_id = e.id and i = any(v.opciones)), 0) order by i)
               from generate_series(0, jsonb_array_length(e.opciones) - 1) i),
    'comentarios', case when public.int_es_coord() then (select coalesce(jsonb_agg(v.comentario), '[]') from public.int_votos v where v.encuesta_id = e.id and v.comentario is not null) end);
end;
$$;

-- Quién leyó / quién votó (solo coordinadores): para hacer seguimiento a quien no se ha enterado
create or replace function public.int_seguimiento(p_tipo text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.int_es_coord() then raise exception 'Solo coordinadores.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('nombre', m.nombre, 'pais', p.nombre, 'telefono', m.telefono,
      'hecho', case when p_tipo = 'lectura' then exists (select 1 from public.int_lecturas l where l.publicacion_id = p_id and l.user_id = m.user_id)
                    else exists (select 1 from public.int_votos v where v.encuesta_id = p_id and v.user_id = m.user_id) end)
      order by m.nombre), '[]')
    from public.int_miembros m join public.int_paises p on p.id = m.pais_id where m.estado = 'activo');
end;
$$;

-- Organigrama y mapa (miembros activos ven nombres de quienes tienen cargo y el conteo por país)
create or replace function public.int_organigrama()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.int_es_activo() then return null; end if;
  return jsonb_build_object(
    'cargos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'titulo', c.titulo, 'nivel', c.nivel, 'continente', c.continente,
        'pais_id', c.pais_id, 'ciudad', c.ciudad, 'sector', c.sector, 'padre_id', c.padre_id, 'orden', c.orden, 'user_id', c.user_id,
        'nombre', m.nombre, 'telefono', case when public.int_es_coord() then m.telefono end) order by c.orden, c.titulo), '[]')
      from public.int_cargos c left join public.int_miembros m on m.user_id = c.user_id),
    'por_pais', (select coalesce(jsonb_object_agg(pais_id, n), '{}') from (select pais_id, count(*) n from public.int_miembros where estado = 'activo' group by pais_id) t));
end;
$$;

-- Resumen para la portada del miembro: pendientes por leer y por votar
create or replace function public.int_pendientes()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'por_leer', (select count(*) from public.int_publicaciones p where public.int_me_aplica(p.continente, p.pais_id)
                  and not exists (select 1 from public.int_lecturas l where l.publicacion_id = p.id and l.user_id = (select auth.uid()))),
    'por_votar', (select count(*) from public.int_encuestas e where public.int_me_aplica(e.continente, e.pais_id) and not e.cerrada
                  and (e.cierra_en is null or e.cierra_en > now())
                  and not exists (select 1 from public.int_votos v where v.encuesta_id = e.id and v.user_id = (select auth.uid()))))
  where public.int_es_activo();
$$;

revoke all on function public.tr_int_nuevo_usuario() from public, anon, authenticated;
grant execute on function public.int_mi_rol(), public.int_es_activo(), public.int_es_coord(), public.int_es_admin(),
  public.int_me_aplica(text, text), public.int_unirme(text, text, text, text, text), public.int_votar(uuid, integer[], text),
  public.int_resultados(uuid), public.int_seguimiento(text, uuid), public.int_organigrama(), public.int_pendientes() to authenticated;
grant select on public.int_paises to anon, authenticated;
grant select, insert, update, delete on public.int_miembros, public.int_cargos, public.int_publicaciones, public.int_lecturas,
  public.int_encuestas, public.int_votos to authenticated;

insert into public.int_paises (id, nombre, continente) values
  ('EX-AF', 'Afganistán', 'Asia'),
  ('EX-AL', 'Albania', 'Europa'),
  ('EX-DE', 'Alemania', 'Europa'),
  ('EX-AD', 'Andorra', 'Europa'),
  ('EX-AO', 'Angola', 'África'),
  ('EX-AG', 'Antigua y Barbuda', 'Centroamérica y Caribe'),
  ('EX-SA', 'Arabia Saudí', 'Asia'),
  ('EX-DZ', 'Argelia', 'África'),
  ('EX-AR', 'Argentina', 'Sudamérica'),
  ('EX-AM', 'Armenia', 'Asia'),
  ('EX-AW', 'Aruba', 'Centroamérica y Caribe'),
  ('EX-AU', 'Australia', 'Oceanía'),
  ('EX-AT', 'Austria', 'Europa'),
  ('EX-AZ', 'Azerbaiyán', 'Asia'),
  ('EX-BS', 'Bahamas', 'Centroamérica y Caribe'),
  ('EX-BD', 'Bangladés', 'Asia'),
  ('EX-BB', 'Barbados', 'Centroamérica y Caribe'),
  ('EX-BH', 'Baréin', 'Asia'),
  ('EX-BZ', 'Belice', 'Centroamérica y Caribe'),
  ('EX-BJ', 'Benín', 'África'),
  ('EX-BY', 'Bielorrusia', 'Europa'),
  ('EX-BO', 'Bolivia', 'Sudamérica'),
  ('EX-BA', 'Bosnia y Herzegovina', 'Europa'),
  ('EX-BW', 'Botsuana', 'África'),
  ('EX-BR', 'Brasil', 'Sudamérica'),
  ('EX-BN', 'Brunéi', 'Asia'),
  ('EX-BG', 'Bulgaria', 'Europa'),
  ('EX-BF', 'Burkina Faso', 'África'),
  ('EX-BI', 'Burundi', 'África'),
  ('EX-BT', 'Bután', 'Asia'),
  ('EX-BE', 'Bélgica', 'Europa'),
  ('EX-CV', 'Cabo Verde', 'África'),
  ('EX-KH', 'Camboya', 'Asia'),
  ('EX-CM', 'Camerún', 'África'),
  ('EX-CA', 'Canadá', 'Norteamérica'),
  ('EX-QA', 'Catar', 'Asia'),
  ('EX-TD', 'Chad', 'África'),
  ('EX-CZ', 'Chequia', 'Europa'),
  ('EX-CL', 'Chile', 'Sudamérica'),
  ('EX-CN', 'China', 'Asia'),
  ('EX-CY', 'Chipre', 'Europa'),
  ('EX-VA', 'Ciudad del Vaticano', 'Europa'),
  ('EX-KM', 'Comoras', 'África'),
  ('EX-CG', 'Congo', 'África'),
  ('EX-KP', 'Corea del Norte', 'Asia'),
  ('EX-KR', 'Corea del Sur', 'Asia'),
  ('EX-CR', 'Costa Rica', 'Centroamérica y Caribe'),
  ('EX-HR', 'Croacia', 'Europa'),
  ('EX-CU', 'Cuba', 'Centroamérica y Caribe'),
  ('EX-CW', 'Curazao', 'Centroamérica y Caribe'),
  ('EX-CI', 'Côte d’Ivoire', 'África'),
  ('EX-DK', 'Dinamarca', 'Europa'),
  ('EX-DM', 'Dominica', 'Centroamérica y Caribe'),
  ('EX-EC', 'Ecuador', 'Sudamérica'),
  ('EX-EG', 'Egipto', 'África'),
  ('EX-SV', 'El Salvador', 'Centroamérica y Caribe'),
  ('EX-AE', 'Emiratos Árabes Unidos', 'Asia'),
  ('EX-ER', 'Eritrea', 'África'),
  ('EX-SK', 'Eslovaquia', 'Europa'),
  ('EX-SI', 'Eslovenia', 'Europa'),
  ('EX-ES', 'España', 'Europa'),
  ('EX-US', 'Estados Unidos', 'Norteamérica'),
  ('EX-EE', 'Estonia', 'Europa'),
  ('EX-SZ', 'Esuatini', 'África'),
  ('EX-ET', 'Etiopía', 'África'),
  ('EX-PH', 'Filipinas', 'Asia'),
  ('EX-FI', 'Finlandia', 'Europa'),
  ('EX-FJ', 'Fiyi', 'Oceanía'),
  ('EX-FR', 'Francia', 'Europa'),
  ('EX-GA', 'Gabón', 'África'),
  ('EX-GM', 'Gambia', 'África'),
  ('EX-GE', 'Georgia', 'Asia'),
  ('EX-GH', 'Ghana', 'África'),
  ('EX-GD', 'Granada', 'Centroamérica y Caribe'),
  ('EX-GR', 'Grecia', 'Europa'),
  ('EX-GT', 'Guatemala', 'Centroamérica y Caribe'),
  ('EX-GN', 'Guinea', 'África'),
  ('EX-GQ', 'Guinea Ecuatorial', 'África'),
  ('EX-GW', 'Guinea-Bisáu', 'África'),
  ('EX-GY', 'Guyana', 'Sudamérica'),
  ('EX-HT', 'Haití', 'Centroamérica y Caribe'),
  ('EX-HN', 'Honduras', 'Centroamérica y Caribe'),
  ('EX-HU', 'Hungría', 'Europa'),
  ('EX-IN', 'India', 'Asia'),
  ('EX-ID', 'Indonesia', 'Asia'),
  ('EX-IQ', 'Irak', 'Asia'),
  ('EX-IE', 'Irlanda', 'Europa'),
  ('EX-IR', 'Irán', 'Asia'),
  ('EX-IS', 'Islandia', 'Europa'),
  ('EX-MH', 'Islas Marshall', 'Oceanía'),
  ('EX-SB', 'Islas Salomón', 'Oceanía'),
  ('EX-IL', 'Israel', 'Asia'),
  ('EX-IT', 'Italia', 'Europa'),
  ('EX-JM', 'Jamaica', 'Centroamérica y Caribe'),
  ('EX-JP', 'Japón', 'Asia'),
  ('EX-JO', 'Jordania', 'Asia'),
  ('EX-KZ', 'Kazajistán', 'Asia'),
  ('EX-KE', 'Kenia', 'África'),
  ('EX-KG', 'Kirguistán', 'Asia'),
  ('EX-KI', 'Kiribati', 'Oceanía'),
  ('EX-KW', 'Kuwait', 'Asia'),
  ('EX-LA', 'Laos', 'Asia'),
  ('EX-LS', 'Lesoto', 'África'),
  ('EX-LV', 'Letonia', 'Europa'),
  ('EX-LR', 'Liberia', 'África'),
  ('EX-LY', 'Libia', 'África'),
  ('EX-LI', 'Liechtenstein', 'Europa'),
  ('EX-LT', 'Lituania', 'Europa'),
  ('EX-LU', 'Luxemburgo', 'Europa'),
  ('EX-LB', 'Líbano', 'Asia'),
  ('EX-MK', 'Macedonia del Norte', 'Europa'),
  ('EX-MG', 'Madagascar', 'África'),
  ('EX-MY', 'Malasia', 'Asia'),
  ('EX-MW', 'Malaui', 'África'),
  ('EX-MV', 'Maldivas', 'Asia'),
  ('EX-ML', 'Mali', 'África'),
  ('EX-MT', 'Malta', 'Europa'),
  ('EX-MA', 'Marruecos', 'África'),
  ('EX-MU', 'Mauricio', 'África'),
  ('EX-MR', 'Mauritania', 'África'),
  ('EX-FM', 'Micronesia', 'Oceanía'),
  ('EX-MD', 'Moldavia', 'Europa'),
  ('EX-MN', 'Mongolia', 'Asia'),
  ('EX-ME', 'Montenegro', 'Europa'),
  ('EX-MZ', 'Mozambique', 'África'),
  ('EX-MM', 'Myanmar (Birmania)', 'Asia'),
  ('EX-MX', 'México', 'Norteamérica'),
  ('EX-MC', 'Mónaco', 'Europa'),
  ('EX-NA', 'Namibia', 'África'),
  ('EX-NR', 'Nauru', 'Oceanía'),
  ('EX-NP', 'Nepal', 'Asia'),
  ('EX-NI', 'Nicaragua', 'Centroamérica y Caribe'),
  ('EX-NG', 'Nigeria', 'África'),
  ('EX-NO', 'Noruega', 'Europa'),
  ('EX-NZ', 'Nueva Zelanda', 'Oceanía'),
  ('EX-NE', 'Níger', 'África'),
  ('EX-OM', 'Omán', 'Asia'),
  ('EX-PK', 'Pakistán', 'Asia'),
  ('EX-PW', 'Palaos', 'Oceanía'),
  ('EX-PA', 'Panamá', 'Centroamérica y Caribe'),
  ('EX-PG', 'Papúa Nueva Guinea', 'Oceanía'),
  ('EX-PY', 'Paraguay', 'Sudamérica'),
  ('EX-NL', 'Países Bajos', 'Europa'),
  ('EX-PE', 'Perú', 'Sudamérica'),
  ('EX-PL', 'Polonia', 'Europa'),
  ('EX-PT', 'Portugal', 'Europa'),
  ('EX-PR', 'Puerto Rico', 'Centroamérica y Caribe'),
  ('EX-GB', 'Reino Unido', 'Europa'),
  ('EX-CF', 'República Centroafricana', 'África'),
  ('EX-CD', 'República Democrática del Congo', 'África'),
  ('EX-DO', 'República Dominicana', 'Centroamérica y Caribe'),
  ('EX-RW', 'Ruanda', 'África'),
  ('EX-RO', 'Rumanía', 'Europa'),
  ('EX-RU', 'Rusia', 'Europa'),
  ('EX-WS', 'Samoa', 'Oceanía'),
  ('EX-KN', 'San Cristóbal y Nieves', 'Centroamérica y Caribe'),
  ('EX-SM', 'San Marino', 'Europa'),
  ('EX-VC', 'San Vicente y las Granadinas', 'Centroamérica y Caribe'),
  ('EX-LC', 'Santa Lucía', 'Centroamérica y Caribe'),
  ('EX-ST', 'Santo Tomé y Príncipe', 'África'),
  ('EX-SN', 'Senegal', 'África'),
  ('EX-RS', 'Serbia', 'Europa'),
  ('EX-SC', 'Seychelles', 'África'),
  ('EX-SL', 'Sierra Leona', 'África'),
  ('EX-SG', 'Singapur', 'Asia'),
  ('EX-SY', 'Siria', 'Asia'),
  ('EX-SO', 'Somalia', 'África'),
  ('EX-LK', 'Sri Lanka', 'Asia'),
  ('EX-ZA', 'Sudáfrica', 'África'),
  ('EX-SD', 'Sudán', 'África'),
  ('EX-SS', 'Sudán del Sur', 'África'),
  ('EX-SE', 'Suecia', 'Europa'),
  ('EX-CH', 'Suiza', 'Europa'),
  ('EX-SR', 'Surinam', 'Sudamérica'),
  ('EX-TH', 'Tailandia', 'Asia'),
  ('EX-TZ', 'Tanzania', 'África'),
  ('EX-TJ', 'Tayikistán', 'Asia'),
  ('EX-PS', 'Territorios Palestinos', 'Asia'),
  ('EX-TL', 'Timor-Leste', 'Asia'),
  ('EX-TG', 'Togo', 'África'),
  ('EX-TO', 'Tonga', 'Oceanía'),
  ('EX-TT', 'Trinidad y Tobago', 'Centroamérica y Caribe'),
  ('EX-TM', 'Turkmenistán', 'Asia'),
  ('EX-TR', 'Turquía', 'Asia'),
  ('EX-TV', 'Tuvalu', 'Oceanía'),
  ('EX-TN', 'Túnez', 'África'),
  ('EX-UA', 'Ucrania', 'Europa'),
  ('EX-UG', 'Uganda', 'África'),
  ('EX-UY', 'Uruguay', 'Sudamérica'),
  ('EX-UZ', 'Uzbekistán', 'Asia'),
  ('EX-VU', 'Vanuatu', 'Oceanía'),
  ('EX-VE', 'Venezuela', 'Sudamérica'),
  ('EX-VN', 'Vietnam', 'Asia'),
  ('EX-YE', 'Yemen', 'Asia'),
  ('EX-DJ', 'Yibuti', 'África'),
  ('EX-ZM', 'Zambia', 'África'),
  ('EX-ZW', 'Zimbabue', 'África')
on conflict (id) do update set nombre = excluded.nombre, continente = excluded.continente;
