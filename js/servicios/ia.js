/**
 * Servicio de Estudio IA y Vertex AI · Avancemos
 * Conecta el panel y los flujos asistidos con Vertex AI.
 */

import { supabase } from "../supabase.js";

export async function generarImagenIA({ descripcion, formato = "1:1", estilo = "editorial" }) {
  const { data, error } = await supabase.functions.invoke("ia-imagen", {
    body: {
      accion: "generar",
      descripcion,
      formato,
      estilo
    }
  });

  if (error) throw error;
  return data;
}

export async function mejorarPromptIA(descripcion) {
  const { data, error } = await supabase.functions.invoke("ia-texto", {
    body: {
      accion: "mejorar_prompt",
      texto: descripcion
    }
  });

  if (error) return descripcion;
  return data?.prompt_mejorado || descripcion;
}
