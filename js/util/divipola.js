/**
 * Catálogo Territorial DIVIPOLA (DANE) · Avancemos
 */

import { supabase } from "../supabase.js";

let cacheDepartamentos = null;
const cacheMunicipios = new Map();
let cacheLocalidades = null;

export async function obtenerDepartamentos() {
  if (cacheDepartamentos) return cacheDepartamentos;
  const { data, error } = await supabase
    .from("departamentos")
    .select("id, nombre, slug, region")
    .order("nombre");

  if (error) throw error;
  cacheDepartamentos = data;
  return data;
}

export async function obtenerMunicipios(departamentoId) {
  if (!departamentoId) return [];
  if (cacheMunicipios.has(departamentoId)) return cacheMunicipios.get(departamentoId);

  const { data, error } = await supabase
    .from("municipios")
    .select("id, nombre, slug, es_capital")
    .eq("departamento_id", departamentoId)
    .order("es_capital", { ascending: false })
    .order("nombre");

  if (error) throw error;
  cacheMunicipios.set(departamentoId, data);
  return data;
}

export async function obtenerLocalidadesBogota() {
  if (cacheLocalidades) return cacheLocalidades;
  const { data, error } = await supabase
    .from("localidades_bogota")
    .select("id, nombre")
    .order("id");

  if (error) throw error;
  cacheLocalidades = data;
  return data;
}
