# Registro de Decisiones de Arquitectura y Diseño · Avancemos

Este documento registra todas las decisiones técnicas tomadas durante el desarrollo de la plataforma conforme a la especificación de `prompt_avancemos.md`.

## 1. Identidad Visual y Logotipo Provisional
- **Decisión:** Se diseñó un logotipo provisional en SVG (`assets/logo.svg`) y un isotipo standalone (`assets/icono.svg`) basados en la palabra "avancemos" en minúscula con la "v" como chevrón ascendente en color turquesa (`#0B7A6E` / `#14B8A6`) y acento ámbar (`#E8A33D`), transmitiendo moderación, rigor institucional y dinamismo hacia el futuro.
- **Razón:** El usuario solicitó prescindir de la imagen generada con IA previa y aplicar la especificación del prompt, que exige un logotipo en SVG sobrio y reproducible sin dependencias.

## 2. Sistema de Soporte y Resolvedor de Dudas
- **Decisión:** Se implementó un sistema de soporte integral accesible tanto para usuarios no registrados como para inscritos y moderadores.
  - **Componente:** Widget flotante universal (`js/ui/widget-soporte.js`) con tres modos:
    1. Chat Asistente IA (consultas de qué es el centro, requisitos de ingreso, normas).
    2. Radicación de Casos Formales con generación de número de radicado único (`RAD-YYYY-XXXXXX`).
    3. Consulta de Casos por número de radicado y correo electrónico.
  - **Base de Datos:** Tablas `casos_soporte` y `caso_mensajes` con RLS estricto y funciones RPC `crear_caso_soporte`, `consultar_caso_soporte`, `agregar_mensaje_caso` y `resolver_caso_soporte`.
- **Razón:** Requerimiento explícito del usuario para brindar atención tanto previa al registro como posterior a la inscripción.

## 3. Modelo de IA en Vertex AI
- **Decisión:** Para generación de imágenes y asistencia de texto se implementó la integración con Vertex AI usando `gemini-2.5-flash-image` y `gemini-2.5-flash` en `us-central1` y `global`, ya que los modelos legacy de Imagen (`imagegeneration@006`) han sido discontinuados en las regiones predeterminadas.
- **Razón:** Las llamadas de prueba confirmaron disponibilidad y compatibilidad con la cuenta de servicio de Google Cloud asociada al proyecto `botes-506017`.

## 4. Estructura de Base de Datos y Territorialidad (DIVIPOLA)
- **Decisión:** Se migraron las 33 entidades territoriales (32 departamentos + Bogotá D.C.) y los 1.105 municipios de Colombia con sus códigos DIVIPOLA oficiales. En Bogotá se implementó el selector adicional de las 20 localidades.
- **Razón:** La organización territorial descentralizada es el núcleo del movimiento Avancemos.

## 5. Prevención Estricta de Vulnerabilidades XSS
- **Decisión:** Prohibición absoluta de `innerHTML` con datos ingresados por usuarios en la red social (`tarjeta-publicacion.js`). El Markdown administrativo del CMS se purifica con `DOMPurify` y `marked`.
- **Razón:** Cumplimiento de la regla de oro número 5 de seguridad web.

## 6. Desactivación de Confirmación de Correo Electrónico
- **Decisión:** Se activó la propiedad `mailer_autoconfirm: true` en la configuración de Supabase Auth mediante la Management API y se adaptó la interfaz de registro (`unete.html`) para omitir la espera o verificación de correo.
- **Razón:** Requerimiento explícito del usuario para agilizar el proceso de incorporación de miembros sin depender de confirmación por correo electrónico.

## 7. Cuenta de Administración Nacional
- **Decisión:** Se creó y aprovisionó la cuenta oficial de administración nacional:
  - Correo: `admin@avancemos.co`
  - Nombre: Administrador Colombia
  - Usuario: `@admin_nacional`
  - Rol asignado: `admin_nacional` con estado `activo` e insignia `dorada`.
- **Razón:** Requerimiento explícito del usuario para gestionar la plataforma y el panel administrativo.

## 8. Edge Functions de Vertex AI desplegadas
- **Decisión:** Se desplegaron `soporte-ia` (pública, máx. 1000 caracteres, Gemini 2.5 Flash sin razonamiento interno para respuestas completas), `ia-imagen` e `ia-texto` (solo administradores y moderadores, validado con `mis_permisos`). La cuenta de servicio se guarda como secreto `GCP_SA_KEY_B64` en Supabase.
- **Razón:** El asistente de "Dudas y Soporte" y el Estudio de IA del panel no tenían funciones desplegadas.

