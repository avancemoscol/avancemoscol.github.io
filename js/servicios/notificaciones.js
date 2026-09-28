/**
 * Servicio de Notificaciones en Tiempo Real · Avancemos
 */

import { supabase } from "../supabase.js";

export async function obtenerNotificaciones() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  const { data, error } = await supabase
    .from("notificaciones")
    .select(`
      id,
      tipo,
      texto,
      leida,
      created_at,
      actor:perfiles!notificaciones_actor_id_fkey (
        id,
        nombre,
        username,
        avatar_path
      )
    `)
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(40);

  if (error) throw error;
  return data || [];
}

export async function marcarNotificacionesLeidas() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase
    .from("notificaciones")
    .update({ leida: true })
    .eq("user_id", user.id)
    .eq("leida", false);
}

export function suscribirNotificaciones(user_id, onNotificacion) {
  return supabase
    .channel(`notificaciones_${user_id}`)
    .on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "notificaciones",
        filter: `user_id=eq.${user_id}`
      },
      (payload) => {
        onNotificacion(payload.new);
      }
    )
    .subscribe();
}
