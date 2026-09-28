# Prompt maestro · Plataforma web de Avancemos

Este documento es la especificación completa del proyecto. Lo que aparece entre **[CORCHETES]** lo aporta el cliente; si falta, usa un valor de ejemplo claramente marcado y regístralo en `PENDIENTES.md`.

## Resumen

Construye una sola plataforma con tres caras para **Avancemos**, un movimiento político de centro en Colombia:

1. **Sitio público** elegante y profesional: qué es Avancemos, qué es el centro político, referentes de centro en Colombia y en el mundo, propuestas, eventos y cómo unirse.
2. **Red social propia, estilo X**, para simpatizantes, voluntarios y líderes de los 32 departamentos y Bogotá: perfiles, publicaciones, comentarios, me gusta, compartir, seguir, mensajes directos, notificaciones, eventos, páginas por departamento y municipio, y directorio de grupos de WhatsApp.
3. **Panel de administración** con dos niveles: **Administrador Colombia** (controla todo) y **administradores departamentales** (varios por departamento, cada uno controla su territorio), más moderadores.

Reglas de oro:
- **Pasa por aprobación de un administrador**: cuentas y roles, publicaciones, grupos de WhatsApp, eventos y verificaciones.
- **No requiere aprobación**: comentarios, me gusta, compartir, guardar, seguir y mensajes directos. Se controlan con filtros, límites y reportes.
- **Verificación con insignias al estilo X**, otorgada solo por administradores.
- **Vertex AI** desde el panel para generar imágenes y videos, y para moderación asistida con Gemini.

Stack: HTML + CSS + JavaScript (módulos ES, sin build) + Supabase (Postgres con RLS, Auth, Storage, Realtime, Edge Functions).

---

## 0. Tu rol y reglas de trabajo

Actúa como ingeniero full-stack senior, experto en Supabase (Postgres, RLS, Auth, Storage, Realtime, Edge Functions), seguridad web y diseño de producto.

1. Entrega archivos completos y funcionales. Nada de `// TODO`, "implementar aquí" ni fragmentos sueltos.
2. La seguridad vive en la base de datos (RLS y funciones `security definer`). Ocultar un botón en el frontend es UX, nunca control de acceso.
3. No inventes datos de Avancemos: ni número de miembros, ni testimonios, ni logros, ni nombres de líderes. Las cifras salen de la base de datos.
4. Interfaz 100 % en español de Colombia, con tuteo cercano y respetuoso. Fechas `dd/mm/aaaa`, horas `3:45 p. m.`, zona `America/Bogota`. En la base, siempre `timestamptz`.
5. Nunca insertes contenido de usuarios con `innerHTML`: usa `textContent` y nodos del DOM. El Markdown del CMS se renderiza con `marked` + `DOMPurify`.
6. Trabaja por fases (sección 22). Al cerrar cada una entrega: archivos, migraciones SQL, pasos para probar y lo pendiente.
7. Pregunta solo si algo te bloquea. Cada decisión de diseño que tomes, anótala en `DECISIONES.md`.

## 1. Datos que aporta el cliente

- Logo en SVG y colores oficiales. Si no existen, usa la identidad de la sección 4 y crea un logotipo provisional.
- Lema, misión, visión, manifiesto y ejes programáticos definitivos (hay sugerencias editables en la sección 20).
- Responsable del tratamiento de datos: nombre o razón social, NIT o cédula, dirección, correo y teléfono.
- Correo de contacto, redes sociales oficiales y dominio.
- Supabase: `SUPABASE_URL` y publishable key. Google Cloud: `GCP_PROJECT_ID` y llave de una cuenta de servicio (solo como secreto de Edge Functions). Cloudflare Turnstile: site key y secret. Correo: cuenta de Resend, Brevo o Amazon SES.

## 2. Stack y arquitectura

- **Frontend**: HTML5, CSS con variables y JavaScript vanilla en módulos ES. Sin framework ni paso de build: se despliega como sitio estático en Netlify, Vercel o Cloudflare Pages.
- **Librerías por CDN (jsDelivr), con versión fijada**: `@supabase/supabase-js@2` (`import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'`), `dompurify`, `marked`, `leaflet`, `chart.js`, `lucide` y `cropperjs`. Leaflet y Chart.js se cargan con `import()` dinámico solo en las vistas que los usan.
- **Supabase**:
  - Postgres con RLS en todas las tablas. Extensiones: `citext`, `unaccent`, `pg_trgm`, `pg_cron`, `pg_net`.
  - Auth con correo y contraseña, confirmación de correo, CAPTCHA con Cloudflare Turnstile (integración nativa: se envía `captchaToken` en registro, inicio de sesión y recuperación) y MFA TOTP obligatorio para moderadores y administradores.
  - Storage, Realtime, Edge Functions (Deno + TypeScript), Database Webhooks y `pg_cron`.
  - Región São Paulo (`sa-east-1`), la más cercana a Colombia. Plan Pro en producción: el gratuito se pausa por inactividad y no incluye copias de seguridad diarias.
  - El frontend solo conoce la **publishable key** (o la `anon` en proyectos antiguos). La **secret key / service_role** vive únicamente dentro de Edge Functions.
- **IA**: Vertex AI (hoy dentro de Gemini Enterprise Agent Platform, con los mismos endpoints `aiplatform.googleapis.com`), llamado solo desde Edge Functions con una cuenta de servicio. Detalle en la sección 14.
- **Correo**: SMTP propio en Supabase Auth. El SMTP por defecto de Supabase es solo para pruebas (envía únicamente a correos del equipo del proyecto y con límites muy bajos), así que configúralo antes de abrir el registro. Plantillas de Auth traducidas al español y con la marca.
- **Privacidad**: sin píxeles publicitarios (Meta, TikTok, etc.) en páginas con sesión. Si se necesita analítica, Plausible o Umami sin cookies.

## 3. Estructura de archivos

```
avancemos/
├── index.html                  # Inicio
├── quienes-somos.html
├── el-centro.html              # Qué es el centro político
├── referentes.html             # Referentes de centro: Colombia y mundo
├── propuestas.html
├── eventos.html                # Eventos públicos
├── publicacion.html            # Vista pública de una publicación (?id=)
├── unete.html                  # Registro + solicitud de rol
├── ingresar.html  restablecer.html
├── app.html                    # Red social (SPA con router por hash)
├── admin.html                  # Panel de administración (SPA)
├── insignias.html  normas.html  privacidad.html  terminos.html
├── estilo.html                 # Galería de componentes para revisar el diseño
├── 404.html  offline.html
├── manifest.webmanifest  sw.js  robots.txt  sitemap.xml  _headers (o vercel.json)
├── css/      tokens.css  base.css  componentes.css  publico.css  app.css  admin.css
├── js/
│   ├── config.js               # URL, llaves públicas y textos [COMPLETAR]
│   ├── supabase.js             # cliente único
│   ├── auth.js  router.js  permisos.js
│   ├── ui/                     # tarjeta-publicacion, avatar, insignia, modal, toast, esqueleto, selector-territorio…
│   ├── servicios/              # publicaciones, perfiles, mensajes, notificaciones, grupos, eventos, verificacion, reportes, admin, ia, cms
│   ├── vistas/app/             # inicio, explorar, buscar, perfil, publicar, publicacion, mensajes, notificaciones, guardados, grupos, eventos, territorio, ajustes, verificacion
│   ├── vistas/admin/           # resumen, aprobaciones, usuarios, equipo, reportes, contenido, oficial, estudio-ia, medios, comunicaciones, grupos-eventos, configuracion, auditoria, exportar
│   └── util/                   # fechas, validadores, texto-seguro, imagenes, divipola
├── assets/   logo.svg  og-default.jpg  iconos/
├── data/     colombia-departamentos.geojson   # MGN del DANE simplificado con mapshaper (< 300 KB)
└── supabase/
    ├── migrations/  0001_extensiones_tipos.sql  0002_tablas.sql  0003_funciones.sql  0004_rls.sql
    │                0005_triggers.sql  0006_storage.sql  0007_cron.sql  0008_semillas.sql
    ├── seed/        municipios_divipola.csv   cuentas_oficiales.js   datos_prueba.js (solo desarrollo)
    ├── functions/   _shared/ (cors.ts, auth.ts, vertex.ts)  ia-imagen/  ia-video/  ia-texto/  moderar-ia/
    │                publicar-media/  vista-previa-enlace/  correo-aviso/  eliminar-cuenta/
    └── tests/       rls_pruebas.sql
README.md  DECISIONES.md  PENDIENTES.md
```

## 4. Identidad visual y experiencia

Objetivo: que se vea como una institución seria y moderna, no como una plantilla. Sobria, cálida y con mucho aire.

**Paleta** (tokens en `css/tokens.css`; se reemplazan si Avancemos ya tiene colores):

| Token | Valor | Uso |
|---|---|---|
| `--azul-noche` | `#0B2440` | títulos, encabezados, fondo del héroe |
| `--turquesa` | `#0B7A6E` | botones y enlaces (contraste 5,2:1 con blanco) |
| `--turquesa-claro` | `#14B8A6` | solo decorativo |
| `--ambar` | `#E8A33D` | acentos y destacados, con texto azul noche encima |
| `--marfil` | `#F7F5F0` | fondo general |
| `--superficie` | `#FFFFFF` | tarjetas |
| `--borde` | `#E4E0D8` | bordes |
| `--texto` / `--texto-suave` | `#16202B` / `#5B6673` | texto |
| `--exito` / `--alerta` / `--error` | `#15803D` / `#B45309` / `#B91C1C` | estados |
| Insignias | azul `#2F7DE1` · dorada `#A67C00` · gris `#6B7785` | verificación (contraste ≥ 3:1 sobre blanco y sobre el fondo oscuro) |

- Modo oscuro (`prefers-color-scheme` + selector manual): fondo `#0B1622`, superficie `#12202F`, texto `#E8EDF2`, turquesa `#2EC4B6`; en oscuro, el botón primario es turquesa con texto `#0B1622`.
- Evita que la marca dependa de colores muy asociados a partidos existentes (por ejemplo, el rojo liberal o el azul conservador): el azul noche funciona como neutro oscuro y el color de marca es el turquesa.

**Tipografía** (Google Fonts): títulos en **Fraunces**; interfaz y texto en **Plus Jakarta Sans**. Escala fluida con `clamp()` y números tabulares en cifras.

**Sistema**: grilla de 8 px, radios de 12–16 px, sombras suaves en dos niveles, ancho máximo de 1180 px en el sitio público.

**App estilo X**: en escritorio (≥ 1280 px), tres columnas (navegación 260 px · feed 620 px · lateral 340 px con tendencias, próximos eventos y sugerencias). Entre 1024 y 1279 px se oculta la columna lateral; entre 768 y 1023 px la navegación queda solo con íconos. En móvil, barra inferior con Inicio, Buscar, Publicar, Notificaciones y Mensajes.

