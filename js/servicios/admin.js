/**
 * Servicio de Operaciones del Panel de Administración · Avancemos
 */

import { supabase } from "../supabase.js";

export async function obtenerResumenMetricas(deptoId = null) {
  // Conteo de solicitudes pendientes
  let qSolicitudes = supabase.from("solicitudes").select("id", { count: "exact", head: true }).eq("estado", "pendiente");
  let qPubs = supabase.from("publicaciones").select("id", { count: "exact", head: true }).eq("estado", "pendiente");
  let qGrupos = supabase.from("grupos_whatsapp").select("id", { count: "exact", head: true }).eq("estado", "pendiente");
  let qReportes = supabase.from("reportes").select("id", { count: "exact", head: true }).eq("estado", "abierto");
  let qCasos = supabase.from("casos_soporte").select("id", { count: "exact", head: true }).in("estado", ["abierto", "en_proceso"]);

  if (deptoId) {
    qSolicitudes = qSolicitudes.eq("departamento_id", deptoId);
    qPubs = qPubs.eq("departamento_moderacion", deptoId);
    qGrupos = qGrupos.eq("departamento_moderacion", deptoId);
    qReportes = qReportes.eq("departamento_moderacion", deptoId);
    qCasos = qCasos.eq("departamento_id", deptoId);
  }

  const [resSol, resPub, resGrup, resRep, resCas] = await Promise.all([
    qSolicitudes, qPubs, qGrupos, qReportes, qCasos
  ]);

  return {
    usuariosPendientes: resSol.count || 0,
    publicacionesPendientes: resPub.count || 0,
    gruposPendientes: resGrup.count || 0,
    reportesAbiertos: resRep.count || 0,
    casosSoporteAbiertos: resCas.count || 0
  };
}

export async function obtenerAprobacionesPendientes(tab = "usuarios", deptoId = null) {
  if (tab === "usuarios") {
    let q = supabase
      .from("solicitudes")
      .select(`
        id,
        user_id,
        rol_solicitado,
        motivo,
        created_at,
        departamento_id,
        municipio_id,
        perfil:perfiles (
          nombre,
          username,
          avatar_path,
          ocupacion,
          intereses
        )
      `)
      .eq("estado", "pendiente");
    if (deptoId) q = q.eq("departamento_id", deptoId);
    const { data, error } = await q.order("created_at", { ascending: true });
    if (error) throw error;
    return data || [];
  }

  if (tab === "publicaciones") {
    let q = supabase
      .from("publicaciones")
      .select(`
        id,
        contenido,
        categoria,
        alcance,
        visibilidad,
        created_at,
        departamento_moderacion,
        autor:perfiles (
          nombre,
          username,
          avatar_path,
          insignia
        ),
        media:publicacion_media (*)
      `)
      .eq("estado", "pendiente");
    if (deptoId) q = q.eq("departamento_moderacion", deptoId);
    const { data, error } = await q.order("created_at", { ascending: true });
    if (error) throw error;
    return data || [];
  }

  if (tab === "grupos") {
    let q = supabase
      .from("grupos_whatsapp")
      .select(`
        id,
        nombre,
        descripcion,
        tipo,
        tema,
        alcance,
        url,
        created_at,
        creador:perfiles (nombre, username)
      `)
      .eq("estado", "pendiente");
    if (deptoId) q = q.eq("departamento_moderacion", deptoId);
    const { data, error } = await q.order("created_at", { ascending: true });
    if (error) throw error;
    return data || [];
  }

  if (tab === "soporte") {
    let q = supabase
      .from("casos_soporte")
      .select(`
        id,
        numero_radicado,
        nombre_contacto,
        correo_contacto,
        telefono_contacto,
        categoria,
        asunto,
        descripcion,
        estado,
        prioridad,
        created_at
      `)
      .in("estado", ["abierto", "en_proceso"]);
    if (deptoId) q = q.eq("departamento_id", deptoId);
    const { data, error } = await q.order("created_at", { ascending: false });
    if (error) throw error;
    return data || [];
  }

  return [];
}

export async function revisarSolicitudUsuario(solicitudId, decision, rolAsignado = null, comentario = null) {
  const { data, error } = await supabase.rpc("revisar_solicitud", {
    solicitud_id: solicitudId,
    decision,
    rol_asignado: rolAsignado,
    comentario
  });
  if (error) throw error;
  return data;
}

export async function revisarPublicacion(publicacionId, decision, motivo = null) {
  const { data, error } = await supabase.rpc("revisar_publicacion", {
    publicacion_id: publicacionId,
    decision,
    motivo
  });
  if (error) throw error;
  return data;
}

export async function resolverCasoSoporteAdmin(casoId, estado, respuesta, prioridad = null) {
  const { data, error } = await supabase.rpc("resolver_caso_soporte", {
    p_caso_id: casoId,
    p_estado: estado,
    p_respuesta: respuesta,
    p_prioridad: prioridad
  });
  if (error) throw error;
  return data;
}

export async function obtenerAuditoria(deptoId = null, limite = 50) {
  let q = supabase
    .from("auditoria")
    .select(`
      id,
      accion,
      entidad,
      entidad_id,
      departamento_id,
      antes,
      despues,
      created_at,
      actor:perfiles (nombre, username)
    `);

  if (deptoId) q = q.eq("departamento_id", deptoId);
  const { data, error } = await q.order("created_at", { ascending: false }).limit(limite);
  if (error) throw error;
  return data || [];
}