## 9. Media de publicaciones sin mover de bucket
- **Decisión:** Los archivos se suben a `media-pendiente/{departamento|nacional}/{user_id}/...` y, al aprobarse la publicación, se leen con URL firmada gracias a la política `leer_media_aprobada` (función `media_publicacion_visible`, migración 0010).
- **Razón:** La ruta de subida no coincidía con la política de Storage (toda publicación con foto fallaba) y la función que movía archivos a `media-publica` nunca se desplegó.

## 10. Experiencia móvil
- **Decisión:** En `app.html` la barra lateral pasa a ser un cajón deslizable (botón de avatar arriba a la izquierda), la barra inferior tiene el botón ➕ funcional desde cualquier vista y contador de notificaciones, y los modales/comentarios se abren como hoja inferior. El sitio público tiene menú ☰ compartido (`js/ui/menu-sitio.js`) y el panel admin usa una barra superior con íconos.
- **Razón:** En pantallas < 768 px no había forma de llegar a Perfil, Grupos, Eventos, Ajustes ni cerrar sesión.

## 11. Ilustraciones de referentes
- **Decisión:** Los retratos de los referentes son caricaturas estilo animación 3D generadas con Vertex AI (`assets/referentes/`), con animación CSS y la nota "ilustraciones generadas con IA; no implican respaldo".
- **Razón:** Solicitud del cliente; se eligió un estilo claramente no fotográfico para no inducir a error.

## 12. Mapa con CARTO Basemaps
- **Decisión:** Las teselas usan `basemaps.cartocdn.com/rastertiles/light_nolabels/...?key=` con la llave en `CONFIG.CARTO_API_KEY`. En celular el mapa se mueve con dos dedos y muestra la información al tocar.
- **Razón:** Sin llave CARTO muestra la marca de agua "API key required".

## 13. Ahorro en IA (Gemini 2.5 Flash-Lite)
- **Decisión:** El asistente de soporte, la mejora de textos y la moderación usan `gemini-2.5-flash-lite`. El asistente acepta preguntas de máximo 120 caracteres, responde con máximo 100 tokens, solo sobre Avancemos y la plataforma, y tiene límites diarios: 3 preguntas por dirección IP para visitantes y 5 por cuenta registrada (tabla `uso_ia`, zona horaria de Bogotá). El admin nacional no tiene límite.
- **Excepción:** El Estudio de imágenes sigue con `gemini-2.5-flash-image`, porque Flash-Lite no genera imágenes. Solo lo usan administradores y moderadores.

## 14. Privacidad del nombre y edición de perfil
- **Decisión:** La columna `perfiles.nombre` no es legible por la API; los demás usuarios ven `primer_nombre` (columna generada). El propio usuario obtiene su perfil completo con `mi_perfil()` y los administradores con sus RPCs. El usuario solo puede actualizar `bio`.
- **Seguridad:** Se eliminó la política que permitía al autor modificar cualquier columna de su publicación (podía auto-aprobarse). Editar/eliminar va por `editar_publicacion` (vuelve a revisión) y `eliminar_publicacion` (borrado lógico).

## 15. Mensajes directos
- **Decisión:** Solo se puede escribir a personas que uno sigue (validado en `iniciar_conversacion` y en la política de inserción de `mensajes`). Un trigger actualiza la vista previa y notifica al destinatario. Los administradores no leen mensajes privados (Ley 1581 y la promesa de privacidad de la plataforma).

## 16. Grupos, anuncios y eventos
- **Grupos:** Se cargaron los 33 grupos departamentales de WhatsApp, el grupo Internacional, Discord y Telegram publicados en beacons.ai/avancemoscol. Son públicos y se abren desde la sección Grupos, `grupos.html` y el mapa.
- **Anuncios:** `anuncios` admite comunicados, encuestas (una o varias respuestas, comentario opcional) y votaciones (una respuesta), con imagen, video o audio, audiencia nacional o departamental, vigencia y modo obligatorio (modal que no se puede cerrar hasta responder).
- **Eventos:** Los administradores los crean desde `admin.html` y quedan aprobados; también aprueban o eliminan los propuestos por usuarios.

## 17. Formatos de media
- **Imágenes:** WebP (máx. 1600 px) en el navegador.
- **Audio:** Opus en WebM a 48 kbps mono (WebCodecs + webm-muxer); notas de voz con MediaRecorder. Se descartó WAV porque no está comprimido (~10 MB/min frente a ~0,35 MB/min).
- **Video:** MP4 (H.264/AAC) tal como se sube, máx. 50 MB: es el formato compatible con todos los celulares. Recomprimir video en el navegador agota batería y tarda minutos en equipos modestos.
