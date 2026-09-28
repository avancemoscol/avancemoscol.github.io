-- =============================================================================
-- Migración 0004: Políticas de Seguridad a Nivel de Fila (RLS)
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- Habilitar RLS en absolutamente todas las tablas
alter table public.departamentos enable row level security;
alter table public.municipios enable row level security;
alter table public.localidades_bogota enable row level security;
alter table public.perfiles enable row level security;
alter table public.perfiles_privados enable row level security;
alter table public.user_roles enable row level security;
alter table public.solicitudes enable row level security;
alter table public.consentimientos enable row level security;
alter table public.seguidores enable row level security;
alter table public.bloqueos enable row level security;
alter table public.publicaciones enable row level security;
alter table public.publicacion_media enable row level security;
alter table public.comentarios enable row level security;
alter table public.me_gusta enable row level security;
alter table public.me_gusta_comentario enable row level security;
alter table public.guardados enable row level security;
alter table public.hashtags enable row level security;
alter table public.publicacion_hashtags enable row level security;
alter table public.menciones enable row level security;
alter table public.conversaciones enable row level security;
alter table public.conversacion_participantes enable row level security;
alter table public.mensajes enable row level security;
alter table public.grupos_whatsapp enable row level security;
alter table public.eventos enable row level security;
alter table public.evento_asistentes enable row level security;
alter table public.solicitudes_verificacion enable row level security;
alter table public.anuncios enable row level security;
alter table public.reportes enable row level security;
alter table public.sanciones enable row level security;
alter table public.apelaciones enable row level security;
alter table public.palabras_bloqueadas enable row level security;
alter table public.auditoria enable row level security;
alter table public.notificaciones enable row level security;
alter table public.configuracion enable row level security;
alter table public.paginas enable row level security;
alter table public.paginas_versiones enable row level security;
alter table public.propuestas enable row level security;
alter table public.referentes enable row level security;
alter table public.media enable row level security;
alter table public.ia_trabajos enable row level security;
alter table public.ia_uso_diario enable row level security;
alter table public.vistas_previas_enlace enable row level security;
alter table public.casos_soporte enable row level security;
alter table public.caso_mensajes enable row level security;

-- -----------------------------------------------------------------------------
-- 1. Tablas de Catálogo y Territorio (Lectura pública)
-- -----------------------------------------------------------------------------
create policy "departamentos_lectura_publica" on public.departamentos
  for select using (true);

create policy "municipios_lectura_publica" on public.municipios
  for select using (true);

create policy "localidades_bogota_lectura_publica" on public.localidades_bogota
  for select using (true);

-- -----------------------------------------------------------------------------
-- 2. Perfiles y Datos Personales
-- -----------------------------------------------------------------------------
create policy "ver_perfiles" on public.perfiles for select using (
  (estado = 'activo' and (perfil_publico or (select public.es_miembro_activo())))
  or id = (select auth.uid())
  or (select public.puede_moderar(departamento_id))
);

create policy "actualizar_propio_perfil" on public.perfiles for update using (
  id = (select auth.uid())
) with check (
  id = (select auth.uid())
);

-- Restricción de columnas en perfiles: El usuario solo puede actualizar estas
revoke update on public.perfiles from anon, authenticated;
grant update (nombre, bio, avatar_path, portada_path, intereses, redes, ocupacion,
              perfil_publico, mostrar_municipio, dm_permitidos)
  on public.perfiles to authenticated;

create policy "ver_perfiles_privados" on public.perfiles_privados for select using (
  id = (select auth.uid())
  or exists (
    select 1 from public.perfiles p
    where p.id = perfiles_privados.id
      and (select public.puede_moderar(p.departamento_id))
  )
);

create policy "editar_perfil_privado" on public.perfiles_privados for update using (
  id = (select auth.uid())
);

create policy "ver_user_roles" on public.user_roles for select using (
  user_id = (select auth.uid())
  or (select public.puede_moderar(departamento_id))
  or (select public.es_miembro_activo())
);

create policy "ver_solicitudes" on public.solicitudes for select using (
  user_id = (select auth.uid())
  or (select public.puede_moderar(departamento_id))
);

create policy "insertar_solicitudes" on public.solicitudes for insert with check (
  user_id = (select auth.uid())
);