**Componentes**: botones (primario, secundario, fantasma, peligro), campos con validación en línea, tarjetas, avatar con insignia, chips, pestañas, modal, cajón lateral, toasts, esqueletos de carga, estados vacíos con ilustración, tablas con filtros y paginación por cursor.

**Movimiento**: 150–250 ms, ease-out; respeta `prefers-reduced-motion`. "Me gusta" optimista con microanimación.

**Imágenes**: fotos reales de actividades cuando existan; mientras tanto, imágenes generadas con Vertex (sección 14) con sello visible "Generada con IA". Video de héroe en bucle, silenciado, con póster y botón de pausa; sin video si el usuario pidió reducir movimiento.

**Logotipo provisional** en SVG: "avancemos" en minúscula (Fraunces seminegrita), con la "v" como un chevrón ascendente en turquesa.

**Rendimiento y accesibilidad**: pensado para Android de gama media y datos móviles (WebP, `loading="lazy"`, sin librerías pesadas). WCAG 2.2 AA: contraste, foco visible, navegación con teclado, `aria-live` en notificaciones y texto alternativo obligatorio en imágenes de publicaciones (con sugerencia por IA).

## 5. Roles, territorio y permisos

**Territorio**: 32 departamentos + Bogotá D. C., con códigos DIVIPOLA del DANE (2 dígitos por departamento, 5 por municipio). Semilla de departamentos (la región es de referencia):
- Caribe: 08 Atlántico, 13 Bolívar, 20 Cesar, 23 Córdoba, 44 La Guajira, 47 Magdalena, 70 Sucre.
- Andina: 05 Antioquia, 11 Bogotá D. C., 15 Boyacá, 17 Caldas, 25 Cundinamarca, 41 Huila, 54 Norte de Santander, 63 Quindío, 66 Risaralda, 68 Santander, 73 Tolima.
- Pacífica: 19 Cauca, 27 Chocó, 52 Nariño, 76 Valle del Cauca.
- Orinoquía: 50 Meta, 81 Arauca, 85 Casanare, 99 Vichada.
- Amazonía: 18 Caquetá, 86 Putumayo, 91 Amazonas, 94 Guainía, 95 Guaviare, 97 Vaupés.
- Insular: 88 Archipiélago de San Andrés, Providencia y Santa Catalina.

La capital de cada departamento es el municipio `{código}001` (p. ej., 05001 Medellín), salvo Cundinamarca, cuya capital es Bogotá (11001). Siembra primero departamentos y capitales; el resto de municipios se importa desde la DIVIPOLA vigente del DANE (`supabase/seed/municipios_divipola.csv`), incluidas las áreas no municipalizadas de Amazonas, Guainía y Vaupés, que también deben aparecer en los selectores. En Bogotá se pide además la localidad: Usaquén, Chapinero, Santa Fe, San Cristóbal, Usme, Tunjuelito, Bosa, Kennedy, Fontibón, Engativá, Suba, Barrios Unidos, Teusaquillo, Los Mártires, Antonio Nariño, Puente Aranda, La Candelaria, Rafael Uribe Uribe, Ciudad Bolívar y Sumapaz.

**Estados de cuenta**: `pendiente → activo | rechazado`; `activo → suspendido | baneado`.

**Roles** (tabla `user_roles`; un usuario puede tener varios, cada uno con alcance territorial):

| Rol | Alcance | Lo otorga |
|---|---|---|
| `simpatizante` | su municipio | admin departamental o nacional |
| `voluntario` | su municipio | admin departamental o nacional |
| `lider` (con título, p. ej. "Líder de juventudes · Envigado") | municipal o departamental | admin departamental o nacional |
| `moderador` | uno o varios departamentos | admin de ese departamento o nacional |
| `admin_departamental` | uno o varios departamentos | solo admin nacional |
| `admin_nacional` ("Administrador Colombia") | todo el país | solo otro admin nacional (el primero se crea por SQL) |

No se puede quitar el último admin nacional. Nadie aprueba su propio contenido; las publicaciones de los admins salen directo y quedan en auditoría.

**Matriz de permisos**. Visitante: solo el sitio público y el contenido público. Cuenta pendiente: lo mismo, más su perfil y el estado de su solicitud.

| Acción | Simp. | Vol. | Líder | Mod. | Admin depto. | Admin Colombia |
|---|---|---|---|---|---|---|
| Ver feed de miembros, perfiles y grupos de WhatsApp aprobados | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Comentar, dar me gusta, compartir, guardar, seguir, escribir mensajes | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Solicitar verificación | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Crear publicaciones | configurable (por defecto no) | con aprobación | con aprobación | con aprobación | directo | directo |
| Proponer grupos de WhatsApp | – | con aprobación | con aprobación | con aprobación | directo | directo |
| Crear eventos | – | – | con aprobación | con aprobación | directo | directo |
| Aprobar publicaciones, grupos y eventos | – | – | – | su depto. | su depto. | todo, incluido lo nacional |
| Resolver reportes, advertir y silenciar | – | – | – | su depto. | su depto. | todo |
| Suspender cuentas | – | – | – | – | su depto. | todo |
| Banear definitivamente | – | – | – | – | – | ✓ |
| Aprobar cuentas y asignar roles hasta Líder | – | – | – | – | su depto. | todo |
| Nombrar moderadores | – | – | – | – | su depto. | todo |
| Nombrar o quitar admins departamentales y nacionales | – | – | – | – | – | ✓ |
| Otorgar insignia azul | – | – | – | – | su depto. | todo |
| Otorgar insignias dorada y gris | – | – | – | – | – | ✓ |
| Publicar como cuenta oficial | – | – | – | – | "Avancemos [Depto.]" | "Avancemos Colombia" y cualquier depto. |
| Enviar anuncios masivos | – | – | – | – | su depto. | todo |
| Usar el Estudio IA | – | – | – | – | con cuota | con cuota |
| Editar el sitio (CMS), propuestas y referentes | – | – | – | – | – | ✓ |
| Configuración global | – | – | – | – | – | ✓ |
| Ver auditoría y exportar CSV | – | – | – | – | su depto. | todo |

El contenido de alcance **nacional** solo lo aprueba el Administrador Colombia; el departamental y el municipal, los moderadores y admins de ese departamento. Un moderador o admin departamental puede **escalar** un caso: se marca `escalado_a_nacional = true`, sale de la cola departamental (que lo sigue viendo en solo lectura) y entra en la del nacional. Al aprobar, el revisor puede ajustar alcance y visibilidad.

**Cuentas oficiales**: "Avancemos Colombia" (@avancemos) y una por departamento (@avancemos_{slug}, p. ej. @avancemos_antioquia) son perfiles con `tipo_cuenta = 'oficial'` e insignia dorada. Se crean una sola vez con `supabase/seed/cuentas_oficiales.js`, que usa la API de administración con una contraseña aleatoria que nadie usa, ajusta el perfil (usuario, tipo, estado activo e insignia) y borra la solicitud automática. Nadie inicia sesión con ellas: los admins publican en su nombre con `publicar_oficial()`, que guarda al admin real en `publicado_por`, y sus notificaciones se ven en el panel.

## 6. Flujos de aprobación

### 6.1 Registro y rol
1. `unete.html`: nombre completo, correo, contraseña (mínimo 10 caracteres), @usuario (disponibilidad en vivo con la RPC `usuario_disponible`), departamento → municipio (selects dependientes) → localidad si es Bogotá, rol solicitado (Simpatizante, Voluntario o Líder), motivo (máx. 500 caracteres), ejes de interés (chips), ocupación (opcional), teléfono (opcional y privado), casilla "Soy mayor de 18 años", casilla de términos y normas, casilla de autorización de datos sensibles (texto en la sección 17) y Turnstile.
2. `supabase.auth.signUp` con metadatos → trigger `crear_perfil_nuevo_usuario` (`security definer`) que crea `perfiles` (estado `pendiente`), `solicitudes` (tipo `ingreso`) y `consentimientos`. El trigger valida: el rol solicitado solo puede ser simpatizante, voluntario o líder; el municipio pertenece al departamento; si el @usuario ya existe, genera uno libre. Un error aquí no puede romper el registro.
3. Tras confirmar el correo, el usuario ve la pantalla "En revisión" con línea de tiempo: Registrado → Correo confirmado → En revisión por el equipo de [Departamento] → Aprobado. Mientras tanto puede completar su perfil y ver contenido público, pero no publicar, comentar ni escribir.
4. El admin del departamento (o el nacional) revisa datos, motivo, antigüedad y coincidencias sospechosas (mismo teléfono o nombre que otra cuenta). Acciones: aprobar con el rol pedido u otro, rechazar con motivo o pedir más información.
5. Al aprobar: notificación en la app, correo "Tu cuenta fue aprobada" (`correo-aviso`) y recorrido de bienvenida: seguir líderes de su departamento, unirse a su grupo de WhatsApp y ver los próximos eventos.

### 6.2 Publicaciones
- Estados: `pendiente → aprobado | rechazado | cambios_solicitados`; `aprobado → retirado`.
- Al crear, un trigger fuerza `estado = 'pendiente'` (salvo auto-aprobación configurada), asigna `autor_id = auth.uid()` y calcula `departamento_moderacion` (NULL si el alcance es nacional).
- El cliente genera el `id` con `crypto.randomUUID()`, sube la media al bucket privado `media-pendiente/{dep}/{uid}/{publicacion_id}/…` (`dep` = código del departamento o `nacional`) y luego llama a la RPC `crear_publicacion`, que inserta la publicación y su media en una sola transacción. Así nadie ve una publicación pendiente sin sus archivos.
- Al aprobar, un Database Webhook llama a `publicar-media`, que copia la media a `media-publica` (visibilidad pública) o a `media-miembros` (solo miembros) y actualiza las rutas; si después cambia la visibilidad, la mueve. La media de lo rechazado se borra a los 30 días (`pg_cron`).
- Editar una publicación aprobada la devuelve a `pendiente` y la oculta hasta la nueva aprobación; el usuario lo ve advertido antes de guardar.
- Compartir dentro de la plataforma (repost sin texto) no requiere aprobación: el trigger lo marca aprobado y hereda la visibilidad del original. Citar con texto nuevo sí requiere aprobación.
- Al crearse, `moderar-ia` guarda un análisis de riesgo (sección 14). La IA nunca rechaza sola: solo ordena y marca la cola.
- El usuario ve sus publicaciones por estado: en revisión, aprobadas, con cambios solicitados y rechazadas (con motivo). Puede apelar una vez (sección 8).

### 6.3 Otros flujos
- **Grupos de WhatsApp**: sección 11. **Eventos**: igual que las publicaciones. **Verificación**: sección 10.
- **Traslado**: si un usuario cambia de departamento o municipio, se crea una solicitud de tipo `traslado` que aprueba el admin del destino; hasta entonces conserva el anterior. Los roles con alcance territorial se revisan en el traslado.

