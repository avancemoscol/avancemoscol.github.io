/**
 * Utilidades de Fechas y Horas · Avancemos
 * Formato oficial: dd/mm/aaaa, horas 3:45 p. m., zona America/Bogota.
 */

const ZONA_COLOMBIA = "America/Bogota";

export function formatearFecha(fechaStr, conHora = false) {
  if (!fechaStr) return "";
  const d = new Date(fechaStr);
  if (isNaN(d.getTime())) return "";

  const opciones = {
    timeZone: ZONA_COLOMBIA,
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  };

  if (conHora) {
    opciones.hour = "numeric";
    opciones.minute = "2-digit";
    opciones.hour12 = true;
  }

  return new Intl.DateTimeFormat("es-CO", opciones).format(d);
}

export function tiempoRelativo(fechaStr) {
  if (!fechaStr) return "";
  const ahora = Date.now();
  const fecha = new Date(fechaStr).getTime();
  if (isNaN(fecha)) return "";

  const diffSegundos = Math.floor((ahora - fecha) / 1000);

  if (diffSegundos < 60) return "ahora";
  if (diffSegundos < 3600) return `hace ${Math.floor(diffSegundos / 60)} min`;
  if (diffSegundos < 86400) return `hace ${Math.floor(diffSegundos / 3600)} h`;
  if (diffSegundos < 604800) return `hace ${Math.floor(diffSegundos / 86400)} d`;

  return formatearFecha(fechaStr, false);
}
