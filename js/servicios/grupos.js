/**
 * Servicio de Grupos de WhatsApp Territoriales · Avancemos
 * Regla: Solo miembros activos pueden ver y acceder a grupos de WhatsApp.
 */

import { supabase } from "../supabase.js";

export async function obtenerGruposWhatsApp(deptoId = null) {
  let query = supabase
    .from("grupos_whatsapp")
    .select(`
      id,
      nombre,
      descripcion,
      tipo,
      tema,
      alcance,
      url,
      departamento_id,
      municipio_id,
      departamento:departamentos (nombre),
      municipio:municipios (nombre)
    `)
    .eq("estado", "aprobado");

  if (deptoId) {
    query = query.or(`departamento_id.eq.${deptoId},alcance.eq.nacional`);
  }

  const { data, error } = await query.order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function proponerGrupoWhatsApp({
  nombre,
  descripcion,
  tipo,
  tema,
  alcance,
  departamentoId,
  municipioId,
  url
}) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { data, error } = await supabase
    .from("grupos_whatsapp")
    .insert({
      nombre,
      descripcion,
      tipo,
      tema,
      alcance,
      departamento_id: departamentoId,
      municipio_id: municipioId,
      departamento_moderacion: alcance === "nacional" ? null : departamentoId,
      url,
      creado_por: user.id
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}
