/**
 * Servicio de Contenidos CMS y Estadísticas Públicas · Avancemos
 */

import { supabase } from "../supabase.js";

export async function obtenerPagina(slug) {
  const { data, error } = await supabase
    .from("paginas")
    .select("slug, titulo, contenido_md, seo_titulo, seo_descripcion")
    .eq("slug", slug)
    .eq("publicada", true)
    .single();

  if (error) return null;
  return data;
}

export async function obtenerPropuestas() {
  const { data, error } = await supabase
    .from("propuestas")
    .select("id, eje, titulo, resumen, detalle_md, icono, orden")
    .eq("publicada", true)
    .order("orden");

  if (error) return [];
  return data || [];
}

export async function obtenerReferentes(ambito = null) {
  let query = supabase
    .from("referentes")
    .select("id, nombre, ambito, pais, orientacion, cargos, logros, contexto, leccion, fuentes, imagen_path, orden")
    .eq("publicado", true);

  if (ambito) {
    query = query.eq("ambito", ambito);
  }

  const { data, error } = await query.order("orden");
  if (error) return [];
  return data || [];
}

export async function obtenerEstadisticasPublicas() {
  const { data, error } = await supabase.rpc("estadisticas_publicas");
  if (error) return null;
  return data;
}
