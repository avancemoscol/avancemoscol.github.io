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
    const { data, error } = await supabase.rpc("admin_solicitudes_pendientes", { p_depto: deptoId });
    if (error) throw error;
    return (data || []).map(s => ({ ...s, perfil: { nombre: s.nombre, username: s.username, ocupacion: s.ocupacion, correo: s.correo } }));
  }

  if (tab === "publicaciones") {
    const { data, error } = await supabase.rpc("admin_publicaciones", { p_estado: "pendiente", p_depto: deptoId });
    if (error) throw error;
    return (data || []).map(p => ({ ...p, autor: { nombre: p.autor_nombre, username: p.autor_username, insignia: p.autor_insignia } }));
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
        creador:perfiles!grupos_whatsapp_creado_por_fkey (nombre:primer_nombre, username)
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
      actor:perfiles!auditoria_actor_id_fkey (nombre:primer_nombre, username)
    `);

  if (deptoId) q = q.eq("departamento_id", deptoId);
  const { data, error } = await q.order("created_at", { ascending: false }).limit(limite);
  if (error) throw error;
  return data || [];
}

// ---------------------------------------------------------------------------
// Gestión avanzada (usuarios, publicaciones, eventos, anuncios, grupos)
// ---------------------------------------------------------------------------
async function rpc(nombre, args = {}) {
  const { data, error } = await supabase.rpc(nombre, args);
  if (error) throw error;
  return data;
}

export const listarUsuarios = (busqueda, depto, estado) =>
  rpc("admin_listar_usuarios", { p_busqueda: busqueda || null, p_depto: depto || null, p_estado: estado || null, p_limite: 100 });
export const actualizarUsuario = (id, datos) => rpc("admin_actualizar_usuario", { p_id: id, p_datos: datos });
export const asignarRol = (userId, rol, deptoId, titulo, activo = true) =>
  rpc("admin_asignar_rol", { p_user_id: userId, p_rol: rol, p_departamento_id: deptoId || null, p_titulo: titulo || null, p_activo: activo });
export const otorgarInsignia = (userId, insignia) => rpc("otorgar_insignia", { p_user_id: userId, p_insignia: insignia });

export const listarPublicacionesAdmin = (estado, depto, busqueda) =>
  rpc("admin_publicaciones", { p_estado: estado || null, p_depto: depto || null, p_busqueda: busqueda || null, p_limite: 100 });
export const listarComentariosAdmin = (pubId) => rpc("admin_comentarios", { p_publicacion_id: pubId });
export const moderarComentario = (id, estado) => rpc("admin_moderar_comentario", { p_id: id, p_estado: estado });
export const eliminarPublicacionAdmin = (id) => rpc("eliminar_publicacion", { p_id: id });

export const listarEventosAdmin = () => rpc("admin_eventos");
export const guardarEvento = (id, datos) => rpc("admin_guardar_evento", { p_id: id || null, p_datos: datos });
export const resolverEvento = (id, accion) => rpc("admin_resolver_evento", { p_id: id, p_accion: accion });

export const listarAnunciosAdmin = () => rpc("admin_anuncios");
export const guardarAnuncio = (id, datos) => rpc("admin_guardar_anuncio", { p_id: id || null, p_datos: datos });
export const eliminarAnuncio = (id) => rpc("admin_eliminar_anuncio", { p_id: id });
export const resultadosAnuncio = (id) => rpc("resultados_anuncio", { p_anuncio_id: id });

export const guardarGrupo = (id, datos) => rpc("admin_guardar_grupo", { p_id: id || null, p_datos: datos });
export const eliminarGrupo = (id) => rpc("admin_eliminar_grupo", { p_id: id });