create policy "ver_consentimientos" on public.consentimientos for select using (
  user_id = (select auth.uid()) or (select public.es_admin_nacional())
);

create policy "insertar_consentimientos" on public.consentimientos for insert with check (
  user_id = (select auth.uid())
);

create policy "ver_seguidores" on public.seguidores for select using (true);
create policy "gestionar_seguidores" on public.seguidores for all using (
  seguidor_id = (select auth.uid())
) with check (
  seguidor_id = (select auth.uid())
);

create policy "gestionar_bloqueos" on public.bloqueos for all using (
  bloqueador_id = (select auth.uid())
) with check (
  bloqueador_id = (select auth.uid())
);

-- -----------------------------------------------------------------------------
-- 3. Publicaciones y Contenido
-- -----------------------------------------------------------------------------
create policy "ver_publicaciones" on public.publicaciones for select using (
  (estado = 'aprobado' and publicado_en <= now() and eliminado_en is null
     and (visibilidad = 'publica' or (select public.es_miembro_activo())))
  or autor_id = (select auth.uid())
  or (select public.puede_moderar(departamento_moderacion))
);

create policy "crear_publicaciones" on public.publicaciones for insert with check (
  autor_id = (select auth.uid()) and (select public.puede_interactuar())
);

create policy "actualizar_publicaciones" on public.publicaciones for update using (
  autor_id = (select auth.uid()) and (select public.puede_interactuar())
);

create policy "ver_publicacion_media" on public.publicacion_media for select using (
  exists (
    select 1 from public.publicaciones p
    where p.id = publicacion_media.publicacion_id
  )
);

create policy "ver_comentarios" on public.comentarios for select using (
  estado = 'visible' or autor_id = (select auth.uid())
  or exists (
    select 1 from public.publicaciones p
    where p.id = comentarios.publicacion_id and (select public.puede_moderar(p.departamento_moderacion))
  )
);

create policy "insertar_comentarios" on public.comentarios for insert with check (
  autor_id = (select auth.uid()) and (select public.puede_interactuar())
);

create policy "actualizar_propios_comentarios" on public.comentarios for update using (
  autor_id = (select auth.uid())
);

create policy "gestionar_me_gusta" on public.me_gusta for all using (
  user_id = (select auth.uid()) and (select public.puede_interactuar())
) with check (
  user_id = (select auth.uid())
);

create policy "gestionar_me_gusta_comentario" on public.me_gusta_comentario for all using (
  user_id = (select auth.uid()) and (select public.puede_interactuar())
) with check (
  user_id = (select auth.uid())
);

create policy "gestionar_guardados" on public.guardados for all using (
  user_id = (select auth.uid())
) with check (
  user_id = (select auth.uid())
);

create policy "ver_hashtags" on public.hashtags for select using (true);
create policy "ver_pub_hashtags" on public.publicacion_hashtags for select using (true);
create policy "ver_menciones" on public.menciones for select using (true);

-- -----------------------------------------------------------------------------
-- 4. Mensajería Directa (Privacidad Estricta: ¡Nadie fuera de la conversación!)
-- -----------------------------------------------------------------------------
create policy "participante_ver_conversacion" on public.conversaciones for select using (
  exists (
    select 1 from public.conversacion_participantes cp
    where cp.conversacion_id = conversaciones.id and cp.user_id = (select auth.uid())
  )
);

create policy "participante_ver_participantes" on public.conversacion_participantes for select using (
  user_id = (select auth.uid()) or exists (
    select 1 from public.conversacion_participantes cp
    where cp.conversacion_id = conversacion_participantes.conversacion_id and cp.user_id = (select auth.uid())
  )
);

create policy "participante_ver_mensajes" on public.mensajes for select using (
  exists (
    select 1 from public.conversacion_participantes cp
    where cp.conversacion_id = mensajes.conversacion_id and cp.user_id = (select auth.uid())
  )
);

create policy "participante_enviar_mensaje" on public.mensajes for insert with check (
  autor_id = (select auth.uid()) and exists (
    select 1 from public.conversacion_participantes cp
    where cp.conversacion_id = mensajes.conversacion_id and cp.user_id = (select auth.uid())
  ) and (select public.puede_interactuar())
);

