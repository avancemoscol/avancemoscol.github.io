-- =============================================================================
-- Migración 0007: Tareas Programadas y Mantenimiento Periódico
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

create or replace function public.limpieza_mantenimiento_diario()
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- 1. Marcar eventos pasados
  -- (se mantiene el registro pero se pueden actualizar estados si se requiere)

  -- 2. Limpiar registros de auditoría muy antiguos si la política de retención lo define
  -- En Avancemos la auditoría se conserva por seguridad e integridad.

  -- 3. Notificaciones de recordatorio de eventos que inician en las próximas 24 horas
  insert into public.notificaciones (user_id, tipo, entidad, entidad_id, texto)
  select
    ea.user_id,
    'recordatorio_evento',
    'evento',
    e.id::text,
    'Recordatorio: El evento "' || e.titulo || '" comenzará en menos de 24 horas.'
  from public.evento_asistentes ea
  join public.eventos e on e.id = ea.evento_id
  where e.inicio between now() and (now() + interval '24 hours')
    and not exists (
      select 1 from public.notificaciones n
      where n.user_id = ea.user_id
        and n.tipo = 'recordatorio_evento'
        and n.entidad_id = e.id::text
    );
end;
$$;

-- Intentar registrar en pg_cron si la extensión existe
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mantenimiento-diario-avancemos', '0 4 * * *', 'select public.limpieza_mantenimiento_diario();');
  end if;
exception when others then
  null;
end $$;