### 6.4 Motivos de rechazo predefinidos (editables en Configuración)
- Ataque personal o lenguaje ofensivo
- Información sin fuente o engañosa
- Datos personales de terceros
- Contenido de campaña que requiere revisión jurídica
- No corresponde al territorio o alcance elegido
- Spam, publicidad comercial o cadena
- Imagen o video inapropiado o de baja calidad
- Duplicado
- Otro (texto obligatorio)

## 7. Sitio público

Todo el contenido público sale de las tablas `paginas`, `propuestas` y `referentes` (editables en el CMS), con las semillas de las secciones 18–20. Cada página lleva título, descripción y etiquetas Open Graph y Twitter propias.

**`index.html`, en este orden:**
1. Barra superior fija con desenfoque: logo, menú (Quiénes somos, El centro, Referentes, Propuestas, Eventos), "Ingresar" y "Únete" (botón primario).
2. Héroe a pantalla completa: video o imagen con degradado azul noche, H1 con el lema, subtítulo, botones "Únete como voluntario" y "Conoce las propuestas", y contadores en vivo (miembros activos, departamentos y municipios con presencia) que solo aparecen si superan un mínimo configurable.
3. Qué es Avancemos: misión, visión y cómo trabajamos, con los valores en chips.
4. Propuestas: tarjetas por eje (ícono, título, resumen, "Ver más").
5. Cómo participar en 3 pasos: Regístrate → Tu equipo departamental te aprueba → Súmate a tu grupo y a las actividades.
6. Mapa de presencia: mapa coroplético de Colombia por departamento, escala en turquesa, tooltip con conteo agregado ("menos de 5" si no llega al umbral) y enlace a la página del departamento.
7. El centro político: resumen y enlace a `el-centro.html`.
8. Referentes: carrusel de tarjetas y enlace.
9. Publicaciones oficiales recientes con visibilidad pública.
10. Próximos eventos públicos.
11. Voces de Avancemos: **solo** testimonios reales con autorización escrita guardada. Si no hay, la sección no se muestra. Nunca se inventan.
12. Llamado final a unirse y pie de página: enlaces legales, redes, contacto y responsable del tratamiento de datos.

**Otras páginas**: `quienes-somos` (manifiesto, valores, organización territorial, preguntas frecuentes), `el-centro` (sección 18), `referentes` (sección 19, con filtro Colombia/Mundo), `propuestas` (detalle por eje), `eventos` (lista, mapa y filtros), `publicacion.html?id=` (publicación pública, legible sin sesión), `insignias`, `normas`, `privacidad` y `terminos`.

## 8. Red social (`app.html`)

**Rutas**: `#/inicio`, `#/explorar`, `#/publicar`, `#/p/:id`, `#/u/:usuario`, `#/mensajes`, `#/mensajes/:id`, `#/notificaciones`, `#/guardados`, `#/grupos`, `#/eventos`, `#/eventos/:id`, `#/d/:departamento`, `#/m/:municipio`, `#/buscar?q=`, `#/ajustes`, `#/verificacion`.

**Feed**: pestañas Nacional · Mi departamento · Mi municipio · Siguiendo. Orden cronológico con las publicaciones oficiales fijadas arriba. Scroll infinito con cursor (`publicado_en`, `id`).

**Redactar**: texto de hasta 3.000 caracteres ("Ver más" a partir de 280), hasta 4 imágenes o 1 video (máx. 50 MB y 2 min; lo más largo, por enlace de YouTube), enlace con vista previa, categoría (opinión, propuesta, noticia, convocatoria, logro, pregunta), alcance (nacional, departamental o municipal; el territorio es siempre el del autor, salvo para el admin nacional), visibilidad (pública o solo miembros; al elegir pública se avisa que el nombre del autor se verá fuera de la red), #hashtags y @menciones con autocompletado, botón opcional "Revisar con IA", contador de caracteres, borrador guardado localmente y el aviso "Tu publicación será revisada por el equipo de [Departamento] antes de publicarse". Las imágenes se comprimen en el navegador a WebP de máx. 1600 px antes de subir; del video se captura un póster con canvas. Si el rol del usuario no puede publicar (`roles_pueden_publicar`), el botón Publicar invita a solicitar el rol de voluntario.

**Tarjeta de publicación**: avatar, nombre, insignia, @usuario, cargo, territorio y tiempo relativo; texto con enlaces, #hashtags y @menciones; media en grilla; acciones: me gusta, comentar, compartir (repostear, copiar enlace, enviar por WhatsApp con `https://wa.me/?text=`), guardar y reportar; sellos "Oficial" y "Generada con IA" cuando apliquen. Los enlaces de YouTube se incrustan con `youtube-nocookie.com`.

**Comentarios**: respuestas de un nivel, me gusta, orden por relevantes o recientes, reportar; los moderadores pueden ocultar. Sin aprobación previa, pero con filtro de palabras y límites.

**Perfil**: portada, avatar, nombre, insignia, @usuario, rol y cargo, territorio (el municipio solo si el usuario lo permite), bio, ejes de interés, redes y fecha de ingreso; contadores; pestañas Publicaciones, Respuestas, Me gusta (solo el propio) y Eventos. Botones: Seguir, Mensaje (según privacidad), Compartir perfil, Reportar y Bloquear.

**Ajustes**: editar perfil (con recorte de avatar), privacidad (perfil visible fuera de la red sí/no, mostrar municipio, quién puede escribirme: todos / personas que sigo / nadie), notificaciones por tipo, seguridad (cambiar contraseña, cerrar sesión en todos los dispositivos), mis datos (descargar en JSON, eliminar cuenta), solicitar verificación, y solicitar traslado o cambio de rol.

**Explorar y buscar**: personas (trigramas), publicaciones (búsqueda de texto en español), hashtags, tendencias de las últimas 48 h, líderes por departamento y eventos.

**Apelaciones**: el usuario puede apelar una vez un rechazo o una sanción; la revisa un admin distinto o el nacional.

## 9. Panel de administración (`admin.html`)

**Acceso**: sesión + rol de moderador o superior + MFA (`aal2`). Sin MFA, el panel muestra el enrolamiento TOTP con código QR (`supabase.auth.mfa.enroll`). Todas las RPC de administración verifican `aal2` en el servidor.

**Barra superior**: selector de territorio (el nacional elige "Toda Colombia" o un departamento; el departamental solo ve los suyos), búsqueda global y contadores en vivo de pendientes.

**Secciones:**
1. **Resumen**: pendientes por tipo, registros de 7 y 30 días, miembros activos por rol, publicaciones aprobadas vs. rechazadas, tiempo medio de aprobación, pendientes con más de 24 h, reportes abiertos, gráficas (Chart.js), mapa y, para el nacional, departamentos sin administrador.
2. **Aprobaciones** (bandeja unificada con pestañas Usuarios · Publicaciones · Grupos de WhatsApp · Eventos · Verificaciones · Traslados · Apelaciones): vista previa idéntica a como se verá publicado, ficha del autor (antigüedad, historial, sanciones, reportes), análisis de IA con su motivo, y botones Aprobar / Rechazar (con motivo) / Pedir cambios / Escalar a nacional. Atajos: A aprobar, R rechazar, C pedir cambios, J/K siguiente y anterior. Acciones masivas para usuarios. Si otro admin ya resolvió el ítem, avisar (la RPC actualiza solo `where estado = 'pendiente'`).
3. **Usuarios**: tabla filtrable (departamento, municipio, rol, estado, insignia, fecha) con búsqueda; ficha lateral con roles, historial y auditoría; acciones: cambiar rol, asignar título de líder, suspender, banear (solo nacional), reactivar, otorgar o quitar insignia.
4. **Equipo**: el nacional nombra y quita admins departamentales; el departamental, moderadores. Vista de cobertura por departamento.
5. **Reportes**: cola con captura del contenido, motivo y reportante; acciones: descartar, ocultar contenido, advertir, silenciar 24 h o 7 días, suspender, banear. Los reportes por amenaza o riesgo para la seguridad llegan con prioridad alta y notifican de inmediato al admin del departamento y al nacional.
6. **Contenido del sitio** (solo nacional): editor Markdown con vista previa e historial de versiones restaurables; CRUD de propuestas y referentes (con fuentes); héroe (lema, subtítulo, media), banners, preguntas frecuentes y versiones de los textos legales.
7. **Publicar como oficial**: con la cuenta "Avancemos Colombia" (nacional) o "Avancemos [Departamento]" (departamental); fijar, programar fecha y ver las notificaciones de la cuenta.
8. **Estudio IA** (sección 14).
9. **Biblioteca de medios**: todo lo subido o generado, con filtros, sello de IA y dónde se usa.
10. **Comunicaciones**: anuncios por territorio y rol (notificación en la app y correo opcional), con historial.
11. **Grupos de WhatsApp y Eventos**: gestión completa, marcar enlace roto, desactivar.
12. **Configuración** (solo nacional): el bloque `configuracion` de la sección 15.
13. **Auditoría**: registro inmutable y filtrable (quién, qué, cuándo, antes/después, territorio), exportable.
14. **Exportar**: CSV de miembros de su territorio, sin teléfono salvo casilla explícita; exige MFA reciente (claim `amr` del JWT con método `totp` de hace menos de 15 minutos) y queda en auditoría.

## 10. Verificación estilo X

| Insignia | Significado | La otorga |
|---|---|---|
| Azul | Identidad verificada por Avancemos | admin departamental (su depto.) o nacional |
| Dorada | Vocería o liderazgo oficial de Avancemos, y cuentas oficiales | solo admin nacional |
| Gris | Cargo de elección popular o servidor público (concejal, diputado, alcalde, congresista…) | solo admin nacional |

- Requisitos para solicitarla (validados en el servidor, configurables): cuenta activa hace 30 días, foto de perfil, nombre real, bio y ninguna sanción en 90 días.
- Solicitud: tipo de insignia, cargo o rol, motivo, enlaces de soporte y método preferido (videollamada o presencial).
- Revisión con lista de chequeo y decisión con método usado y notas internas. **No se guarda número ni foto de la cédula**: la identidad se confirma en videollamada o en persona, y solo se registra el método, quién y cuándo.
- La insignia aparece en todas partes (feed, perfil, comentarios, búsqueda, mensajes) con tooltip y enlace a `insignias.html`.
- Si un verificado cambia nombre, @usuario o foto, la insignia se suspende automáticamente (trigger) y se abre una solicitud de revalidación.
- Revocación con motivo notificado al usuario.
- @usuarios reservados: los que contengan "avancemos", "oficial", "admin" o "soporte", y los nombres de departamentos.

## 11. Grupos de WhatsApp

- Proponen voluntarios, líderes y admins. Campos: nombre, descripción, tipo (grupo, comunidad o canal), tema (general, juventudes, mujeres, eventos, comunicaciones…), alcance y territorio, y enlace.
- Validación del enlace en cliente y servidor (CHECK o trigger), normalizado sin parámetros y sin duplicados:
  - Grupos: `^https://chat\.whatsapp\.com/[A-Za-z0-9]{20,24}$`
  - Canales: `^https://(www\.)?whatsapp\.com/channel/[A-Za-z0-9]+$`