-- -----------------------------------------------------------------------------
-- 5. Grupos de WhatsApp y Eventos
-- -----------------------------------------------------------------------------
-- Regla de oro: WhatsApp NUNCA en sitio público, solo miembros activos
create policy "ver_grupos_whatsapp" on public.grupos_whatsapp for select using (
  (estado = 'aprobado' and (select public.es_miembro_activo()))
  or creado_por = (select auth.uid())
  or (select public.puede_moderar(departamento_moderacion))
);

create policy "insertar_grupos_whatsapp" on public.grupos_whatsapp for insert with check (
  creado_por = (select auth.uid()) and (select public.es_miembro_activo())
);

create policy "ver_eventos" on public.eventos for select using (
  (estado = 'aprobado' and (visibilidad = 'publica' or (select public.es_miembro_activo())))
  or organizador_id = (select auth.uid())
  or (select public.puede_moderar(departamento_moderacion))
);

create policy "insertar_eventos" on public.eventos for insert with check (
  organizador_id = (select auth.uid()) and (select public.es_miembro_activo())
);

create policy "ver_evento_asistentes" on public.evento_asistentes for select using (
  (select public.es_miembro_activo()) or user_id = (select auth.uid())
);

create policy "gestionar_asistencia_evento" on public.evento_asistentes for all using (
  user_id = (select auth.uid())
) with check (
  user_id = (select auth.uid())
);

create policy "ver_solicitudes_verificacion" on public.solicitudes_verificacion for select using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.perfiles p
    where p.id = solicitudes_verificacion.user_id and (select public.puede_moderar(p.departamento_id))
  )
);

create policy "ver_anuncios" on public.anuncios for select using (
  (select public.es_miembro_activo())
);

-- -----------------------------------------------------------------------------
-- 6. Moderación, Auditoría, Notificaciones
-- -----------------------------------------------------------------------------
create policy "ver_reportes" on public.reportes for select using (
  reportado_por = (select auth.uid()) or (select public.puede_moderar(departamento_moderacion))
);

create policy "insertar_reportes" on public.reportes for insert with check (
  reportado_por = (select auth.uid())
);

create policy "ver_sanciones" on public.sanciones for select using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.perfiles p
    where p.id = sanciones.user_id and (select public.puede_moderar(p.departamento_id))
  )
);

create policy "ver_apelaciones" on public.apelaciones for select using (
  user_id = (select auth.uid())
  or (select public.es_admin_nacional())
);

create policy "insertar_apelaciones" on public.apelaciones for insert with check (
  user_id = (select auth.uid())
);

create policy "ver_auditoria" on public.auditoria for select using (
  (select public.es_admin_nacional()) or (select public.puede_moderar(departamento_id))
);

create policy "ver_propias_notificaciones" on public.notificaciones for select using (
  user_id = (select auth.uid())
);

create policy "actualizar_propias_notificaciones" on public.notificaciones for update using (
  user_id = (select auth.uid())
);

create policy "ver_configuracion" on public.configuracion for select using (true);

-- -----------------------------------------------------------------------------
-- 7. CMS y Medios Públicos
-- -----------------------------------------------------------------------------
create policy "paginas_lectura_publica" on public.paginas for select using (publicada);
create policy "propuestas_lectura_publica" on public.propuestas for select using (publicada);
create policy "referentes_lectura_publica" on public.referentes for select using (publicado);
create policy "media_lectura_publica" on public.media for select using (true);
create policy "vistas_previas_lectura_publica" on public.vistas_previas_enlace for select using (true);

-- -----------------------------------------------------------------------------
-- 8. Casos de Soporte y Resolvedor de Dudas
-- -----------------------------------------------------------------------------
create policy "ver_casos_soporte" on public.casos_soporte for select using (
  user_id = (select auth.uid())
  or (select public.es_admin_nacional())
  or (select public.puede_moderar(departamento_id))
);

create policy "insertar_casos_soporte" on public.casos_soporte for insert with check (
  true -- Cualquier visitante o usuario puede radicar un caso de soporte
);

create policy "ver_caso_mensajes" on public.caso_mensajes for select using (
  exists (
    select 1 from public.casos_soporte cs
    where cs.id = caso_mensajes.caso_id
      and (
        cs.user_id = (select auth.uid())
        or (select public.es_admin_nacional())
        or (select public.puede_moderar(cs.departamento_id))
      )
  )
);
