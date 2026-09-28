-- =============================================================================
-- Migración 0002: Tablas e Índices
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- Función inmutable auxiliar para unaccent en columnas generadas
create or replace function public.f_unaccent(text)
returns text language sql immutable strict parallel safe as $$
  select public.unaccent('public.unaccent', $1);
$$;

-- -----------------------------------------------------------------------------
-- 1. Territorio (DIVIPOLA DANE)
-- -----------------------------------------------------------------------------
create table if not exists public.departamentos (
  id text primary key, -- 2 dígitos (ej. 05, 11)
  nombre text not null,
  slug text not null unique,
  region text not null,
  capital_id text
);

create table if not exists public.municipios (
  id text primary key, -- 5 dígitos (ej. 05001)
  departamento_id text not null references public.departamentos(id) on delete cascade,
  nombre text not null,
  slug text not null,
  es_capital boolean not null default false
);

create table if not exists public.localidades_bogota (
  id smallint primary key, -- 1 a 20
  nombre text not null
);

-- -----------------------------------------------------------------------------
-- 2. Personas y Cuentas
-- -----------------------------------------------------------------------------
create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tipo_cuenta text not null default 'persona' check (tipo_cuenta in ('persona', 'oficial')),
  username public.citext not null unique check (username ~ '^[a-z0-9_]{3,30}$'),
  nombre text not null,
  bio text check (char_length(bio) <= 280),
  avatar_path text,
  portada_path text,
  departamento_id text references public.departamentos(id),
  municipio_id text references public.municipios(id),
  localidad_id smallint references public.localidades_bogota(id),
  cargo_titulo text,
  ocupacion text,
  intereses text[] default '{}',
  redes jsonb default '{}'::jsonb,
  estado public.estado_cuenta not null default 'pendiente',
  insignia public.insignia not null default 'ninguna',
  insignia_suspendida boolean not null default false,
  insignia_otorgada_por uuid references auth.users(id),
  insignia_otorgada_en timestamptz,
  perfil_publico boolean not null default false,
  mostrar_municipio boolean not null default true,
  dm_permitidos text not null default 'seguidos' check (dm_permitidos in ('todos', 'seguidos', 'nadie')),
  seguidores_n integer not null default 0,
  siguiendo_n integer not null default 0,
  publicaciones_n integer not null default 0,
  ultimo_cambio_usuario timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.perfiles_privados (
  id uuid primary key references public.perfiles(id) on delete cascade,
  telefono text,
  notas_admin text
);

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  rol public.rol_app not null,
  departamento_id text references public.departamentos(id) on delete set null,
  municipio_id text references public.municipios(id) on delete set null,
  titulo text,
  activo boolean not null default true,
  otorgado_por uuid references public.perfiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, rol, departamento_id, municipio_id)
);

create table if not exists public.solicitudes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  tipo text not null check (tipo in ('ingreso', 'cambio_rol', 'traslado')),
  rol_solicitado public.rol_app not null default 'simpatizante',
  departamento_id text references public.departamentos(id),
  municipio_id text references public.municipios(id),
  motivo text check (char_length(motivo) <= 500),
  estado public.estado_revision not null default 'pendiente',
  revisado_por uuid references public.perfiles(id),
  revisado_en timestamptz,
  comentario_admin text,
  created_at timestamptz not null default now()
);

create table if not exists public.consentimientos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  version_politica text not null default '1.0',
  acepta_terminos boolean not null,
  autoriza_datos_sensibles boolean not null,
  mayor_de_edad boolean not null,
  user_agent text,
  created_at timestamptz not null default now()
);

create table if not exists public.seguidores (
  seguidor_id uuid not null references public.perfiles(id) on delete cascade,
  seguido_id uuid not null references public.perfiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (seguidor_id, seguido_id),
  check (seguidor_id <> seguido_id)
);

create table if not exists public.bloqueos (
  bloqueador_id uuid not null references public.perfiles(id) on delete cascade,
  bloqueado_id uuid not null references public.perfiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bloqueador_id, bloqueado_id),
  check (bloqueador_id <> bloqueado_id)
);

