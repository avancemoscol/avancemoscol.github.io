/**
 * Servicio de Perfiles y Relaciones Sociales · Avancemos
 */

import { supabase } from "../supabase.js";
import { CONFIG } from "../config.js";

export async function obtenerPerfilPorUsername(username) {
  const { data, error } = await supabase
    .from("perfiles")
    .select(`
      id,
      nombre,
      username,
      bio,
      avatar_path,
      portada_path,
      cargo_titulo,
      ocupacion,
      intereses,
      redes,
      estado,
      insignia,
      insignia_suspendida,
      mostrar_municipio,
      seguidores_n,
      siguiendo_n,
      publicaciones_n,
      created_at,
      departamento:departamentos (nombre),
      municipio:municipios (nombre)
    `)
    .eq("username", username.toLowerCase())
    .single();

  if (error) throw error;
  return data;
}

export async function obtenerMiPerfil() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from("perfiles")
    .select(`
      *,
      privado:perfiles_privados (*),
      roles:user_roles!user_roles_user_id_fkey (*)
    `)
    .eq("id", user.id)
    .single();

  if (error) throw error;
  return data;
}

export async function actualizarMiPerfil(cambios) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { data, error } = await supabase
    .from("perfiles")
    .update(cambios)
    .eq("id", user.id)
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function subirAvatar(archivo) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const ext = archivo.name.split(".").pop();
  const ruta = `${user.id}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;

  const { data, error } = await supabase.storage
    .from(CONFIG.STORAGE_BUCKETS.AVATARES)
    .upload(ruta, archivo, { upsert: true });

  if (error) throw error;

  const { data: { publicUrl } } = supabase.storage
    .from(CONFIG.STORAGE_BUCKETS.AVATARES)
    .getPublicUrl(data.path);

  await actualizarMiPerfil({ avatar_path: publicUrl });
  return publicUrl;
}

export async function seguirUsuario(targetId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase.from("seguidores").insert({
    seguidor_id: user.id,
    seguido_id: targetId
  });
  if (error && error.code !== "23505") throw error;
}

export async function dejarDeSeguir(targetId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");

  const { error } = await supabase
    .from("seguidores")
    .delete()
    .match({ seguidor_id: user.id, seguido_id: targetId });
  if (error) throw error;
}
