-- =============================================================================
-- Migración 0013: Solicitud de insignias sin límites de días y revisión en el panel
-- =============================================================================

-- Cualquier miembro activo puede solicitar insignia en cualquier momento
-- (se eliminó el requisito de 30 días de antigüedad y de 90 días sin sanciones).
-- Solo se evita tener dos solicitudes pendientes al mismo tiempo.
create or replace function public.solicitar_verificacion(
  p_insignia public.insignia,
  p_cargo text,
  p_motivo text,
  p_enlaces text[] default '{}',
  p_metodo text default 'videollamada'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  if not exists (select 1 from public.perfiles where id = v_uid and estado = 'activo') then
    raise exception 'Tu cuenta debe estar aprobada para solicitar una insignia.' using errcode = '42501';
  end if;
  if p_insignia = 'ninguna' then
    raise exception 'Elige el tipo de insignia.' using errcode = '22023';
  end if;
  if coalesce(btrim(p_cargo), '') = '' or coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Indica tu cargo o actividad y el motivo de la solicitud.' using errcode = '22023';
  end if;
  if exists (select 1 from public.solicitudes_verificacion where user_id = v_uid and estado = 'pendiente') then
    raise exception 'Ya tienes una solicitud de insignia en revisión.' using errcode = '23505';
  end if;

  insert into public.solicitudes_verificacion (id, user_id, insignia_solicitada, cargo, motivo, enlaces, metodo_preferido)
  values (v_id, v_uid, p_insignia, btrim(p_cargo), btrim(p_motivo), coalesce(p_enlaces, '{}'),
          case when p_metodo in ('videollamada', 'presencial') then p_metodo else 'videollamada' end);

  return v_id;
end;
$$;

-- Estado de la última solicitud del usuario (para mostrarlo en Ajustes)
create or replace function public.mi_solicitud_insignia()
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(s) - 'notas_internas' - 'revisado_por'
  from public.solicitudes_verificacion s
  where s.user_id = auth.uid()
  order by s.created_at desc
  limit 1;
$$;
grant execute on function public.mi_solicitud_insignia() to authenticated;

-- Solicitudes pendientes para el panel (con datos completos del solicitante)
create or replace function public.admin_verificaciones_pendientes(p_depto text default null)
returns table (id uuid, user_id uuid, insignia_solicitada public.insignia, cargo text, motivo text, enlaces text[],
               metodo_preferido text, created_at timestamptz, nombre text, username text, correo text,
               departamento text, insignia_actual public.insignia)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_moderador_alguno() then
    raise exception 'Acceso restringido.' using errcode = '42501';
  end if;
  return query
  select s.id, s.user_id, s.insignia_solicitada, s.cargo, s.motivo, s.enlaces, s.metodo_preferido, s.created_at,
         p.nombre, p.username::text, u.email::text, d.nombre, p.insignia
  from public.solicitudes_verificacion s
  join public.perfiles p on p.id = s.user_id
  join auth.users u on u.id = s.user_id
  left join public.departamentos d on d.id = p.departamento_id
  where s.estado = 'pendiente' and public.puede_moderar(p.departamento_id)
    and (p_depto is null or p.departamento_id = p_depto)
  order by s.created_at;
end;
$$;
grant execute on function public.admin_verificaciones_pendientes(text) to authenticated;

-- Aprobar (otorga la insignia) o rechazar una solicitud
create or replace function public.resolver_verificacion(p_id uuid, p_decision text, p_notas text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_s record;
begin
  if p_decision not in ('aprobado', 'rechazado') then
    raise exception 'Decisión no válida.' using errcode = '22023';
  end if;
  select s.*, p.departamento_id into v_s
  from public.solicitudes_verificacion s join public.perfiles p on p.id = s.user_id
  where s.id = p_id and s.estado = 'pendiente' for update of s;
  if not found then
    raise exception 'Solicitud no encontrada o ya resuelta.' using errcode = 'P0002';
  end if;
  if not public.puede_moderar(v_s.departamento_id) then
    raise exception 'No tienes permisos para revisar esta solicitud.' using errcode = '42501';
  end if;

  if p_decision = 'aprobado' then
    -- otorgar_insignia valida quién puede dar cada insignia (dorada y gris: admin nacional)
    perform public.otorgar_insignia(v_s.user_id, v_s.insignia_solicitada);
  else
    insert into public.notificaciones (user_id, tipo, actor_id, texto)
    values (v_s.user_id, 'insignia_rechazada', auth.uid(),
            'Tu solicitud de insignia no fue aprobada' || coalesce(': ' || nullif(btrim(p_notas), ''), '.') || ' Puedes volver a solicitarla cuando quieras.');
  end if;

  update public.solicitudes_verificacion
  set estado = p_decision::public.estado_revision, notas_internas = nullif(btrim(p_notas), ''),
      revisado_por = auth.uid(), revisado_en = now()
  where id = p_id;
  return true;
end;
$$;
grant execute on function public.resolver_verificacion(uuid, text, text) to authenticated;
