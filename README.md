# Plataforma Web y Red Ciudadana de Avancemos (Colombia)

Plataforma oficial del movimiento político de centro **Avancemos**, construida con arquitectura modular en Vanilla JavaScript (módulos ES, sin build), CSS moderno con tokens, Supabase (Postgres 17, RLS, Storage, Realtime, Edge Functions) y Google Cloud Vertex AI (Gemini).

---

## 🏛️ Caras de la Plataforma

1. **Sitio Público (`index.html`)**:
   - Qué es Avancemos, manifiesto de centro, historia y evidencia empírica en Colombia y el mundo.
   - Mapa coroplético interactivo de presencia territorial en los 32 departamentos y Bogotá (DIVIPOLA DANE).
   - Ejes programáticos y propuestas de gobierno evaluables.
   - Directorio de eventos ciudadanos públicos.
   - Widget universal flotante con **Asistente IA** y **Sistema de Radicación y Seguimiento de Casos de Soporte**.

2. **Red Social Estilo X (`app.html`)**:
   - Feed cronológico en 3 columnas: Nacional, Mi Departamento, Mi Municipio, Siguiendo.
   - Redacción de publicaciones con soporte de imágenes y video (compresión automática a WebP en el navegador).
   - Comentarios, me gusta optimistas, guardados y compartir directo a WhatsApp.
   - Directorio privado de grupos de WhatsApp territoriales para miembros aprobados.
   - Mensajería directa 1 a 1 en tiempo real con estricta privacidad.
   - Notificaciones en vivo con Supabase Realtime.

3. **Panel de Administración (`admin.html`)**:
   - Bandeja unificada de aprobaciones: Usuarios, Publicaciones, Grupos de WhatsApp, Eventos, Verificaciones y Casos de Soporte.
   - Estudio de creación con **Vertex AI** (Gemini Image).
   - Registro inmutable de auditoría para todas las acciones moderativas.

---

## 🛡️ Seguridad y Reglas de Oro

- **RLS (Row Level Security)** habilitado en todas las tablas con políticas restrictivas.
- **Protección XSS**: Cero uso de `innerHTML` con datos de usuarios; manipulación pura del DOM con `textContent` y purificación con `DOMPurify` para Markdown del CMS.
- **Ley 1581 de 2012 (Colombia)**: Protección reforzada de datos sensibles (afinidad política). Consentimiento explícito separado, perfiles privados por defecto y exportación de datos en JSON.
- **Insignias estilo X**: Azul (identidad verificada), Dorada (vocería oficial), Gris (servidores públicos).

---

## 🚀 Despliegue y Puesta en Marcha

### 1. Base de Datos en Supabase
Las migraciones ya se encuentran aplicadas en el proyecto Supabase `zxlqwhjlgmoqemcuseek`:
```bash
# Las migraciones se ubican en:
supabase/migrations/
├── 0001_extensiones_tipos.sql
├── 0002_tablas.sql
├── 0003_funciones.sql
├── 0004_rls.sql
├── 0005_triggers.sql
├── 0006_storage.sql
├── 0007_cron.sql
└── 0008_semillas.sql
```

### 2. Ejecutar Pruebas de Aceptación RLS
```bash
# Verifica los criterios de aceptación de seguridad
psql -f supabase/tests/rls_pruebas.sql
```

### 3. Servidor Local de Desarrollo
Al no requerir compilación ni herramientas pesadas de empaquetado, puedes servir el proyecto con cualquier servidor HTTP estático:
```bash
# Con Python
python3 -m http.server 3000

# O con npx serve
npx serve .
```

Abre en tu navegador:
- Sitio Público: `http://localhost:3000/index.html`
- Galería de Componentes: `http://localhost:3000/estilo.html`
- Red Social: `http://localhost:3000/app.html`
- Panel Admin: `http://localhost:3000/admin.html`
