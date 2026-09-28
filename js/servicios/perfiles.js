/**
 * Servicio de Perfiles y Relaciones Sociales · Avancemos
 */

import { supabase } from "../supabase.js";

export async function obtenerPerfilPorUsername(username) {
  const { data, error } = await supabase
    .from("perfiles")
    .select(`
      id,
      nombre:primer_nombre,
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
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return null;
  // Incluye nombre completo, datos privados y roles (solo del propio usuario)
  const { data, error } = await supabase.rpc("mi_perfil");
  if (error) throw error;
  return data;
}

export async function actualizarBio(bio) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");
  const { error } = await supabase.from("perfiles").update({ bio: bio.trim() || null }).eq("id", user.id);
  if (error) throw error;
}

export async function obtenerRelaciones(username, tipo = "seguidores") {
  const { data, error } = await supabase.rpc("relaciones_de_perfil", { p_username: username, p_tipo: tipo });
  if (error) throw error;
  return data || [];
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
