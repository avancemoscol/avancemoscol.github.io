/**
 * Servicio de la Línea de Tiempo del movimiento · Avancemos
 * Hitos del administrador + eventos públicos aprobados (lo hecho y lo que sigue).
 */

import { supabase } from "../supabase.js";

export async function obtenerLineaTiempo(limite = 30) {
  const { data, error } = await supabase.rpc("linea_tiempo", { p_limite: limite });
  if (error) throw error;
  return data || { proximo: [], historial: [], cifras: {} };
}