- Estados: `pendiente → aprobado | rechazado`; `aprobado → retirado` (enlace roto o grupo cerrado).
- Solo visibles para miembros activos, nunca en el sitio público (evita spam e infiltración). Por defecto cada miembro ve los de su departamento y los nacionales; configurable a "todos".
- Antes de abrir el enlace, aviso: "Al unirte, los demás miembros del grupo pueden ver tu número de teléfono". Para difusión masiva se recomiendan canales o comunidades.
- Botón "El enlace no funciona": con 3 reportes, el grupo vuelve a revisión.
- Directorio con buscador por departamento y municipio; también aparece en las páginas de territorio.

## 12. Mensajes directos y notificaciones

**Mensajes 1 a 1**
- Solo entre cuentas activas. Se respeta la preferencia del destinatario (todos / personas que sigo / nadie); los admins de su departamento siempre pueden escribirle para coordinación. Un bloqueo impide todo contacto.
- Se inician con la RPC `iniciar_conversacion(destinatario)`, que valida permisos y límites, y reutiliza la conversación existente.
- Tiempo real con Supabase Realtime (canal por conversación), "escribiendo…" por Broadcast, leídos con `ultimo_leido_en`, texto de hasta 2.000 caracteres e imagen opcional (bucket privado `mensajes`, URLs firmadas).
- **Ningún admin puede leer mensajes privados.** Si alguien reporta un mensaje, el reporte guarda una copia de ese mensaje, y solo de ese, para revisión.
- Límite de conversaciones nuevas por día: 20 (5 para cuentas de menos de 7 días).

**Notificaciones**
- Tabla `notificaciones` llenada por triggers: me gusta (agrupados: "A Ana y 12 personas más…"), comentarios, respuestas, menciones, nuevos seguidores, mensajes, aprobación / rechazo / cambios solicitados (con motivo), verificación, anuncios y recordatorio de eventos 24 h antes (`pg_cron`).
- Campana con contador en vivo (Realtime filtrado por `user_id`), marcar como leídas y preferencias por tipo.
- Admins: contador de pendientes de su territorio y resumen diario por correo si tienen ítems con más de 24 h.
- Opcional: Web Push con VAPID desde una Edge Function.

## 13. Eventos, páginas de territorio y mapa

**Eventos**: tipo (reunión, foro, capacitación, jornada de voluntariado, virtual), inicio y fin, lugar, dirección y punto en el mapa (Leaflet, clic para ubicar) o enlace virtual, cupo, imagen, visibilidad (pública o miembros) y opción "mostrar la dirección solo a inscritos". Los crean líderes y admins. Inscripción ("Voy" / "Me interesa"), lista de asistentes para el organizador, botón "Agregar al calendario" (.ics y Google Calendar) y recordatorio.

**Páginas de territorio**
- `#/d/:departamento`: portada (foto real o imagen IA con sello), nombre, capital, región, contadores agregados y pestañas Oficiales ("Avancemos [Depto.]"), Comunidad, Eventos, Grupos de WhatsApp, Líderes (solo perfiles visibles) y Municipios con presencia.
- `#/m/:municipio`: lo mismo a escala municipal.

**Mapa**: coroplético por departamento con GeoJSON local (unido por el campo `DPTO_CCDGO` del MGN) y San Andrés en un recuadro aparte. Nunca se muestran puntos de personas. Los conteos por debajo del umbral (5 por defecto) se muestran como "menos de 5". Los datos vienen de la función `estadisticas_publicas()` (`security definer`, solo agregados).

## 14. Vertex AI (imágenes, video y texto)

**Arquitectura**: todas las llamadas pasan por Edge Functions; el navegador nunca ve credenciales de Google. Si se prefiere, estas funciones pueden vivir en un servidor Node.js propio con el mismo contrato de entrada y salida.

**Modelos** (IDs en variables de entorno, nunca escritos en el código):

| Variable | Valor inicial | Uso | Ubicación |
|---|---|---|---|
| `VERTEX_MODEL_TEXT` | `gemini-3.8-flash` | moderación asistida, texto alternativo, mejora de prompts, borradores | `global` |
| `VERTEX_MODEL_IMAGE` | `gemini-3.1-flash-image` | generar y editar imágenes | `global` |
| `VERTEX_MODEL_VIDEO` | `veo-3.1-generate-001` | video: texto → video e imagen → video | `us-central1` |

- Para imágenes usa Gemini Image (`:generateContent`), que es lo que prioriza la documentación actual de Google; no uses el API de Imagen (`:predict`).
- `gemini-3.8-flash` acepta `thinkingLevel` `LOW`, `MEDIUM` (por defecto) y `HIGH`; `MINIMAL` devuelve error. Usa `LOW` para moderación y texto alternativo.
- Verifica en Model Garden que los IDs y las ubicaciones sigan vigentes; si un modelo no está en `global`, cambia su variable de ubicación.

**Secretos**: `GCP_PROJECT_ID`, `GCP_SA_KEY_B64` (JSON de la cuenta de servicio en base64, con rol `roles/aiplatform.user`), `VERTEX_LOCATION_TEXT`, `VERTEX_LOCATION_IMAGE`, `VERTEX_LOCATION_VIDEO`, los tres `VERTEX_MODEL_*` y `RESEND_API_KEY` (correos).

**`_shared/vertex.ts`** (token OAuth firmado con la cuenta de servicio y guardado en caché ~1 h):

