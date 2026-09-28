/**
 * Servicio de Grupos (WhatsApp, Telegram y Discord) · Avancemos
 * Los grupos aprobados son públicos: son los mismos enlaces oficiales de beacons.ai/avancemoscol.
 */

import { supabase } from "../supabase.js";

export async function obtenerGrupos() {
  const { data, error } = await supabase
    .from("grupos_whatsapp")
    .select(`
      id,
      nombre,
      descripcion,
      tipo,
      tema,
      alcance,
      url,
      plataforma,
      orden,
      departamento_id,
      departamento:departamentos!grupos_whatsapp_departamento_id_fkey (nombre, region)
    `)
    .eq("estado", "aprobado")
    .order("orden")
    .order("nombre");
  if (error) throw error;
  return data || [];
}

// Compatibilidad con el nombre anterior
export const obtenerGruposWhatsApp = obtenerGrupos;

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
