/**
 * Validadores de Entrada y Expresiones Regulares · Avancemos
 */

export function validarUsername(username) {
  return /^[a-z0-9_]{3,30}$/.test(username);
}

export function validarCorreo(correo) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo);
}

export function validarContrasena(pass) {
  return typeof pass === "string" && pass.length >= 10;
}

export function validarGrupoWhatsapp(url) {
  if (!url) return false;
  const esGrupo = /^https:\/\/chat\.whatsapp\.com\/[A-Za-z0-9]{20,24}$/.test(url);
  const esCanal = /^https:\/\/(www\.)?whatsapp\.com\/channel\/[A-Za-z0-9]+$/.test(url);
  return esGrupo || esCanal;
}
