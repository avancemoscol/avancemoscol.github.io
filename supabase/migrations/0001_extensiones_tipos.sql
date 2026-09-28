-- =============================================================================
-- Migración 0001: Extensiones y Tipos Enumerados
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- Extensiones
create extension if not exists "citext" with schema public;
create extension if not exists "unaccent" with schema public;
create extension if not exists "pg_trgm" with schema public;

-- Intentar habilitar pg_net si está disponible en la plataforma
do $$
begin
  create extension if not exists "pg_net";
exception when others then
  null; -- ignorar si no está soportado en el entorno
end $$;

-- Tipos enumerados
do $$ begin
  if not exists (select 1 from pg_type where typname = 'estado_cuenta') then
    create type public.estado_cuenta as enum (
      'pendiente',
      'activo',
      'rechazado',
      'suspendido',
      'baneado'
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'rol_app') then
    create type public.rol_app as enum (
      'simpatizante',
      'voluntario',
      'lider',
      'moderador',
      'admin_departamental',
      'admin_nacional'
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'estado_revision') then
    create type public.estado_revision as enum (
      'pendiente',
      'aprobado',
      'rechazado',
      'cambios_solicitados',
      'retirado'
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'insignia') then
    create type public.insignia as enum (
      'ninguna',
      'azul',
      'dorada',
      'gris'
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'alcance') then
    create type public.alcance as enum (
      'nacional',
      'departamental',
      'municipal'
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'visibilidad') then
    create type public.visibilidad as enum (
      'publica',
      'miembros'
    );
  end if;
end $$;
