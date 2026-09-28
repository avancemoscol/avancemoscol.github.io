/**
 * Servicio de Soporte, Casos y Resolvedor de Dudas (IA) · Avancemos
 * Atiende tanto a visitantes no registrados como a miembros activos e inscritos.
 */

import { supabase } from "../supabase.js";

// Base de conocimiento contextual para respuestas instantáneas
const CONOCIMIENTO_BASE = `
Avancemos es un movimiento político ciudadano de centro en Colombia.
Principios: Pragmatismo con evidencia, diálogo y acuerdos sobre trincheras, instituciones fuertes y respeto por la Constitución de 1991, economía social de mercado e integridad absoluta contra la corrupción.
Presencia: En los 32 departamentos de Colombia y Bogotá D. C.
Inscripción: Es 100% gratuita. Los usuarios completan su registro y el equipo de moderadores de su respectivo departamento revisa y aprueba su cuenta en 24 a 48 horas.
Roles: Simpatizante, Voluntario y Líder (asignados territorialmente).
Insignias de verificación: Azul (identidad confirmada mediante videollamada o presencial), Dorada (cuentas oficiales y vocerías del movimiento), Gris (servidores públicos y cargos de elección popular).
Grupos de WhatsApp: Disponibles exclusivamente para miembros activos aprobados para evitar spam e infiltraciones.
Eventos: Encuentros ciudadanos, foros programáticos y jornadas de voluntariado en las regiones.
`;

export const MAX_CARACTERES_PREGUNTA = 120;

/**
 * Consulta al asistente de IA (Gemini 2.5 Flash-Lite).
 * Límites en el servidor: 3 preguntas/día para visitantes y 5/día para usuarios registrados.
 * @returns {{ respuesta: string, restantes: number|null, limite?: boolean, sinIA?: boolean }}
 */
export async function resolverDudaConIA(pregunta) {
  const texto = String(pregunta || "").trim().slice(0, MAX_CARACTERES_PREGUNTA);
  try {
    const { data, error } = await supabase.functions.invoke("soporte-ia", { body: { pregunta: texto } });
    if (!error && data?.respuesta) {
      return { respuesta: data.respuesta, restantes: data.restantes ?? null };
    }
    // Leer el mensaje de error del servidor (límite alcanzado, pregunta muy larga, etc.)
    let cuerpo = null;
    try { cuerpo = await error?.context?.json(); } catch (_) { /* sin cuerpo */ }
    if (cuerpo?.limite_alcanzado) return { respuesta: cuerpo.error, restantes: 0, limite: true };
    if (error?.context?.status === 400 && cuerpo?.error) return { respuesta: cuerpo.error, restantes: null };
  } catch (e) {
    // Sin conexión: continuar con respuestas locales
  }
  return { respuesta: respuestaLocal(texto), restantes: null, sinIA: true };
}

// Respuestas locales (sin IA) cuando el servicio no está disponible
function respuestaLocal(pregunta) {
  const p = pregunta.toLowerCase();
  if (p.includes("inscri") || p.includes("unir") || p.includes("registro") || p.includes("crear cuenta")) {
    return "¡Unirte a Avancemos es muy fácil y gratuito! Ve a la sección 'Únete', ingresa tus datos, selecciona tu departamento y municipio, y elige el rol con el que deseas aportar (Simpatizante, Voluntario o Líder). El equipo departamental de tu región revisará tu solicitud para activar tu cuenta.";
  }
  if (p.includes("aprob") || p.includes("revision") || p.includes("tiempo") || p.includes("demora")) {
    return "La revisión de nuevas cuentas y publicaciones está a cargo de los administradores y moderadores de tu propio departamento. Normalmente el proceso toma entre 12 y 48 horas hábiles. Recibirás un correo y una notificación una vez sea aprobada.";
  }
  if (p.includes("centro") || p.includes("ideolog") || p.includes("izquierda") || p.includes("derecha")) {
    return "El centro político en Avancemos no es tibieza ni neutralidad pasiva: es tomar posición con base en la evidencia y los resultados prácticos, no en dogmas cerrados. Defendemos la Constitución de 1991, el diálogo democrático, el libre emprendimiento y la justicia social sin polarización.";
  }
  if (p.includes("insignia") || p.includes("verific") || p.includes("chulito") || p.includes("azul") || p.includes("dorad")) {
    return "Avancemos cuenta con un sistema de verificación con insignias estilo X: la Insignia Azul certifica tu identidad real verificada en videollamada; la Insignia Dorada distingue a líderes oficiales y cuentas territoriales; y la Insignia Gris reconoce a servidores públicos de elección popular.";
  }
  if (p.includes("whatsapp") || p.includes("grupo") || p.includes("chat")) {
    return "Cada departamento tiene su grupo oficial de WhatsApp, además de la comunidad nacional en Telegram y Discord. Encuéntralos en la sección 'Grupos' o tocando tu departamento en el mapa de la página de inicio.";
  }
  if (p.includes("costo") || p.includes("pago") || p.includes("plata") || p.includes("dinero") || p.includes("cobro")) {
    return "Unirte y participar en la plataforma de Avancemos es totalmente gratuito. No se cobra ninguna tarifa por registro, verificación ni acceso a grupos o eventos comunitarios.";
  }
  if (p.includes("caso") || p.includes("radic") || p.includes("problema") || p.includes("soporte") || p.includes("humano")) {
    return "Si requieres atención personalizada por parte del equipo humano de Avancemos, puedes radicar un caso formal en la pestaña 'Radicar caso' de este asistente. Te asignaremos un número de radicado oficial para hacerle seguimiento.";
  }

  return "Hola, soy el Asistente Inteligente de Avancemos. Puedo orientarte sobre qué es el centro político, cómo registrarte, el estado de las revisiones, grupos de WhatsApp, eventos y propuestas. Si tienes un requerimiento específico o técnico, también puedes radicar un caso para que un moderador humano te contacte.";
}

export async function radicarCasoSoporte({
  nombre,
  correo,
  telefono = null,
  categoria = "otro",
  asunto,
  descripcion,
  departamentoId = null
}) {
  const { data, error } = await supabase.rpc("crear_caso_soporte", {
    p_nombre: nombre,
    p_correo: correo,
    p_telefono: telefono,
    p_categoria: categoria,
    p_asunto: asunto,
    p_descripcion: descripcion,
    p_departamento_id: departamentoId
  });

  if (error) throw error;
  return data;
}

export async function consultarCasoSoporte(numeroRadicado, correo) {
  const { data, error } = await supabase.rpc("consultar_caso_soporte", {
    p_radicado: numeroRadicado,
    p_correo: correo
  });

  if (error) throw error;
  return data;
}

export async function enviarMensajeACaso(casoId, mensaje, correo = null) {
  const { data, error } = await supabase.rpc("agregar_mensaje_caso", {
    p_caso_id: casoId,
    p_mensaje: mensaje,
    p_correo: correo
  });

  if (error) throw error;
  return data;
}
