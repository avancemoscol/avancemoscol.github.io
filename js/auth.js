/**
 * Módulo de Autenticación y MFA · Avancemos
 */

import { supabase } from "./supabase.js";

export async function obtenerSesion() {
  const { data: { session }, error } = await supabase.auth.getSession();
  if (error) return null;
  return session;
}

export async function obtenerUsuarioActual() {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error) return null;
  return user;
}

export async function iniciarSesion(email, password, captchaToken = null) {
  const opciones = {
    email,
    password
  };
  if (captchaToken) {
    opciones.options = { captchaToken };
  }

  const { data, error } = await supabase.auth.signInWithPassword(opciones);
  if (error) throw error;
  return data;
}

export async function iniciarSesionConGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: {
      redirectTo: `${window.location.origin}/ingresar.html?oauth=google`
    }
  });
  if (error) throw error;
  return data;
}

export async function registrarse({
  email,
  password,
  nombre,
  username,
  departamentoId,
  municipioId,
  localidadId = null,
  rolSolicitado = "simpatizante",
  motivo = "",
  telefono = null,
  ocupacion = null,
  intereses = [],
  areaApoyo = null,
  areaApoyoOtro = null,
  captchaToken = null
}) {
  const opciones = {
    email,
    password,
    options: {
      data: {
        nombre,
        username,
        departamento_id: departamentoId,
        municipio_id: municipioId,
        localidad_id: localidadId,
        rol_solicitado: rolSolicitado,
        motivo,
        telefono,
        ocupacion,
        intereses,
        area_apoyo: areaApoyo,
        area_apoyo_otro: areaApoyoOtro,
        acepta_terminos: true,
        autoriza_datos_sensibles: true,
        mayor_de_edad: true,
        version_politica: "1.0",
        user_agent: navigator.userAgent
      }
    }
  };

  if (captchaToken) {
    opciones.options.captchaToken = captchaToken;
  }

  const { data, error } = await supabase.auth.signUp(opciones);
  if (error) throw error;
  return data;
}

export async function cerrarSesion() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function restablecerContrasena(email, captchaToken = null) {
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/restablecer.html`,
    captchaToken
  });
  if (error) throw error;
}

export async function actualizarContrasena(nuevaContrasena) {
  const { data, error } = await supabase.auth.updateUser({
    password: nuevaContrasena
  });
  if (error) throw error;
  return data;
}

export async function verificarNivelAAL() {
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (error) return { currentLevel: "aal1", nextLevel: "aal1" };
  return data;
}

export function suscribirCambioAuth(callback) {
  return supabase.auth.onAuthStateChange((evento, sesion) => {
    callback(evento, sesion);
  });
}
