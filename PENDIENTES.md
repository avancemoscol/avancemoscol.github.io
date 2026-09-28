# Pendientes y Datos del Cliente · Avancemos

Valores de ejemplo utilizados que deben ser confirmados o reemplazados por el cliente:

1. **Logo definitivo:**
   - Se utiliza actualmente el logotipo provisional en SVG con chevrón turquesa (`assets/logo.svg`). Si el movimiento cuenta con un manual de marca definitivo, reemplazar en `assets/logo.svg` y `assets/icono.svg`.
2. **Cloudflare Turnstile:**
   - La llave de sitio actual en `js/config.js` es una llave de prueba. Se debe configurar la Site Key definitiva del dominio en producción en Cloudflare y activar la integración en Supabase Auth.
3. **Servidor SMTP Propio:**
   - Para producción, configurar un proveedor SMTP (Resend, Brevo o Amazon SES) en el panel de Supabase Auth para envíos a correos reales fuera del equipo de desarrollo.
4. **Dominio Definitivo:**
   - Se configuró por defecto `https://avancemos.co`. Si el dominio definitivo cambia, actualizar `CONFIG.DOMINIO` en `js/config.js` y las URL de redirección en Supabase Auth.
5. **Repositorio de GitHub:**
   - El código local está preparado y versionado con Git. Se requiere la URL del repositorio remoto o token de GitHub para vincular y subir (`git push`).
6. **Aprobación automática de media en otro bucket (opcional):**
   - La Edge Function `publicar-media` (mover archivos a `media-publica`) y `moderar-ia` no están desplegadas: requieren configurar Database Webhooks en Supabase. La plataforma funciona sin ellas gracias a la migración 0010.
7. **Rotar credenciales:**
   - `credenciales.txt` contiene en texto plano el token de GitHub, la `service_role` y el token de administración de Supabase. Se recomienda rotarlos y guardarlos en un gestor de secretos.
8. **Datos legales del responsable del tratamiento:**
   - El NIT y la dirección quedaron en blanco en `privacidad.html` y `js/config.js` hasta tener los datos reales.
9. **Límite de visitantes del asistente por IP:**
   - Personas que comparten conexión (universidad, oficina) comparten las 3 preguntas diarias de visitante.
