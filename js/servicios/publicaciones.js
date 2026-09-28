/**
 * Servicio de Publicaciones, Feed e Interacciones · Avancemos
 */

import { supabase } from "../supabase.js";
import { CONFIG } from "../config.js";

export async function obtenerFeed(tipo = "nacional", cursorFecha = null, cursorId = null, limite = 20) {
  const { data, error } = await supabase.rpc("feed", {
    tipo,
    cursor_fecha: cursorFecha,
    cursor_id: cursorId,
    limite
  });
  if (error) throw error;
  return data || [];
}

export async function obtenerFeedPublico(cursorFecha = null, cursorId = null, limite = 15) {
  const { data, error } = await supabase.rpc("feed_publico", {
    cursor_fecha: cursorFecha,
    cursor_id: cursorId,
    limite
  });
  if (error) throw error;
  return data || [];
}

export async function obtenerPublicacionPublica(id) {
  const { data, error } = await supabase.rpc("publicacion_publica", { p_id: id });
  if (error) throw error;
  return data;
}

export async function crearPublicacion({
  contenido,
  categoria = "opinion",
  alcance = "departamental",
  visibilidad = "publica",
  enlaceUrl = null,
  archivosMedia = []
}) {
  const pubId = crypto.randomUUID();
  const mediaSubida = [];

  // Si hay archivos multimedia, subirlos al bucket privado media-pendiente
  if (archivosMedia && archivosMedia.length > 0) {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error("No autenticado");

    for (let i = 0; i < archivosMedia.length; i++) {
      const item = archivosMedia[i];
      const archivo = item.archivo;
      const extension = archivo.name.split(".").pop();
      const rutaArchivo = `${user.id}/${pubId}/${i}_${crypto.randomUUID()}.${extension}`;

      const { data: uploadData, error: uploadErr } = await supabase.storage
        .from(CONFIG.STORAGE_BUCKETS.MEDIA_PENDIENTE)
        .upload(rutaArchivo, archivo);

      if (uploadErr) throw uploadErr;

      mediaSubida.push({
        path: uploadData.path,
        bucket: CONFIG.STORAGE_BUCKETS.MEDIA_PENDIENTE,
        tipo: item.tipo || (archivo.type.startsWith("video/") ? "video" : "imagen"),
        ancho: item.ancho || null,
        alto: item.alto || null,
        duracion_s: item.duracion_s || null,
        alt_text: item.alt_text || "",
        orden: i,
        generada_ia: Boolean(item.generada_ia)
      });
    }
  }

  // Insertar publicación y media en una sola transacción RPC
  const { data, error } = await supabase.rpc("crear_publicacion", {
    p_id: pubId,
    p_contenido: contenido,
    p_categoria: categoria,
    p_alcance: alcance,
    p_visibilidad: visibilidad,
    p_enlace_url: enlaceUrl,
    p_media: mediaSubida
  });

  if (error) throw error;
  return data;
}

export async function darMeGusta(publicacionId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase.from("me_gusta").insert({
    publicacion_id: publicacionId,
    user_id: user.id
  });
  if (error && error.code !== "23505") throw error; // Ignorar si ya existía
}

export async function quitarMeGusta(publicacionId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase
    .from("me_gusta")
    .delete()
    .match({ publicacion_id: publicacionId, user_id: user.id });
  if (error) throw error;
}

export async function guardarPublicacion(publicacionId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase.from("guardados").insert({
    publicacion_id: publicacionId,
    user_id: user.id
  });
  if (error && error.code !== "23505") throw error;
}

export async function quitarGuardado(publicacionId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase
    .from("guardados")
    .delete()
    .match({ publicacion_id: publicacionId, user_id: user.id });
  if (error) throw error;
}

export async function obtenerComentarios(publicacionId) {
  const { data, error } = await supabase
    .from("comentarios")
    .select(`
      id,
      contenido,
      me_gusta_n,
      created_at,
      autor:perfiles!comentarios_autor_id_fkey (
        id,
        nombre,
        username,
        avatar_path,
        insignia
      )
    `)
    .eq("publicacion_id", publicacionId)
    .eq("estado", "visible")
    .order("created_at", { ascending: true });

  if (error) throw error;
  return data || [];
}

export async function agregarComentario(publicacionId, contenido, padreId = null) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { data, error } = await supabase
    .from("comentarios")
    .insert({
      publicacion_id: publicacionId,
      autor_id: user.id,
      padre_id: padreId,
      contenido
    })
    .select(`
      id,
      contenido,
      me_gusta_n,
      created_at,
      autor:perfiles!comentarios_autor_id_fkey (
        id,
        nombre,
        username,
        avatar_path,
        insignia
      )
    `)
    .single();

  if (error) throw error;
  return data;
}
