/**
 * Configuración Global · Plataforma Avancemos
 * Llaves públicas y metadatos del proyecto.
 */

export const CONFIG = {
  // Supabase
  SUPABASE_URL: "https://zxlqwhjlgmoqemcuseek.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4bHF3aGpsZ21vcWVtY3VzZWVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA1NDI2NjgsImV4cCI6MjEwNjExODY2OH0.dI4aGoYxqEktxdfn64J0eDBIDSSo9GgX0NOjkw4t_c8",

  // Datos Institucionales
  NOMBRE_MOVIMIENTO: "Avancemos",
  LEMA: "Ni extremos ni excusas: soluciones.",
  LEMA_SECUNDARIO: "Colombia avanza cuando nos escuchamos.",
  PAIS: "Colombia",
  CORREO_CONTACTO: "abulingo.help@gmail.com",
  CORREO_SOPORTE: "abulingo.help@gmail.com",
  DOMINIO: "https://avancemos.co",
  RESPONSABLE_DATOS: "Movimiento Político Avancemos Colombia",
  NIT_DOCUMENTO: "",
  DIRECCION_CONTACTO: "",

  // CARTO Basemaps (teselas raster del mapa; la llave elimina la marca de agua)
  CARTO_API_KEY: "cb1_2nsz_1_2e810fa90ac9971bc0c7f6b9",
  CARTO_ESTILO: "light_nolabels",

  // Cloudflare Turnstile (Site Key de prueba o producción)
  TURNSTILE_SITE_KEY: "0x4AAAAAAAEkG6kC8_3fX2xL",

  // Rutas de almacenamiento Supabase Storage
  STORAGE_BUCKETS: {
    AVATARES: "avatares",
    PORTADAS: "portadas",
    MEDIA_PENDIENTE: "media-pendiente",
    MEDIA_PUBLICA: "media-publica",
    MEDIA_MIEMBROS: "media-miembros",
    MENSAJES: "mensajes",
    IA_MEDIA: "ia-media",
    SITIO: "sitio"
  },

  // Ajustes de Interfaz
  LIMITES: {
    MAX_CARACTERES_POST: 3000,
    MAX_CARACTERES_COMENTARIO: 1000,
    MAX_CARACTERES_MENSAJE: 2000,
    MAX_IMAGENES_POST: 4,
    MAX_TAMANO_IMAGEN_MB: 10,
    MAX_TAMANO_VIDEO_MB: 50
  }
};
