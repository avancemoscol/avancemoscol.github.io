/**
 * Servicio de Reportes Ciudadanos · Avancemos
 */

import { supabase } from "../supabase.js";

export async function enviarReporte({
  entidad,
  entidadId,
  motivo,
  detalle = null
}) {
  const { data, error } = await supabase.rpc("reportar", {
    p_entidad: entidad,
    p_entidad_id: entidadId,
    p_motivo: motivo,
    p_detalle: detalle
  });

  if (error) throw error;
  return data;
}
