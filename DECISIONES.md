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