```ts
import { SignJWT, importPKCS8 } from "npm:jose@5";

let cache: { token: string; exp: number } | null = null;

export async function tokenGoogle(): Promise<string> {
  if (cache && cache.exp > Date.now() + 60_000) return cache.token;
  const sa = JSON.parse(atob(Deno.env.get("GCP_SA_KEY_B64")!));
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/cloud-platform" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!r.ok) throw new Error(`OAuth Google ${r.status}: ${await r.text()}`);
  const { access_token, expires_in } = await r.json();
  cache = { token: access_token, exp: Date.now() + expires_in * 1000 };
  return access_token;
}

export function urlModelo(ubicacion: string, modelo: string, metodo: string): string {
  const host = ubicacion === "global" ? "aiplatform.googleapis.com" : `${ubicacion}-aiplatform.googleapis.com`;
  const proyecto = Deno.env.get("GCP_PROJECT_ID");
  return `https://${host}/v1/projects/${proyecto}/locations/${ubicacion}/publishers/google/models/${modelo}:${metodo}`;
}
```

**Funciones:**
1. **`ia-imagen`** — `POST { accion: "generar" | "editar", descripcion, formato: "1:1" | "3:4" | "4:3" | "9:16" | "16:9", cantidad: 1–4, estilo, media_base_id? }`
   - Valida el JWT del usuario y llama a `puede_usar_ia('imagen')` (rol admin, `aal2` y cuota disponible).
   - Aplica los guardarraíles (abajo).
   - "Mejorar descripción": Gemini reescribe la petición como un prompt detallado en inglés + el estilo de marca, y lo devuelve para que el admin lo edite antes de generar.
   - Llama `:generateContent` con `generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio } }`. Para editar, envía la imagen base como `inlineData` junto con la instrucción. Para varias imágenes, N solicitudes en paralelo.
   - Cada `parts[].inlineData` se guarda en el bucket `ia-media`, se registra en `media`, se suma a la cuota y se escribe en auditoría. Devuelve las URLs.
2. **`ia-video`** — acciones `iniciar`, `estado` y `procesar`.
   - `iniciar`: `:predictLongRunning` con `instances: [{ prompt, image?: { bytesBase64Encoded, mimeType } }]` y `parameters: { aspectRatio: "16:9" | "9:16", durationSeconds, resolution: "720p" | "1080p", generateAudio, personGeneration: "allow_adult", sampleCount: 1, storageUri? }`. Por defecto, 8 s y 720p; toma de la página del modelo los valores permitidos de `durationSeconds` y `resolution` y ofrécelos como opciones en el Estudio IA. Guarda el nombre de la operación en `ia_trabajos` y devuelve el id del trabajo.
   - `estado`: `:fetchPredictOperation` con `{ operationName }`. Cuando `done` es `true`, toma `response.videos[]` (`bytesBase64Encoded`, o `gcsUri` si se usó `storageUri`), lo sube a `ia-media` y crea el registro en `media`.
   - `procesar`: un job de `pg_cron` cada minuto (con `pg_net` y la llave guardada en Vault) cierra los trabajos pendientes aunque el admin cierre la pestaña.
   - Envía solo los parámetros que el modelo soporte, según su página en la documentación. Para 1080p conviene usar `storageUri` (un bucket de Cloud Storage) y descargar desde allí, en lugar de recibir el video en base64.
3. **`ia-texto`** — acciones `texto_alternativo` y `revisar_borrador` (tono, ataques personales, datos sin fuente; solo sugerencias al usuario), disponibles para cualquier miembro activo con cuota diaria de textos; y `mejorar_prompt`, `redactar` (borradores oficiales) y `resumen_semanal` (por departamento), solo para admins.
4. **`moderar-ia`** — Database Webhook en INSERT de `publicaciones`, `eventos` y `grupos_whatsapp` (y en UPDATE cuando cambia el contenido). Envía el texto y las imágenes adjuntas a Gemini con `responseMimeType: "application/json"` y `responseSchema`, y guarda en la columna `ia_moderacion` de cada tabla: `{ riesgo: "bajo" | "medio" | "alto", categorias: [...], motivo, sugerencia: "aprobar" | "revisar" | "rechazar" }`. Categorías: ataque personal, odio o discriminación, violencia o amenaza, posible desinformación, datos personales, spam, contenido sexual, propaganda electoral, ninguna. Nunca rechaza sola.

**Guardarraíles** (se validan en el servidor antes de llamar al modelo):
- Prohibido generar: personas reales identificables (políticos, candidatos, periodistas, funcionarios), logos o símbolos de partidos, menores de edad, armas o violencia, y escenas que simulen hechos reales (eventos, multitudes o declaraciones que no ocurrieron).
- Doble filtro: lista `ia_terminos_bloqueados` + clasificación rápida con Gemini ("¿pide una persona real, un partido, violencia, menores o desinformación?").
- Todo archivo generado lleva `etiqueta_ia = true` y el sello visible "Generada con IA" en tarjetas, héroes y páginas, además de la marca de agua invisible que añade Google.
- Cuotas diarias por rol (bloque `configuracion`, sección 15) y alerta de presupuesto mensual en Google Cloud.

**Estudio IA (panel)**: pestañas Imagen · Video · Editar imagen · Plantillas · Historial; cuota restante visible; en cada resultado: descargar, guardar en la biblioteca, usar como portada (héroe, página, departamento) o adjuntar a una publicación oficial.

**Estilo de marca** (se añade a todos los prompts; editable): `warm natural light, subtle teal and amber tones, editorial documentary photography, dignified and optimistic, realistic, no text, no logos`.

**Plantillas iniciales** (en inglés, rinden mejor):
1. Héroe, video 16:9, 8 s: `Slow aerial drone shot at golden hour over the Colombian Andes: morning mist, coffee farms and a small town with a white church. Cinematic, natural colors, no text, no close-up faces.`
2. Héroe móvil: el mismo en 9:16.
3. Quiénes somos, imagen 16:9: `Documentary photo of a diverse group of Colombian adult volunteers seen from behind, walking up a colorful street in a mountain town, warm light, candid, no logos, no text.`
4. Educación: `Bright public school library in a small Colombian town, wooden shelves, afternoon light, empty, editorial photography, no text.`
5. Campo y agua: `Aerial view of a river winding through green farmland in the Colombian Llanos at sunrise, editorial photography, no text.`
6. Ciudad: `Cable car over hillside neighborhoods of a Colombian city at dusk, city lights, cinematic, no text.`
7. Diálogo: `Top-down view of a round wooden table with notebooks, coffee cups and printed maps, soft light, no people, no text.`
8. Portadas de departamento: `Iconic landscape of [PAISAJE], [DEPARTAMENTO], Colombia, editorial travel photography, no people, no text.` Ejemplos: Quindío (Valle de Cocora y palmas de cera), Meta (Caño Cristales), Bolívar (murallas de Cartagena), La Guajira (Cabo de la Vela), Boyacá (Villa de Leyva), Nariño (Laguna de La Cocha), Amazonas (río Amazonas), San Andrés (mar de siete colores).

## 15. Modelo de datos

**Tipos**: `estado_cuenta` (pendiente, activo, rechazado, suspendido, baneado) · `rol_app` (simpatizante, voluntario, lider, moderador, admin_departamental, admin_nacional) · `estado_revision` (pendiente, aprobado, rechazado, cambios_solicitados, retirado) · `insignia` (ninguna, azul, dorada, gris) · `alcance` (nacional, departamental, municipal) · `visibilidad` (publica, miembros).

**Territorio**
- `departamentos` (`id` text PK = DIVIPOLA de 2 dígitos, `nombre`, `slug` único, `region`, `capital_id`)
- `municipios` (`id` text PK = DIVIPOLA de 5 dígitos, `departamento_id`, `nombre`, `slug`, `es_capital`)
- `localidades_bogota` (`id` 1–20, `nombre`)

**Personas**
- `perfiles` (`id` uuid PK → `auth.users` on delete cascade, `tipo_cuenta` (persona, oficial), `username` citext único `^[a-z0-9_]{3,30}$`, `nombre`, `bio` ≤ 280, `avatar_path`, `portada_path`, `departamento_id`, `municipio_id`, `localidad_id`, `cargo_titulo` (lo asigna un admin), `ocupacion`, `intereses` text[], `redes` jsonb, `estado`, `insignia` (defecto `ninguna`), `insignia_suspendida`, `insignia_otorgada_por`, `insignia_otorgada_en`, `perfil_publico` (defecto **false**), `mostrar_municipio` (defecto true), `dm_permitidos` (todos, seguidos, nadie; defecto seguidos), contadores `seguidores_n`, `siguiendo_n`, `publicaciones_n`, `ultimo_cambio_usuario`, `created_at`, `updated_at`)
- `perfiles_privados` (`id` PK → perfiles, `telefono`, `notas_admin`): solo el dueño y los admins de su departamento
- `user_roles` (`id`, `user_id`, `rol`, `departamento_id` null, `municipio_id` null, `titulo`, `activo`, `otorgado_por`, `created_at`; único por usuario + rol + territorio)
- `solicitudes` (`id`, `user_id`, `tipo` (ingreso, cambio_rol, traslado), `rol_solicitado`, `departamento_id`, `municipio_id`, `motivo`, `estado`, `revisado_por`, `revisado_en`, `comentario_admin`, `created_at`)
- `consentimientos` (`id`, `user_id`, `version_politica`, `acepta_terminos`, `autoriza_datos_sensibles`, `mayor_de_edad`, `user_agent`, `created_at`)
- `seguidores` (`seguidor_id`, `seguido_id`, `created_at`) · `bloqueos` (`bloqueador_id`, `bloqueado_id`, `created_at`)

**Contenido**
- `publicaciones` (`id` uuid, `autor_id`, `contenido` ≤ 3000, `categoria`, `alcance`, `departamento_id`, `municipio_id`, `departamento_moderacion` (NULL = nacional), `visibilidad`, `estado`, `motivo_revision`, `revisado_por`, `revisado_en`, `escalado_a_nacional`, `publicado_en`, `programada_para`, `es_oficial`, `publicado_por` (admin real en las oficiales), `fijada`, `enlace_url`, `enlace_preview` jsonb, `repost_de`, `ia_moderacion` jsonb, `me_gusta_n`, `comentarios_n`, `compartidos_n`, `busqueda` tsvector generada (español + `unaccent` con envoltorio inmutable), `eliminado_en`, `created_at`, `updated_at`)
- `publicacion_media` (`id`, `publicacion_id`, `tipo` (imagen, video), `bucket`, `path`, `ancho`, `alto`, `duracion_s`, `alt_text`, `orden`, `generada_ia`)
- `comentarios` (`id`, `publicacion_id`, `autor_id`, `padre_id` null, `contenido` ≤ 1000, `estado` (visible, oculto, eliminado), `marcado_revision`, `me_gusta_n`, `created_at`)
- `me_gusta` (`publicacion_id`, `user_id`, `created_at`) · `me_gusta_comentario` (`comentario_id`, `user_id`) · `guardados` (`user_id`, `publicacion_id`, `created_at`)
- `hashtags` (`tag` PK) · `publicacion_hashtags` (`publicacion_id`, `tag`) · `menciones` (`publicacion_id` o `comentario_id`, `mencionado_id`): se llenan por trigger al aprobar

**Mensajería**
- `conversaciones` (`id`, `created_at`, `ultimo_mensaje_en`, `ultimo_mensaje_preview`)
- `conversacion_participantes` (`conversacion_id`, `user_id`, `ultimo_leido_en`, `silenciada`)
- `mensajes` (`id`, `conversacion_id`, `autor_id`, `contenido` ≤ 2000, `media_path`, `eliminado`, `created_at`)

**Organización**
- `grupos_whatsapp` (`id`, `nombre`, `descripcion`, `tipo`, `tema`, `alcance`, `departamento_id`, `municipio_id`, `departamento_moderacion`, `url` único, `creado_por`, `estado`, `motivo_revision`, `revisado_por`, `revisado_en`, `escalado_a_nacional`, `ia_moderacion` jsonb, `reportes_enlace_roto`, `created_at`)
- `eventos` (`id`, `titulo`, `descripcion`, `tipo`, `inicio`, `fin`, `modalidad` (presencial, virtual, mixta), `lugar`, `direccion`, `lat`, `lng`, `url_virtual`, `direccion_solo_inscritos`, `cupo`, `imagen_path`, `alcance`, `departamento_id`, `municipio_id`, `departamento_moderacion`, `visibilidad`, `organizador_id`, `estado`, `motivo_revision`, `revisado_por`, `revisado_en`, `escalado_a_nacional`, `ia_moderacion` jsonb, `asistentes_n`, `created_at`) · `evento_asistentes` (`evento_id`, `user_id`, `respuesta` (voy, interesado), `created_at`)
- `solicitudes_verificacion` (`id`, `user_id`, `insignia_solicitada`, `cargo`, `motivo`, `enlaces` text[], `metodo_preferido`, `es_revalidacion`, `estado`, `metodo_usado`, `notas_internas`, `revisado_por`, `revisado_en`, `created_at`)
- `anuncios` (`id`, `autor_id`, `titulo`, `cuerpo`, `departamento_id` (NULL = nacional), `roles_destino` rol_app[], `enviar_correo`, `created_at`)

**Moderación y control**
- `reportes` (`id`, `reportado_por`, `entidad` (publicacion, comentario, mensaje, perfil, grupo, evento), `entidad_id`, `motivo` (odio, acoso, amenaza_seguridad, violencia, desinformacion, spam, datos_personales, suplantacion, sexual, enlace_roto, otro), `detalle`, `snapshot` jsonb, `departamento_moderacion`, `escalado_a_nacional`, `prioridad` (normal, alta), `estado` (abierto, en_revision, resuelto, descartado), `resuelto_por`, `resolucion`, `created_at`)
- `sanciones` (`id`, `user_id`, `tipo` (advertencia, silencio, suspension, baneo), `motivo`, `hasta`, `impuesta_por`, `created_at`) · `apelaciones` (`id`, `user_id`, `entidad`, `entidad_id`, `texto`, `estado`, `resuelta_por`, `created_at`)
- `palabras_bloqueadas` (`palabra`, `nivel` (bloquear, revisar))
- `auditoria` (`id` bigint identity, `actor_id`, `accion`, `entidad`, `entidad_id`, `departamento_id`, `antes` jsonb, `despues` jsonb, `created_at`): solo inserción desde funciones; sin UPDATE ni DELETE para nadie
- `notificaciones` (`id`, `user_id`, `tipo`, `actor_id`, `entidad`, `entidad_id`, `texto`, `agrupadas_n`, `leida`, `created_at`)
- `configuracion` (`clave` PK, `valor` jsonb, `updated_by`, `updated_at`)

**Sitio y medios**
- `paginas` (`slug` PK, `titulo`, `contenido_md`, `seo_titulo`, `seo_descripcion`, `publicada`, `updated_by`, `updated_at`) + `paginas_versiones`
- `propuestas` (`id`, `eje`, `titulo`, `resumen`, `detalle_md`, `icono`, `orden`, `publicada`)
- `referentes` (`id`, `nombre`, `ambito` (colombia, mundo), `pais`, `orientacion`, `cargos`, `logros` text[], `contexto`, `leccion`, `fuentes` text[], `imagen_path`, `credito_imagen`, `orden`, `publicado`)
- `media` (`id`, `bucket`, `path`, `tipo`, `mime`, `ancho`, `alto`, `duracion_s`, `origen` (subida, ia_imagen, ia_video, ia_edicion), `prompt`, `prompt_final`, `modelo`, `etiqueta_ia`, `creado_por`, `created_at`)
- `ia_trabajos` (`id`, `tipo`, `estado` (en_cola, procesando, completado, error), `operacion`, `parametros` jsonb, `media_ids` uuid[], `error`, `costo_estimado_usd`, `solicitado_por`, `created_at`, `completado_en`) · `ia_uso_diario` (`user_id`, `fecha`, `imagenes`, `videos`, `textos`)
- `vistas_previas_enlace` (`url` PK, `titulo`, `descripcion`, `imagen`, `sitio`, `obtenida_en`)

**Funciones RPC** (todas `security definer` con `set search_path = ''`; verifican permisos y MFA cuando aplica, escriben en `auditoria` y generan la notificación):
- Miembros: `usuario_disponible`, `mis_permisos`, `feed(tipo, cursor, limite)`, `buscar`, `crear_publicacion`, `iniciar_conversacion`, `reportar` (valida que el reportante pueda ver el contenido y guarda el `snapshot`), `solicitar_verificacion` (valida requisitos), `cambiar_usuario` (reservados y 30 días entre cambios), `exportar_mis_datos`.
- Público (sin sesión; del autor solo devuelve nombre, usuario, avatar e insignia): `feed_publico(cursor, limite)`, `publicacion_publica(id)`, `estadisticas_publicas`.
- Administración: `revisar_solicitud`, `revisar_publicacion`, `revisar_grupo`, `revisar_evento`, `revisar_verificacion`, `escalar`, `asignar_rol`, `revocar_rol`, `otorgar_insignia`, `revocar_insignia`, `sancionar`, `resolver_reporte`, `resolver_apelacion`, `publicar_oficial`, `enviar_anuncio`, `exportar_miembros`, `actualizar_configuracion`, `puede_usar_ia`.

**Índices mínimos**: `publicaciones (estado, publicado_en desc, id desc)`, `(departamento_id, estado, publicado_en desc)`, `(municipio_id, estado, publicado_en desc)`, `(autor_id, created_at desc)`, parcial `(departamento_moderacion) where estado = 'pendiente'`, GIN en `busqueda`; GIN de trigramas en `perfiles.username` y `perfiles.nombre`; `user_roles (user_id) where activo`; `comentarios (publicacion_id, created_at)`; `mensajes (conversacion_id, created_at desc)`; `notificaciones (user_id, leida, created_at desc)`; `seguidores (seguido_id)`.

**Bloque `configuracion` inicial:**

```json
{
  "auto_aprobacion_roles": ["admin_departamental", "admin_nacional"],
  "roles_pueden_publicar": ["voluntario", "lider", "moderador", "admin_departamental", "admin_nacional"],
  "limites": {
    "publicaciones_dia": 10,
    "publicaciones_dia_nuevos": 3,
    "comentarios_hora": 30,
    "conversaciones_nuevas_dia": 20,
    "conversaciones_nuevas_dia_nuevos": 5,
    "dias_usuario_nuevo": 7
  },
  "umbral_privacidad_mapa": 5,
  "contadores_inicio_minimo": 100,
  "visibilidad_grupos_whatsapp": "mi_departamento_y_nacionales",
  "verificacion": { "dias_antiguedad": 30, "dias_sin_sancion": 90 },
  "ia_cuotas_diarias": {
    "miembro": { "textos": 30 },
    "admin_departamental": { "imagenes": 20, "videos": 2, "textos": 100 },
    "admin_nacional": { "imagenes": 60, "videos": 10, "textos": 300 }
  },
  "ia_estilo_marca": "warm natural light, subtle teal and amber tones, editorial documentary photography, dignified and optimistic, realistic, no text, no logos",
  "ia_terminos_bloqueados": ["[nombres de políticos y partidos a bloquear]"],
  "motivos_rechazo": ["Ataque personal o lenguaje ofensivo", "Información sin fuente o engañosa", "…el resto de la sección 6.4"],
  "eliminacion_cuenta": "anonimizar",
  "modo_campana": false,
  "modo_mantenimiento": false
}
```

`eliminacion_cuenta` admite `anonimizar` (las publicaciones quedan como "Cuenta eliminada") o `borrar`.

## 16. Seguridad

**RLS en todas las tablas**, denegando por defecto. Funciones de apoyo:

```sql
create or replace function public.tiene_rol(r public.rol_app)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_roles ur
                 where ur.user_id = (select auth.uid()) and ur.rol = r and ur.activo);