-- -----------------------------------------------------------------------------
-- 3. Contenido (Publicaciones, Comentarios, Me gusta, Guardados)
-- -----------------------------------------------------------------------------
create table if not exists public.publicaciones (
  id uuid primary key default gen_random_uuid(),
  autor_id uuid not null references public.perfiles(id) on delete cascade,
  contenido text not null check (char_length(contenido) <= 3000),
  categoria text not null default 'opinion' check (categoria in ('opinion', 'propuesta', 'noticia', 'convocatoria', 'logro', 'pregunta')),
  alcance public.alcance not null default 'departamental',
  departamento_id text references public.departamentos(id),
  municipio_id text references public.municipios(id),
  departamento_moderacion text references public.departamentos(id), -- NULL = nacional
  visibilidad public.visibilidad not null default 'publica',
  estado public.estado_revision not null default 'pendiente',
  motivo_revision text,
  revisado_por uuid references public.perfiles(id),
  revisado_en timestamptz,
  escalado_a_nacional boolean not null default false,
  publicado_en timestamptz,
  programada_para timestamptz,
  es_oficial boolean not null default false,
  publicado_por uuid references public.perfiles(id), -- Admin real cuando es oficial
  fijada boolean not null default false,
  enlace_url text,
  enlace_preview jsonb,
  repost_de uuid references public.publicaciones(id) on delete set null,
  ia_moderacion jsonb,
  me_gusta_n integer not null default 0,
  comentarios_n integer not null default 0,
  compartidos_n integer not null default 0,
  busqueda tsvector generated always as (
    to_tsvector('spanish', public.f_unaccent(coalesce(contenido, '')))
  ) stored,
  eliminado_en timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.publicacion_media (
  id uuid primary key default gen_random_uuid(),
  publicacion_id uuid not null references public.publicaciones(id) on delete cascade,
  tipo text not null check (tipo in ('imagen', 'video')),
  bucket text not null,
  path text not null,
  ancho integer,
  alto integer,
  duracion_s numeric(6,2),
  alt_text text,
  orden smallint not null default 0,
  generada_ia boolean not null default false
);

create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid(),
  publicacion_id uuid not null references public.publicaciones(id) on delete cascade,
  autor_id uuid not null references public.perfiles(id) on delete cascade,
  padre_id uuid references public.comentarios(id) on delete cascade,
  contenido text not null check (char_length(contenido) <= 1000),
  estado text not null default 'visible' check (estado in ('visible', 'oculto', 'eliminado')),
  marcado_revision boolean not null default false,
  me_gusta_n integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.me_gusta (
  publicacion_id uuid not null references public.publicaciones(id) on delete cascade,
  user_id uuid not null references public.perfiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (publicacion_id, user_id)
);

create table if not exists public.me_gusta_comentario (
  comentario_id uuid not null references public.comentarios(id) on delete cascade,
  user_id uuid not null references public.perfiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comentario_id, user_id)
);

create table if not exists public.guardados (
  user_id uuid not null references public.perfiles(id) on delete cascade,
  publicacion_id uuid not null references public.publicaciones(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, publicacion_id)
);

create table if not exists public.hashtags (
  tag text primary key check (tag ~ '^[a-z0-9_]{2,50}$')
);

create table if not exists public.publicacion_hashtags (
  publicacion_id uuid not null references public.publicaciones(id) on delete cascade,
  tag text not null references public.hashtags(tag) on delete cascade,
  primary key (publicacion_id, tag)
);

