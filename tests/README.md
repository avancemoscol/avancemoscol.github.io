# Pruebas de extremo a extremo (Playwright)

Pruebas contra el proyecto Supabase real. Crean cuentas `e2e.*@avancemos.co` que
deben borrarse al terminar (ver "Limpieza").

```bash
python3 -m http.server 3000 &            # desde la raíz del proyecto
cd tests && npm i playwright-core
export ADMP='<contraseña del admin nacional>'
export CHROMIUM=/snap/bin/chromium       # o la ruta de tu Chrome/Chromium

node e2e.mjs        # escritorio: registro, aprobación, publicar, seguir, DM, me gusta, comentarios
node movil.mjs      # celular (Pixel 7): menú lateral, ➕, foto, comentarios, soporte IA, mapa, video
node admin.mjs      # panel admin en escritorio y celular (GENERAR=1 prueba el Estudio IA)
node barrido.mjs $(cd .. && ls *.html)   # errores de consola y desborde horizontal a 360 px
```

## Limpieza

```sql
delete from public.casos_soporte where correo_contacto like 'e2e.%@avancemos.co';
delete from auth.users where email like 'e2e.%@avancemos.co';
```