$$;

create or replace function public.es_admin_nacional()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.tiene_rol('admin_nacional');
$$;

create or replace function public.es_miembro_activo()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfiles p
                 where p.id = (select auth.uid()) and p.estado = 'activo');
$$;

-- dep NULL = contenido nacional: solo el admin nacional
create or replace function public.puede_moderar(dep text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin_nacional()
      or (dep is not null and exists (
            select 1 from public.user_roles ur
            where ur.user_id = (select auth.uid()) and ur.activo
              and ur.rol in ('admin_departamental', 'moderador')
              and ur.departamento_id = dep));
$$;

create or replace function public.es_admin_de(dep text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin_nacional()
      or (dep is not null and exists (
            select 1 from public.user_roles ur
            where ur.user_id = (select auth.uid()) and ur.activo
              and ur.rol = 'admin_departamental' and ur.departamento_id = dep));
$$;

create or replace function public.exigir_mfa()
returns void language plpgsql stable set search_path = '' as $$
begin
  if coalesce((select auth.jwt() ->> 'aal'), 'aal1') <> 'aal2' then
    raise exception 'Se requiere verificación en dos pasos' using errcode = '42501';
  end if;
end $$;
```

Ejemplo de política y de permisos por columna:

```sql
alter table public.publicaciones enable row level security;

create policy "ver publicaciones" on public.publicaciones for select using (
  (estado = 'aprobado' and publicado_en <= now() and eliminado_en is null
     and (visibilidad = 'publica' or (select public.es_miembro_activo())))
  or autor_id = (select auth.uid())
  or public.puede_moderar(departamento_moderacion)
);

-- El usuario solo puede editar estas columnas de su perfil; estado, insignia,
-- username y territorio cambian únicamente por RPC.
revoke update on public.perfiles from anon, authenticated;
grant update (nombre, bio, avatar_path, portada_path, intereses, redes, ocupacion,
              perfil_publico, mostrar_municipio, dm_permitidos)
  on public.perfiles to authenticated;
```

Envuelve en `(select …)` las funciones que no dependen de la fila, para que Postgres las evalúe una sola vez por consulta. Aplica el mismo patrón de permisos por columna en `publicaciones`, `comentarios`, `eventos` y `grupos_whatsapp`: el usuario solo edita sus campos de contenido; estado, revisión y contadores los cambian triggers y RPC.

**Reglas**
- Triggers: forzar estado y autor al crear; recalcular contadores; límites por tiempo (leídos de `configuracion`); palabras bloqueadas (nivel `bloquear` rechaza con un mensaje amable; nivel `revisar` publica pero marca para revisión); huella del texto para frenar duplicados en 24 h; suspensión de insignia; notificaciones.
- `puede_interactuar()` = cuenta activa y sin silencio vigente; se usa en las políticas de INSERT de comentarios, me gusta, mensajes y publicaciones.
- Los bloqueos filtran feed, perfiles, comentarios y mensajes.
- RPC de admin: `perform public.exigir_mfa();` + chequeo de alcance + `update … where estado = 'pendiente'` + auditoría.

**Storage** (con `allowed_mime_types` y `file_size_limit` por bucket; validar el tipo real del archivo antes de subir):

| Bucket | Acceso | Reglas |
|---|---|---|
| `avatares`, `portadas` | lectura pública | escritura solo en `{uid}/`, con nombre de archivo aleatorio (URLs no adivinables); imágenes ≤ 5 MB |
| `media-pendiente` | privado | ruta `{dep}/{uid}/{publicacion_id}/…`; sube el dueño (el primer segmento debe ser su departamento o `nacional`); leen el dueño y `puede_moderar(primer segmento)`; imágenes ≤ 10 MB, video ≤ 50 MB |
| `media-publica` | lectura pública | escribe solo la Edge Function `publicar-media` (service role) |
| `media-miembros` | privado | leen los miembros activos (`es_miembro_activo()`) con URLs firmadas; escribe solo `publicar-media` |
| `mensajes` | privado | ruta `{conversacion_id}/…`; solo participantes; URLs firmadas |
| `ia-media` | lectura pública | escriben solo las Edge Functions de IA |
| `sitio` | lectura pública | escribe solo el admin nacional (CMS) |

```sql
create policy "leer media pendiente" on storage.objects for select to authenticated using (
  bucket_id = 'media-pendiente' and (
    (storage.foldername(name))[2] = (select auth.uid())::text
    or public.puede_moderar(nullif((storage.foldername(name))[1], 'nacional'))
  )
);
```

**Edge Functions**: validar el JWT con `auth.getUser()`, CORS limitado al dominio (responder `OPTIONS`), errores genéricos al cliente y detalle en los logs. `vista-previa-enlace`: solo http/https, bloquear localhost e IP privadas, máx. 3 redirecciones, 5 s de espera, 1 MB y caché en `vistas_previas_enlace`. `eliminar-cuenta`: borra el usuario con la API de administración tras reautenticación.

**Frontend**: CSP estricta en `_headers` o `vercel.json`, sin scripts inline: `script-src 'self' cdn.jsdelivr.net challenges.cloudflare.com`; `style-src 'self' fonts.googleapis.com cdn.jsdelivr.net`; `font-src fonts.gstatic.com`; `img-src 'self' data: blob:` más el dominio de Supabase y el servidor de teselas del mapa; `connect-src` y `media-src` con `'self'`, `https://[ref].supabase.co` y `wss://[ref].supabase.co`; `frame-src challenges.cloudflare.com www.youtube-nocookie.com`; `frame-ancestors 'none'`. Enlaces externos con `rel="noopener noreferrer"`. El mapa de eventos usa teselas de OpenStreetMap con su atribución (o un proveedor más sobrio como CARTO, revisando sus condiciones de uso).

**Auth**: confirmación de correo, Turnstile, contraseñas de 10 o más caracteres, protección de contraseñas filtradas (si el plan lo permite), MFA TOTP para moderadores y admins, y "cerrar sesión en todos los dispositivos".

**Seguridad de líderes (contexto colombiano)**: en Colombia los líderes sociales enfrentan amenazas reales. Por eso:
- Perfiles invisibles fuera de la red por defecto; el municipio se puede ocultar.
- Nada de "última conexión" ni ubicación en tiempo real.
- El mapa solo muestra agregados por departamento, con umbral mínimo.
- Eventos con opción "dirección solo para inscritos".
- Exportaciones restringidas, con MFA y auditadas.
- Reporte "amenaza o riesgo para la seguridad" con prioridad alta y aviso inmediato a los admins.

**Copias de seguridad**: diarias (plan Pro) y PITR si se contrata.

## 17. Datos personales y marco legal (Colombia)

> Esto orienta el desarrollo; no reemplaza la revisión de un abogado.

- **Ley 1581 de 2012 y Decreto 1377 de 2013** (hoy compilado en el Decreto 1074 de 2015): la pertenencia u orientación política es un **dato sensible**. Por eso:
  - Autorización previa, expresa e informada, **separada** de los términos, que indique la finalidad y que el titular no está obligado a autorizar el tratamiento de datos sensibles.
  - Prueba guardada en `consentimientos` (versión de la política, fecha, casillas marcadas, user agent).
  - Política de tratamiento publicada en `privacidad.html`: responsable, finalidades, derechos (conocer, actualizar, rectificar, suprimir y revocar), canal de atención y plazos (consultas: 10 días hábiles; reclamos: 15 días hábiles).
  - En Ajustes: "Descargar mis datos" (JSON) y "Eliminar mi cuenta" (borra el perfil y los mensajes propios; las publicaciones se borran o se anonimizan según `eliminacion_cuenta` en Configuración).
  - Solo mayores de 18 años: los datos de menores tienen protección reforzada.
  - Consultar con un abogado si la base debe inscribirse en el Registro Nacional de Bases de Datos de la SIC.
- Texto sugerido para la casilla de datos sensibles: *"Autorizo de manera previa, expresa e informada a [RESPONSABLE] para tratar mis datos personales, incluidos datos sensibles como mi afinidad política, con el fin de gestionar mi participación en Avancemos, conforme a la Política de Tratamiento de Datos. Sé que no estoy obligado(a) a autorizar el tratamiento de datos sensibles y que puedo revocar esta autorización en cualquier momento."*
- **Propaganda electoral**: antes de un periodo electoral, revisar con asesoría jurídica las reglas de la Ley 1475 de 2011 y los lineamientos del CNE. El "modo campaña" de Configuración activa un aviso en el editor y el motivo de rechazo correspondiente. Las próximas elecciones territoriales (alcaldías, gobernaciones, concejos y asambleas) son en octubre de 2027: activa el modo campaña, con asesoría jurídica, antes de que empiece ese periodo.
- **Financiación**: no incluir donaciones en línea sin asesoría legal; la financiación política está regulada.
- **Encuestas**: la plataforma no publica encuestas de intención de voto.
- **IA**: todo contenido sintético se etiqueta y nunca representa a personas reales.
- **Tono editorial**: propositivo; se debaten ideas y políticas con datos, no se ataca a personas ni a partidos.

## 18. Contenido semilla: el centro político (`el-centro.html`)

### ¿Qué es el centro político?
El centro es la posición que busca soluciones prácticas tomando lo que funciona de distintas tradiciones políticas, en lugar de aplicar una ideología cerrada. Sus rasgos más comunes:
- **Pragmatismo y evidencia**: las políticas se juzgan por sus resultados medibles.
- **Diálogo y acuerdos**: se prefiere construir mayorías amplias a imponer desde una trinchera.
- **Instituciones fuertes**: Constitución, separación de poderes y Estado de derecho.
- **Mercado con responsabilidad social**: emprendimiento y crecimiento, con políticas que reduzcan la desigualdad.
- **Reformas graduales y evaluables**, en vez de rupturas.
- **Integridad**: la lucha contra la corrupción como condición para todo lo demás.
- **Respeto por la diferencia**: se debaten ideas, no se ataca a personas.

### De dónde vienen "izquierda", "derecha" y "centro"
En la Asamblea Nacional de Francia de 1789, quienes defendían el poder del rey se sentaban a la derecha del presidente de la asamblea y quienes pedían cambios, a la izquierda. En la Convención de 1792, los diputados moderados que ocupaban el espacio intermedio recibieron el nombre de "la Llanura". De ahí viene la idea del centro como punto de equilibrio.

### Lo que el centro no es
- No es tibieza: toma posición en cada tema, según la evidencia.
- No es un promedio automático entre dos propuestas.
- No es apolítico: es una forma de hacer política basada en acuerdos y resultados.

### Corrientes cercanas al centro
- **Centroizquierda**: socialdemocracia y "Tercera Vía", sistematizada por el sociólogo Anthony Giddens en su libro de 1998.
- **Centro liberal**: libertades individuales, economía abierta e instituciones fuertes.
- **Centroderecha**: democracia cristiana y conservadurismo moderado.

El espectro izquierda–derecha es una simplificación: también importan otros ejes, como libertades individuales frente a autoridad.

### El centro en Colombia: algunos hitos
- **1991 — Constitución Política**: la Asamblea Nacional Constituyente tuvo tres copresidentes de fuerzas distintas: Horacio Serpa (Partido Liberal), Álvaro Gómez Hurtado (Movimiento de Salvación Nacional) y Antonio Navarro Wolff (Alianza Democrática M-19). La nueva Constitución nació de un acuerdo amplio.
- **2010 — "Ola Verde"**: Antanas Mockus llevó al Partido Verde a la segunda vuelta presidencial con una campaña basada en voluntarios y redes sociales.
- **2018 — Coalición Colombia**: Sergio Fajardo obtuvo cerca del 23,7 % en primera vuelta y quedó a poco más de un punto de pasar a segunda vuelta.
- **2018 — Consulta Anticorrupción**: cerca de 11,7 millones de votos, más de los que obtuvo el presidente electo ese año en segunda vuelta, aunque no alcanzó el umbral de participación exigido.
- **2022 — Coalición Centro Esperanza**: reunió a varias fuerzas de centro en una consulta interpartidista.

## 19. Contenido semilla: referentes (`referentes`)

**Reglas**
- Se siembran con `publicado = false`. El admin nacional revisa cada uno, agrega al menos una fuente (Wikipedia en español y una fuente oficial), verifica los datos y lo publica.
- Aviso fijo en la página: *"Estas personas se presentan como referentes de moderación, consenso y gobiernos de centro. No están afiliadas a Avancemos ni lo respaldan."*
- Sin imágenes IA de estas personas. Por defecto, tarjeta con monograma; si se sube una foto, debe tener licencia (p. ej., Wikimedia Commons) y crédito visible.
- Cada ficha puede llevar una línea de "Contexto" con críticas o debates relevantes, para que la página informe y no parezca propaganda.

### Colombia

**Antanas Mockus** — Alcalde de Bogotá (1995–1997 y 2001–2003) · Centro (independiente en sus alcaldías; luego Partido Verde)
- Creó la política de "cultura ciudadana": mimos en las calles para enseñar normas de tránsito, la "Ley Zanahoria" (cierre de bares a la 1 a. m.) y jornadas de desarme voluntario.
- Entre 1993 y 2003, periodo que incluye sus dos alcaldías y la de Enrique Peñalosa, la tasa de homicidios de Bogotá pasó de más de 80 por cada 100.000 habitantes a menos de un tercio de ese nivel. Los expertos atribuyen la caída al trabajo acumulado de varias administraciones.
- En 2002 invitó a pagar un 10 % adicional voluntario de impuestos ("110 % con Bogotá") y unos 63.000 contribuyentes lo hicieron.
- Lección: la pedagogía y la confianza pueden cambiar comportamientos tanto como las sanciones.

**Sergio Fajardo** — Alcalde de Medellín (2004–2007) y gobernador de Antioquia (2012–2015) · Centro (Compromiso Ciudadano)
- "Medellín, la más educada": parques biblioteca, colegios de calidad y urbanismo social en los barrios con menos oportunidades.
- "Antioquia, la más educada": parques educativos en municipios del departamento.
- 2018: tercer lugar en la elección presidencial, con cerca del 23,7 % de los votos.
- Lección: la educación como eje de la transformación de un territorio.

**Humberto de la Calle** — Ministro de Gobierno (1990–1993), vicepresidente (1994–1996) y jefe negociador del Gobierno en La Habana (2012–2016) · Centro liberal
- Participó, desde el Gobierno, en el proceso que dio origen a la Constitución de 1991.
- Encabezó el equipo negociador del Acuerdo de Paz con las FARC (2016).
- Lección: el diálogo paciente puede resolver conflictos de décadas.

**Juan Manuel Santos** — Presidente de Colombia (2010–2018) · Centro / centroderecha, promotor de la "Tercera Vía"
- Firmó el Acuerdo de Paz con las FARC (2016); tras la victoria del "No" en el plebiscito, el acuerdo se renegoció y fue refrendado por el Congreso.
- Premio Nobel de Paz 2016.
- Ley de Víctimas y Restitución de Tierras (Ley 1448 de 2011).
- Encaminó el ingreso de Colombia a la OCDE (invitación en 2018, adhesión formal en 2020).
- Contexto: el acuerdo y su implementación siguen generando debate político.
- Lección: los acuerdos difíciles necesitan negociación, pero también pedagogía y legitimidad ciudadana.

**Claudia López** — Senadora (2014–2018) y alcaldesa de Bogotá (2020–2023), primera mujer elegida por voto popular para ese cargo · Centroizquierda (Alianza Verde)
- Impulsó la Consulta Anticorrupción de 2018 (cerca de 11,7 millones de votos).
- Creó el Sistema Distrital de Cuidado y las "Manzanas del Cuidado" para apoyar a las mujeres cuidadoras.
- Lección: convertir una causa ciudadana en una institución concreta.

**Alejandro Gaviria** — Ministro de Salud (2012–2018), rector de la Universidad de los Andes (2019–2021) y ministro de Educación (2022–2023) · Centro
- Durante su gestión se aprobó la Ley Estatutaria de Salud (Ley 1751 de 2015), que reconoce la salud como derecho fundamental.
- Impulsó el control de precios de medicamentos, incluida la declaratoria de interés público del imatinib (2016).
- Lección: decisiones técnicas basadas en evidencia, aun frente a intereses poderosos.

### Mundo

**Emmanuel Macron** (Francia) — Presidente, elegido en 2017 y reelegido en 2022 · Centro liberal
- Fundó en 2016 el movimiento ciudadano "En Marche!", que no se definía ni de izquierda ni de derecha, y ganó la presidencia al año siguiente.
- Antes de escribir su programa, sus voluntarios recorrieron el país puerta a puerta ("la Gran Marcha") para escuchar a los ciudadanos.
- Redujo a la mitad el tamaño de los cursos de los primeros grados de primaria en zonas vulnerables.
- Contexto: su reforma pensional de 2023 generó amplias protestas.
- Lección para Avancemos: un movimiento nuevo puede crecer rápido si se organiza con voluntarios y escucha en el territorio.

**Tony Blair** (Reino Unido) — Primer ministro (1997–2007) · Centroizquierda ("Tercera Vía", Nuevo Laborismo)
- Acuerdo de Viernes Santo (1998), clave para terminar décadas de violencia en Irlanda del Norte.
- Su gobierno creó el salario mínimo nacional (1998).
- Su gobierno dio al Banco de Inglaterra independencia para fijar las tasas de interés (1997).
- Contexto: su apoyo a la guerra de Irak (2003) es muy criticado.
- Lección: reformas sociales y responsabilidad económica pueden ir juntas.

**Angela Merkel** (Alemania) — Canciller (2005–2021) · Centroderecha moderada (CDU)
- Gobernó 16 años, la mayor parte en "gran coalición" con los socialdemócratas.
- En la crisis de 2008–2009 amplió el programa de reducción de jornada (Kurzarbeit) para evitar despidos masivos.
- Con su gobierno entró en vigor el salario mínimo nacional (2015).
- Contexto: su política de acogida de refugiados de 2015 dividió a la opinión pública.
- Lección: estabilidad y acuerdos entre adversarios.

**Fernando Henrique Cardoso** (Brasil) — Ministro de Hacienda (1993–1994) y presidente (1995–2002) · Centro socialdemócrata (PSDB)
- Lideró el Plan Real (1994), que acabó con la hiperinflación.
- Ley de Responsabilidad Fiscal (2000).
- Bolsa Escola federal (2001), antecedente del programa de transferencias condicionadas Bolsa Família.
- Lección: la estabilidad económica es la base de la política social.

**Patricio Aylwin** (Chile) — Presidente (1990–1994) · Centro (Democracia Cristiana)
- Encabezó la transición a la democracia con una coalición amplia, la Concertación.
- Creó la Comisión Nacional de Verdad y Reconciliación (Informe Rettig, 1991).
- Durante su gobierno la economía creció y la pobreza bajó de forma significativa.
- Lección: reconciliación y resultados económicos pueden avanzar juntos.

**Mario Draghi** (Italia / Unión Europea) — Presidente del Banco Central Europeo (2011–2019) y primer ministro de Italia (2021–2022) · Independiente
- Su compromiso de hacer "lo que sea necesario" para preservar el euro (2012) se considera clave para contener la crisis de la eurozona.
- Encabezó un gobierno de unidad nacional con partidos de izquierda y de derecha, y presentó el plan de recuperación financiado por la Unión Europea.
- Lección: la competencia técnica y la unidad pueden estar por encima de la polarización.

## 20. Contenido semilla: Avancemos (sugerencias editables)

**Lema** (elegir o reemplazar): "Ni extremos ni excusas: soluciones." · "Colombia avanza cuando nos escuchamos." · "Del acuerdo a la acción."

**Misión** [SUGERENCIA]: Organizar a ciudadanos de todas las regiones para construir y ejecutar soluciones prácticas, basadas en evidencia y en acuerdos, que mejoren la vida de los colombianos.

**Visión** [SUGERENCIA]: Una Colombia que resuelve sus problemas con diálogo, instituciones confiables y resultados medibles.

**Valores**: Pragmatismo (lo que funciona, con evidencia) · Diálogo (acuerdos por encima de trincheras) · Integridad (cero tolerancia a la corrupción) · Respeto (a la diferencia y a las instituciones) · Territorio (soluciones pensadas desde las regiones).

**Ejes** [SUGERENCIA; `publicada = false` hasta que el cliente los apruebe]:
1. Educación de calidad desde la primera infancia.
2. Seguridad ciudadana con Estado de derecho.
3. Empleo, emprendimiento y formalización.
4. Transparencia y lucha contra la corrupción.
5. Salud cercana y sostenible.
6. Campo, agua y transición energética.
7. Paz, convivencia y reconciliación.
8. Territorios conectados: movilidad, vivienda y conectividad digital.

**Preguntas frecuentes**: ¿Qué es Avancemos? · ¿Es un partido? [COMPLETAR] · ¿Cuesta algo unirse? (no) · ¿Quién aprueba mi solicitud? · ¿Mis datos son públicos? (no, por defecto) · ¿Qué significan las insignias? · ¿Cómo creo el grupo de WhatsApp de mi municipio? · ¿Cómo reporto un contenido?

**Normas de la comunidad** (`normas.html`):
1. Debate ideas; no ataques a personas.
2. Cero discursos de odio, discriminación, amenazas o incitación a la violencia.
3. Cita fuentes; no difundas información falsa o engañosa.
4. No publiques datos personales de terceros.
5. No suplantes a personas ni instituciones.
6. Nada de spam, cadenas ni publicidad comercial.
7. Respeta las decisiones de moderación; puedes apelar una vez.

Escala de sanciones: advertencia → silencio 24 h → silencio 7 días → suspensión 30 días → baneo. Las faltas graves (amenazas, violencia, datos personales, suplantación) implican suspensión inmediata y revisión nacional.

## 21. Rendimiento, SEO y PWA

- Lighthouse móvil ≥ 90 en rendimiento, accesibilidad, buenas prácticas y SEO para las páginas públicas; LCP < 2,5 s en 4G; todo usable a 360 px de ancho.
- Imágenes responsive (`srcset`), WebP y carga diferida. Consultas con columnas explícitas (nunca `select *`), índices, paginación por cursor y contadores desnormalizados.
- SEO: título y descripción por página, Open Graph y Twitter (`og-default.jpg` de 1200×630), `sitemap.xml`, `robots.txt` que excluye `app.html` y `admin.html`, y JSON-LD `Organization` y `Event`.
- PWA: `manifest.webmanifest` (íconos 192, 512 y maskable; `theme_color` azul noche) y service worker con caché del app shell y página sin conexión; instalable en Android.
- Opcional: una función del hosting (Netlify o Cloudflare) que sirva meta etiquetas OG por publicación, para que los enlaces compartidos en WhatsApp muestren vista previa.

## 22. Fases de entrega

1. **Fundaciones**: migraciones (extensiones, tipos, tablas, funciones, RLS, triggers, storage, cron y semillas de departamentos, capitales, localidades y contenido de las secciones 18–20), importador DIVIPOLA, `config.js`, cliente Supabase, sistema de diseño y `estilo.html`.
2. **Sitio público** completo, leyendo del CMS, con el mapa.
3. **Cuentas**: registro, ingreso, recuperación, pantalla "En revisión", perfil y ajustes. Panel: acceso con MFA, resumen, aprobación de usuarios, equipo y roles, y auditoría.
4. **Red social**: publicar con media, aprobación, feed, publicación individual, comentarios, me gusta, compartir, guardar, seguir, perfiles, búsqueda y tendencias.
5. **Mensajes**, notificaciones en tiempo real, reportes, sanciones y apelaciones.
6. **Grupos de WhatsApp**, eventos y páginas de departamento y municipio.
7. **Verificación**, cuentas oficiales (`cuentas_oficiales.js`), configuración global, publicaciones oficiales, anuncios y exportaciones.
8. **Vertex AI**: Estudio IA (imagen, video y edición), biblioteca de medios, moderación asistida, texto alternativo y revisión previa.
9. **Cierre**: PWA, SEO, rendimiento, pruebas de la sección 23, `README.md` de despliegue y `datos_prueba.js` (usuarios ficticios de dos departamentos creados con `auth.admin.createUser`; nunca en producción).

## 23. Criterios de aceptación

Incluye `supabase/tests/rls_pruebas.sql`, que simule usuarios dentro de una transacción (`begin; set local role authenticated; select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated","aal":"aal2"}', true); … rollback;`) y compruebe:

1. Un usuario no puede darse rol, insignia ni estado, ni cambiar de departamento, por la API (`update perfiles set insignia = 'dorada'` falla).
2. Una publicación enviada con `estado = 'aprobado'` desde el cliente queda `pendiente`.
3. Una publicación pendiente y su media solo las ven el autor y los moderadores de su territorio; la URL directa del bucket privado falla para los demás.
4. El admin de Antioquia no ve ni aprueba pendientes, usuarios ni reportes del Valle, ni contenido nacional.
5. Un moderador no puede aprobar usuarios ni nombrar admins; un admin departamental no puede nombrar admins departamentales ni otorgar insignias dorada o gris.
6. Cualquier acción de admin con sesión `aal1` falla en el servidor.
7. No se puede quitar el último admin nacional.
8. Nadie fuera de una conversación, ni siquiera un admin, puede leer sus mensajes.
9. Comentarios y me gusta funcionan sin aprobación; las palabras bloqueadas se rechazan y los límites por hora se aplican.
10. Los enlaces de WhatsApp inválidos se rechazan en el servidor; los aprobados solo los ven miembros activos.
11. Cambiar el nombre o la foto de un verificado suspende su insignia.
12. Toda aprobación, rechazo, sanción y cambio de rol queda en `auditoria`, que no se puede editar ni borrar.
13. Las funciones de IA rechazan a usuarios sin rol, sin MFA o sin cuota; los prompts con personas reales se bloquean; todo archivo IA queda etiquetado.
14. El mapa público nunca muestra conteos por debajo del umbral.
15. Publicar `<img src=x onerror=alert(1)>` se muestra como texto.
16. La media de una publicación "solo miembros" no se puede abrir sin sesión ni con una cuenta pendiente.
17. Al reportar un mensaje, el reporte guarda solo ese mensaje, nunca el resto de la conversación.
18. Un simpatizante no puede crear publicaciones mientras `roles_pueden_publicar` no lo incluya.
19. Lighthouse móvil ≥ 90 en las páginas públicas.

## 24. Despliegue (el `README.md` debe incluirlo)

1. **Supabase**: crear el proyecto en São Paulo y luego:
   ```bash
   npx supabase login
   npx supabase link --project-ref [PROJECT_REF]
   npx supabase db push
   ```
   Importar `municipios_divipola.csv`.
2. **Auth**: Site URL y Redirect URLs del dominio; SMTP propio; CAPTCHA con Turnstile; confirmación de correo; MFA TOTP; protección de contraseñas filtradas.
3. **Primer Administrador Colombia**: registrarse normalmente y luego, en el SQL Editor:
   ```sql
   update public.perfiles set estado = 'activo' where id = '[UUID]';
   update public.solicitudes set estado = 'aprobado', revisado_en = now() where user_id = '[UUID]';
   insert into public.user_roles (user_id, rol) values ('[UUID]', 'admin_nacional');
   ```
   Luego crea las cuentas oficiales desde tu máquina (la secret key nunca sale de ella): `node supabase/seed/cuentas_oficiales.js`.
4. **Google Cloud**:
   ```bash
   gcloud config set project [GCP_PROJECT_ID]
   gcloud services enable aiplatform.googleapis.com
   gcloud iam service-accounts create avancemos-vertex --display-name="Avancemos Vertex"
   gcloud projects add-iam-policy-binding [GCP_PROJECT_ID] \
     --member="serviceAccount:avancemos-vertex@[GCP_PROJECT_ID].iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"
   gcloud iam service-accounts keys create key.json \
     --iam-account=avancemos-vertex@[GCP_PROJECT_ID].iam.gserviceaccount.com
   echo "GCP_SA_KEY_B64=$(base64 -w0 key.json)" >> supabase/.env && shred -u key.json
   ```
   Si la organización de Google Cloud bloquea la creación de llaves (política `iam.disableServiceAccountKeyCreation`), habilítala solo para este proyecto. Crear una alerta de presupuesto mensual. `supabase/.env` va en `.gitignore`.
5. **Secretos y funciones**:
   ```bash
   npx supabase secrets set --env-file supabase/.env
   npx supabase functions deploy
   ```
   Crear los Database Webhooks (`moderar-ia`, `publicar-media`) y el job de `pg_cron` de `ia-video`.
6. **Frontend**: completar `js/config.js`, desplegar en Netlify, Vercel o Cloudflare Pages, y configurar las cabeceras de seguridad y el dominio con HTTPS.
7. **Prueba final**: recorrer la sección 23 con usuarios de prueba de dos departamentos.

## 25. Extensiones opcionales (después del MVP)

- **Propuestas ciudadanas**: los miembros proponen (con aprobación) y otros las apoyan; sirven como insumo para el programa.
- **Misiones de voluntariado**: tareas creadas por líderes, marcadas como hechas y con ranking por municipio.
- **Encuestas internas** no electorales dentro de publicaciones.
- **Web Push** y boletín por correo.
- **Inicio de sesión con Google**, con un paso posterior para completar el perfil y firmar los consentimientos antes de crear la solicitud.
- **App Android nativa** (Flutter o Capacitor) sobre el mismo backend.
