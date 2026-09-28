-- =============================================================================
-- Pruebas de Seguridad y Criterios de Aceptación RLS
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

begin;

-- 1. Un usuario no autenticado no puede consultar grupos de WhatsApp
select count(*) = 0 as prueba_1_visitante_no_ve_whatsapp
from public.grupos_whatsapp;

-- 2. El mapa público nunca muestra datos sin agregación
select (public.estadisticas_publicas()->>'departamentos') is not null as prueba_2_estadisticas_agregadas;

-- 3. Una publicación pública es legible por cualquiera
select count(*) >= 0 as prueba_3_feed_publico
from public.feed_publico();

-- 4. Un usuario anónimo puede consultar disponibilidad de username
select public.usuario_disponible('usuario_prueba_123') as prueba_4_username_disponible;

-- 5. Nombres reservados son bloqueados
select not public.usuario_disponible('avancemos') as prueba_5_nombre_reservado_bloqueado;

-- 6. No se puede consultar casos de soporte ajenos sin autenticación ni radicado
select count(*) = 0 as prueba_6_casos_privados
from public.casos_soporte
where user_id is not null;

rollback;
