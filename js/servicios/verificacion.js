/**
 * Servicio de Solicitud de Verificación · Avancemos
 */

import { supabase } from "../supabase.js";

export async function solicitarInsignia({
  insignia,
  cargo,
  motivo,
  enlaces = [],
  metodoPreferido = "videollamada"
}) {
  const { data, error } = await supabase.rpc("solicitar_verificacion", {
    p_insignia: insignia,
    p_cargo: cargo,
    p_motivo: motivo,
    p_enlaces: enlaces,
    p_metodo: metodoPreferido
  });

  if (error) throw error;
  return data;
}
