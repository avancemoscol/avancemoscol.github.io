/**
 * Servicio de Mensajes Directos y Conversaciones · Avancemos
 * Regla de oro de privacidad: Nadie fuera de la conversación puede leer los mensajes.
 */

import { supabase } from "../supabase.js";

export async function obtenerConversaciones() {
  // Incluye el primer nombre del otro participante y si todavía puedes escribirle
  const { data, error } = await supabase.rpc("mis_conversaciones");
  if (error) throw error;
  return data || [];
}

export async function iniciarConversacion(destinatarioId) {
  const { data, error } = await supabase.rpc("iniciar_conversacion", {
    destinatario_id: destinatarioId
  });
  if (error) throw error;
  return data; // Retorna el UUID de la conversación
}

export async function obtenerMensajes(conversacionId) {
  const { data, error } = await supabase
    .from("mensajes")
    .select(`
      id,
      autor_id,
      contenido,
      media_path,
      created_at,
      autor:perfiles (
        id,
        nombre:primer_nombre,
        username,
        avatar_path
      )
    `)
    .eq("conversacion_id", conversacionId)
    .order("created_at", { ascending: true });

  if (error) throw error;
  return data || [];
}

export async function enviarMensaje(conversacionId, contenido, mediaPath = null) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { data, error } = await supabase
    .from("mensajes")
    .insert({
      conversacion_id: conversacionId,
      autor_id: user.id,
      contenido,
      media_path: mediaPath
    })
    .select()
    .single();

  if (error) {
    if (error.code === "42501") throw new Error("Solo puedes escribir a personas que sigues.");
    throw error;
  }
  // La vista previa y la notificación las actualiza un trigger en la base de datos
  return data;
}

export function suscribirMensajesConversacion(conversacionId, onNuevoMensaje) {
  return supabase
    .channel(`conversacion_${conversacionId}`)
    .on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "mensajes",
        filter: `conversacion_id=eq.${conversacionId}`
      },
      (payload) => {
        onNuevoMensaje(payload.new);
      }
    )
    .subscribe();
}
