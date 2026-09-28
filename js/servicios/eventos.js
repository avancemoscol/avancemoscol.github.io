/**
 * Servicio de Eventos Ciudadanos y Territoriales · Avancemos
 */

import { supabase } from "../supabase.js";

export async function obtenerEventos(soloPublicos = false, deptoId = null) {
  let query = supabase
    .from("eventos")
    .select(`
      id,
      titulo,
      descripcion,
      tipo,
      inicio,
      fin,
      modalidad,
      lugar,
      direccion,
      direccion_solo_inscritos,
      cupo,
      asistentes_n,
      url_virtual,
      imagen_path,
      visibilidad,
      departamento_id,
      departamento:departamentos (nombre),
      municipio:municipios (nombre)
    `)
    .eq("estado", "aprobado");

  if (soloPublicos) {
    query = query.eq("visibilidad", "publica");
  }
  if (deptoId) {
    query = query.or(`departamento_id.eq.${deptoId},alcance.eq.nacional`);
  }

  const { data, error } = await query
    .gte("inicio", new Date(Date.now() - 24 * 3600 * 1000).toISOString())
    .order("inicio", { ascending: true });

  if (error) throw error;
  return data || [];
}

export async function responderAsistenciaEvento(eventoId, respuesta = "voy") {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase
    .from("evento_asistentes")
    .upsert({
      evento_id: eventoId,
      user_id: user.id,
      respuesta
    });

  if (error) throw error;
}
