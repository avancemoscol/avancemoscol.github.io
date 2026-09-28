/**
 * Áreas en las que una persona puede apoyar al movimiento · Avancemos
 * Los valores deben coincidir con la restricción perfiles_area_apoyo_check (migración 0014).
 */

export const AREAS_APOYO = [
  ["voluntariado_territorial", "Voluntariado en mi territorio (reuniones, puerta a puerta)"],
  ["logistica_eventos", "Logística y organización de eventos"],
  ["comunicaciones", "Comunicaciones y redes sociales"],
  ["diseno_audiovisual", "Diseño, fotografía y video"],
  ["tecnologia", "Tecnología y desarrollo web"],
  ["politicas_publicas", "Investigación y propuestas de políticas públicas"],
  ["juridico", "Asesoría jurídica"],
  ["formacion", "Educación y formación ciudadana"],
  ["defensa_voto", "Testigo electoral y defensa del voto"],
  ["recoleccion_firmas", "Recolección de firmas"],
  ["finanzas", "Finanzas y recaudación de fondos"],
  ["liderazgo_comunitario", "Liderazgo comunitario y enlace con organizaciones"],
  ["otro", "Otro"]
];

export function nombreAreaApoyo(valor, otro = null) {
  if (!valor) return "";
  if (valor === "otro") return otro ? `Otro: ${otro}` : "Otro";
  return (AREAS_APOYO.find(([v]) => v === valor) || [valor, valor])[1];
}