create table if not exists public.menciones (
  id uuid primary key default gen_random_uuid(),
  publicacion_id uuid references public.publicaciones(id) on delete cascade,
  comentario_id uuid references public.comentarios(id) on delete cascade,
  mencionado_id uuid not null references public.perfiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 4. Mensajería Directa y Conversaciones
-- -----------------------------------------------------------------------------
create table if not exists public.conversaciones (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  ultimo_mensaje_en timestamptz not null default now(),
  ultimo_mensaje_preview text
);

create table if not exists public.conversacion_participantes (
  conversacion_id uuid not null references public.conversaciones(id) on delete cascade,
  user_id uuid not null references public.perfiles(id) on delete cascade,
  ultimo_leido_en timestamptz not null default now(),
  silenciada boolean not null default false,
  primary key (conversacion_id, user_id)
);

create table if not exists public.mensajes (
  id uuid primary key default gen_random_uuid(),
  conversacion_id uuid not null references public.conversaciones(id) on delete cascade,
  autor_id uuid not null references public.perfiles(id) on delete cascade,
  contenido text not null check (char_length(contenido) <= 2000),
  media_path text,
  eliminado boolean not null default false,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 5. Organización Territorial (Grupos WhatsApp, Eventos, Verificación)
-- -----------------------------------------------------------------------------
create table if not exists public.grupos_whatsapp (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  descripcion text check (char_length(descripcion) <= 500),
  tipo text not null default 'grupo' check (tipo in ('grupo', 'comunidad', 'canal')),
  tema text not null default 'general',
  alcance public.alcance not null default 'departamental',
  departamento_id text references public.departamentos(id),
  municipio_id text references public.municipios(id),
  departamento_moderacion text references public.departamentos(id),
  url text not null unique check (
    url ~ '^https://chat\.whatsapp\.com/[A-Za-z0-9]{20,24}$' or
    url ~ '^https://(www\.)?whatsapp\.com/channel/[A-Za-z0-9]+$'
  ),
  creado_por uuid not null references public.perfiles(id) on delete cascade,
  estado public.estado_revision not null default 'pendiente',
  motivo_revision text,
  revisado_por uuid references public.perfiles(id),
  revisado_en timestamptz,
  escalado_a_nacional boolean not null default false,
  ia_moderacion jsonb,
  reportes_enlace_roto smallint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.eventos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text not null,
  tipo text not null default 'reunion' check (tipo in ('reunion', 'foro', 'capacitacion', 'voluntariado', 'virtual')),
  inicio timestamptz not null,
  fin timestamptz,
  modalidad text not null default 'presencial' check (modalidad in ('presencial', 'virtual', 'mixta')),
  lugar text,
  direccion text,
  lat numeric(10, 7),
  lng numeric(10, 7),
  url_virtual text,
  direccion_solo_inscritos boolean not null default false,
  cupo integer,
  imagen_path text,
  alcance public.alcance not null default 'departamental',
  departamento_id text references public.departamentos(id),
  municipio_id text references public.municipios(id),
  departamento_moderacion text references public.departamentos(id),
  visibilidad public.visibilidad not null default 'publica',
  organizador_id uuid not null references public.perfiles(id) on delete cascade,
  estado public.estado_revision not null default 'pendiente',
  motivo_revision text,
  revisado_por uuid references public.perfiles(id),
  revisado_en timestamptz,
  escalado_a_nacional boolean not null default false,
  ia_moderacion jsonb,
  asistentes_n integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.evento_asistentes (
  evento_id uuid not null references public.eventos(id) on delete cascade,
  user_id uuid not null references public.perfiles(id) on delete cascade,
  respuesta text not null check (respuesta in ('voy', 'interesado')),
  created_at timestamptz not null default now(),
  primary key (evento_id, user_id)
);

create table if not exists public.solicitudes_verificacion (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  insignia_solicitada public.insignia not null,
  cargo text not null,
  motivo text not null,
  enlaces text[] default '{}',
  metodo_preferido text not null default 'videollamada' check (metodo_preferido in ('videollamada', 'presencial')),
  es_revalidacion boolean not null default false,
  estado public.estado_revision not null default 'pendiente',
  metodo_usado text,
  notas_internas text,
  revisado_por uuid references public.perfiles(id),
  revisado_en timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.anuncios (
  id uuid primary key default gen_random_uuid(),
  autor_id uuid not null references public.perfiles(id) on delete cascade,
  titulo text not null,
  cuerpo text not null,
  departamento_id text references public.departamentos(id), -- NULL = nacional
  roles_destino public.rol_app[] default '{}',
  enviar_correo boolean not null default false,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 6. Moderación, Control, Sanciones, Auditoría
-- -----------------------------------------------------------------------------
create table if not exists public.reportes (
  id uuid primary key default gen_random_uuid(),
  reportado_por uuid not null references public.perfiles(id) on delete cascade,
  entidad text not null check (entidad in ('publicacion', 'comentario', 'mensaje', 'perfil', 'grupo', 'evento')),
  entidad_id text not null,
  motivo text not null check (motivo in (
    'odio', 'acoso', 'amenaza_seguridad', 'violencia', 'desinformacion',
    'spam', 'datos_personales', 'suplantacion', 'sexual', 'enlace_roto', 'otro'
  )),
  detalle text,
  snapshot jsonb not null default '{}'::jsonb,
  departamento_moderacion text references public.departamentos(id),
  escalado_a_nacional boolean not null default false,
  prioridad text not null default 'normal' check (prioridad in ('normal', 'alta')),
  estado text not null default 'abierto' check (estado in ('abierto', 'en_revision', 'resuelto', 'descartado')),
  resuelto_por uuid references public.perfiles(id),
  resolucion text,
  created_at timestamptz not null default now()
);

create table if not exists public.sanciones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  tipo text not null check (tipo in ('advertencia', 'silencio', 'suspension', 'baneo')),
  motivo text not null,
  hasta timestamptz,
  impuesta_por uuid not null references public.perfiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.apelaciones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  entidad text not null check (entidad in ('publicacion', 'sancion', 'verificacion', 'solicitud')),
  entidad_id text not null,
  texto text not null,
  estado public.estado_revision not null default 'pendiente',
  resuelta_por uuid references public.perfiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.palabras_bloqueadas (
  palabra text primary key,
  nivel text not null default 'bloquear' check (nivel in ('bloquear', 'revisar'))
);

create table if not exists public.auditoria (
  id bigint generated always as identity primary key,
  actor_id uuid references public.perfiles(id) on delete set null,
  accion text not null,
  entidad text not null,
  entidad_id text not null,
  departamento_id text references public.departamentos(id),
  antes jsonb,
  despues jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.notificaciones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  tipo text not null,
  actor_id uuid references public.perfiles(id) on delete set null,
  entidad text,
  entidad_id text,
  texto text not null,
  agrupadas_n integer not null default 1,
  leida boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.configuracion (
  clave text primary key,
  valor jsonb not null,
  updated_by uuid references public.perfiles(id),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 7. CMS del Sitio Público y Medios
-- -----------------------------------------------------------------------------
create table if not exists public.paginas (
  slug text primary key,
  titulo text not null,
  contenido_md text not null,
  seo_titulo text,
  seo_descripcion text,
  publicada boolean not null default true,
  updated_by uuid references public.perfiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.paginas_versiones (
  id uuid primary key default gen_random_uuid(),
  slug text not null references public.paginas(slug) on delete cascade,
  contenido_md text not null,
  created_by uuid references public.perfiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.propuestas (
  id uuid primary key default gen_random_uuid(),
  eje text not null,
  titulo text not null,
  resumen text not null,
  detalle_md text not null,
  icono text not null default 'sparkles',
  orden smallint not null default 0,
  publicada boolean not null default false
);

create table if not exists public.referentes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  ambito text not null check (ambito in ('colombia', 'mundo')),
  pais text not null default 'Colombia',
  orientacion text not null,
  cargos text not null,
  logros text[] not null default '{}',
  contexto text,
  leccion text not null,
  fuentes text[] not null default '{}',
  imagen_path text,
  credito_imagen text,
  orden smallint not null default 0,
  publicado boolean not null default false
);

create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),
  bucket text not null,
  path text not null,
  tipo text not null check (tipo in ('imagen', 'video')),
  mime text not null,
  ancho integer,
  alto integer,
  duracion_s numeric(6,2),
  origen text not null check (origen in ('subida', 'ia_imagen', 'ia_video', 'ia_edicion')),
  prompt text,
  prompt_final text,
  modelo text,
  etiqueta_ia boolean not null default false,
  creado_por uuid references public.perfiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.ia_trabajos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('imagen', 'video', 'texto')),
  estado text not null default 'en_cola' check (estado in ('en_cola', 'procesando', 'completado', 'error')),
  operacion text,
  parametros jsonb not null default '{}'::jsonb,
  media_ids uuid[] default '{}',
  error text,
  costo_estimado_usd numeric(8,4) default 0,
  solicitado_por uuid not null references public.perfiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  completado_en timestamptz
);

create table if not exists public.ia_uso_diario (
  user_id uuid not null references public.perfiles(id) on delete cascade,
  fecha date not null default current_date,
  imagenes smallint not null default 0,
  videos smallint not null default 0,
  textos smallint not null default 0,
  primary key (user_id, fecha)
);

create table if not exists public.vistas_previas_enlace (
  url text primary key,
  titulo text,
  descripcion text,
  imagen text,
  sitio text,
  obtenida_en timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 8. Sistema de Soporte y Resolvedor de Dudas (Requerimiento especial)
-- -----------------------------------------------------------------------------
create table if not exists public.casos_soporte (
  id uuid primary key default gen_random_uuid(),
  numero_radicado text not null unique,
  user_id uuid references public.perfiles(id) on delete set null,
  nombre_contacto text not null,
  correo_contacto public.citext not null,
  telefono_contacto text,
  tipo_usuario text not null check (tipo_usuario in ('visitante', 'inscrito_pendiente', 'miembro_activo')),
  categoria text not null check (categoria in (
    'inscripcion', 'verificacion', 'territorio_grupo', 'moderacion_apelacion',
    'problema_tecnico', 'pregunta_politica', 'otro'
  )),
  asunto text not null,
  descripcion text not null,
  estado text not null default 'abierto' check (estado in ('abierto', 'en_proceso', 'esperando_usuario', 'resuelto', 'cerrado')),
  prioridad text not null default 'media' check (prioridad in ('baja', 'media', 'alta', 'urgente')),
  departamento_id text references public.departamentos(id),
  asignado_a uuid references public.perfiles(id),
  respuesta_oficial text,
  ia_sugerencia_respuesta text,
  resuelto_por uuid references public.perfiles(id),
  resuelto_en timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.caso_mensajes (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references public.casos_soporte(id) on delete cascade,
  autor_id uuid references public.perfiles(id) on delete set null,
  es_equipo boolean not null default false,
  es_ia boolean not null default false,
  mensaje text not null,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 9. Índices de rendimiento
-- -----------------------------------------------------------------------------
create index if not exists idx_publicaciones_feed
  on public.publicaciones (estado, publicado_en desc, id desc);

create index if not exists idx_publicaciones_departamento
  on public.publicaciones (departamento_id, estado, publicado_en desc);

create index if not exists idx_publicaciones_municipio
  on public.publicaciones (municipio_id, estado, publicado_en desc);

create index if not exists idx_publicaciones_autor
  on public.publicaciones (autor_id, created_at desc);

create index if not exists idx_publicaciones_pendientes_moderacion
  on public.publicaciones (departamento_moderacion)
  where estado = 'pendiente';

create index if not exists idx_publicaciones_busqueda
  on public.publicaciones using gin (busqueda);

create index if not exists idx_perfiles_username_trgm
  on public.perfiles using gin (username gin_trgm_ops);

create index if not exists idx_perfiles_nombre_trgm
  on public.perfiles using gin (nombre gin_trgm_ops);

create index if not exists idx_user_roles_activos
  on public.user_roles (user_id)
  where activo;

create index if not exists idx_comentarios_publicacion
  on public.comentarios (publicacion_id, created_at);

create index if not exists idx_mensajes_conversacion
  on public.mensajes (conversacion_id, created_at desc);

create index if not exists idx_notificaciones_usuario
  on public.notificaciones (user_id, leida, created_at desc);

create index if not exists idx_seguidores_seguido
  on public.seguidores (seguido_id);

create index if not exists idx_casos_soporte_radicado
  on public.casos_soporte (numero_radicado);

create index if not exists idx_casos_soporte_correo
  on public.casos_soporte (correo_contacto);

create index if not exists idx_casos_soporte_estado
  on public.casos_soporte (estado, prioridad, created_at desc);
