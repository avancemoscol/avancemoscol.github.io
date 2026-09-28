import { chromium, devices } from 'playwright-core';
const BASE='http://localhost:3000/';
const ts=Date.now().toString().slice(-6);
const U={n:'Movil Prueba '+ts,u:'e2e_movil_'+ts,e:`e2e.movil.${ts}@avancemos.co`},V={n:'Vecina Prueba '+ts,u:'e2e_vecina_'+ts,e:`e2e.vecina.${ts}@avancemos.co`};
const PASS='PruebaSegura#2026';
const b=await chromium.launch({executablePath:process.env.CHROMIUM || '/snap/bin/chromium',args:['--no-sandbox']});
const log=(...a)=>console.log(...a);
const OK=(c,m)=>log((c?'✅':'❌')+' '+m);
async function ctx(name,mobile=true){const c=await b.newContext(mobile?{...devices['Pixel 7']}:{viewport:{width:1366,height:850}});const p=await c.newPage();
 p.on('pageerror',e=>log(`  [${name}] PAGEERROR`,e.message.slice(0,200)));
 p.on('console',m=>{if(m.type()==='error'&&!/fonts|ERR_NAME|Failed to load resource/.test(m.text()))log(`  [${name}] console:`,m.text().slice(0,200))});
 p.on('response',r=>{if(r.status()>=400&&!/fonts/.test(r.url()))log(`  [${name}] HTTP ${r.status()}`,r.url().slice(0,130))});
 p.on('dialog',d=>{log(`  [${name}] dialog:`,d.message().slice(0,100));d.accept()});return p;}
const toast=async p=>{await p.waitForTimeout(1500);return (await p.locator('.toast').allTextContents()).join(' | ')};
const txt=async (p,sel)=>(await p.locator(sel).first().innerText()).replace(/\s+/g,' ').trim();
async function registrar(p,x,depIdx){
 await p.goto(BASE+'unete.html');
 await p.fill('#nombre',x.n);await p.fill('#username',x.u);await p.fill('#email',x.e);await p.fill('#password',PASS);
 await p.waitForFunction(()=>document.querySelectorAll('#departamento option').length>1,null,{timeout:20000});
 await p.selectOption('#departamento',{index:depIdx});
 await p.waitForFunction(()=>document.querySelectorAll('#municipio option').length>1,null,{timeout:20000});
 await p.selectOption('#municipio',{index:1});
 await p.fill('#motivo','Quiero aportar a mi región con propuestas sensatas.');
 for(const c of ['#check-mayor','#check-terminos','#check-datos-sensibles']) await p.check(c);
 await p.click('#btn-enviar');
 OK(await p.waitForSelector('#revision-box',{state:'visible',timeout:20000}).then(()=>true).catch(()=>false),'registro '+x.u);
}
async function login(p,email,pass){
 await p.goto(BASE+'ingresar.html');await p.fill('#email',email);await p.fill('#password',pass);await p.click('#btn-login');
 OK(await p.waitForURL(u=>!u.href.includes('ingresar'),{timeout:40000}).then(()=>true).catch(()=>false),'login '+email);
}
async function cerrarAnuncio(p){await p.waitForTimeout(1500);const b=p.locator('#btn-cerrar-anuncio');if(await b.count()){await b.click({timeout:8000}).catch(async e=>{console.log('  ❌ no se pudo pulsar Entendido: '+e.message.split('\n')[0]);await p.screenshot({path:'m2-anuncio-err.png'});await p.evaluate(()=>document.querySelectorAll('.modal-overlay').forEach(m=>m.remove()));});}await p.waitForTimeout(400);}
const M=await ctx('movil'),Vc=await ctx('vecina'),ADM=await ctx('admin',false);
await registrar(M,U,1);await registrar(Vc,V,1);
await login(ADM,'admin@avancemos.co',process.env.ADMP);
await ADM.goto(BASE+'admin.html');await ADM.waitForTimeout(2500);await ADM.click("a[href='#aprobaciones']");await ADM.waitForTimeout(2500);
for(const x of [U,V]){const card=ADM.locator('.aprobacion-tarjeta',{hasText:x.u});if(await card.count()){await card.getByText('Aprobar Usuario').click();await ADM.waitForTimeout(1500);OK(true,'admin aprueba '+x.u);}else OK(false,'solicitud visible '+x.u);}
await login(M,U.e,PASS);await login(Vc,V.e,PASS);
await M.goto(BASE+'app.html#/inicio');await cerrarAnuncio(M);
OK(await M.evaluate(()=>document.documentElement.scrollWidth)<=412,'app sin desborde horizontal ('+await M.evaluate(()=>document.documentElement.scrollWidth)+'px)');
// menú lateral
await M.click('#btn-menu-movil');await M.waitForTimeout(500);
OK(await M.locator('#app-nav-lateral').evaluate(e=>e.getBoundingClientRect().left>=0),'menú lateral se abre');
await M.screenshot({path:'m2-menu.png'});
await M.click('#app-nav-lateral >> text=Eventos');await M.waitForTimeout(1500);
OK(M.url().includes('#/eventos')&&!(await M.evaluate(()=>document.body.classList.contains('menu-movil-abierto'))),'navegar desde el menú a Eventos y se cierra');
// ➕ desde otra vista
await M.click('.barra-movil-publicar');await M.waitForTimeout(1200);
OK(M.url().includes('#/inicio')&&await M.locator('#redactor-texto').evaluate(e=>document.activeElement===e),'botón ➕ lleva al redactor y lo enfoca');
const texto='Propuesta móvil E2E '+ts+': ciclorrutas seguras en mi municipio.';
await M.fill('#redactor-texto',texto);
await M.setInputFiles('#redactor-input-archivo',{name:'foto.webp',mimeType:'image/webp',buffer:(await import('fs')).readFileSync(new URL('../assets/video/video-poster.webp', import.meta.url))});await M.waitForTimeout(2500);
OK(await M.locator('#redactor-preview-media .redactor-adjunto img').count()===1,'vista previa de imagen');
await M.click('#btn-enviar-post');
const t1=await toast(M);OK(/enviada|revisión/i.test(t1),'publicar con imagen: '+t1);
// admin aprueba
await ADM.goto(BASE+'admin.html');await ADM.waitForTimeout(2500);await ADM.click("a[href='#aprobaciones']");await ADM.waitForTimeout(1500);
await ADM.click("#aprobaciones-pestanas >> text=Publicaciones");await ADM.waitForTimeout(2500);
const pc=ADM.locator('.aprobacion-tarjeta',{hasText:ts});
if(await pc.count()){await pc.getByText('Aprobar Publicación').click();await ADM.waitForTimeout(1500);OK(true,'admin aprueba publicación');}else OK(false,'publicación en moderación');
// vecina ve post con imagen
await Vc.goto(BASE+'app.html');await cerrarAnuncio(Vc);await Vc.reload();await cerrarAnuncio(Vc);await Vc.waitForTimeout(2500);
const post=Vc.locator('.tarjeta-pub',{hasText:texto}).first();
OK(await post.count()===1,'vecina ve la publicación en el feed');
if(await post.count()){
 await post.scrollIntoViewIfNeeded();await Vc.waitForTimeout(2500);
 const imgOk=await post.locator('img.pub-media-item').evaluate(i=>i.complete&&i.naturalWidth>0).catch(()=>false);
 OK(imgOk,'la imagen aprobada se ve');
 await post.locator('.pub-ver-comentarios').click();await Vc.waitForTimeout(2000);
 OK(await Vc.locator('.modal-hoja .hilo-comentarios').count()===1,'se abre el hilo de comentarios');
 await Vc.fill('.comentario-input','Excelente idea, apoyo desde mi barrio '+ts);await Vc.click('.comentario-form button');await Vc.waitForTimeout(2000);
 OK((await txt(Vc,'.comentarios-lista')).includes('apoyo desde mi barrio '+ts),'comentario aparece en la lista');
 await Vc.screenshot({path:'m2-comentarios.png'});
 await Vc.click('.modal-hoja .modal-cabecera button');await Vc.waitForTimeout(500);
}
// autor ve los comentarios
await M.goto(BASE+'app.html');await M.reload();await cerrarAnuncio(M);await M.waitForTimeout(2500);
const mp=M.locator('.tarjeta-pub',{hasText:texto}).first();
if(await mp.count()){ OK(/1 comentario/.test(await mp.innerText()),'autor ve "Ver 1 comentario"');
 await mp.locator('.pub-ver-comentarios').click();await M.waitForTimeout(2000);
 OK((await txt(M,'.comentarios-lista')).includes('apoyo desde mi barrio '+ts),'autor puede leer el comentario');
 await M.keyboard.press('Escape');}
// badge notificaciones
await M.waitForTimeout(1000);
OK(await M.locator('#badge-notificaciones-movil').isVisible(),'contador de notificaciones visible en barra móvil');
// detalle público
await M.goto(BASE+'app.html#/inicio');
// widget IA
await M.goto(BASE+'index.html');await M.waitForTimeout(1500);
await M.click('.widget-soporte-boton');await M.waitForTimeout(600);
OK(await M.locator('#widget-soporte-panel').isVisible(),'widget de soporte abre en celular');
await M.fill('#widget-soporte-panel input','¿Qué significa ser de centro?');await M.click('#widget-soporte-panel >> text=Enviar');
await M.waitForFunction(()=>!document.querySelector('.widget-soporte-cuerpo').innerText.includes('Consultando'),null,{timeout:40000}).catch(()=>{});
const resp=await txt(M,'.widget-soporte-cuerpo');OK(resp.length>200,'IA responde: '+resp.slice(-160));
await M.screenshot({path:'m2-widget.png'});
// menú público
await M.goto(BASE+'referentes.html');await M.waitForTimeout(2500);
await M.click('.menu-hamburguesa');await M.waitForTimeout(500);
OK(await M.locator('#sitio-menu').evaluate(e=>e.getBoundingClientRect().top>=0),'menú ☰ en referentes');
await M.click('.menu-hamburguesa');await M.waitForTimeout(400);
const retratos=await M.locator('.referente-retrato img').evaluateAll(a=>a.filter(i=>i.complete&&i.naturalWidth>0).length);
OK(retratos===8,'retratos de referentes cargados: '+retratos);
await M.screenshot({path:'m2-referentes.png',fullPage:false});
// video
await M.goto(BASE+'index.html');await M.locator('#seccion-video').scrollIntoViewIfNeeded();await M.waitForTimeout(1500);
const vid=await M.evaluate(()=>{const v=document.getElementById('video-institucional');return {rs:v.readyState,dur:v.duration,sinVideo:document.getElementById('video-marco').classList.contains('sin-video')}});
OK(vid.dur>39&&!vid.sinVideo,'video carga ('+JSON.stringify(vid)+')');
await M.locator('#seccion-video').screenshot({path:'m2-video.png'});
await M.locator('#mapa-colombia').scrollIntoViewIfNeeded();await M.waitForTimeout(2500);
const tiles=await M.evaluate(()=>[...document.querySelectorAll('.leaflet-tile')].map(t=>t.src));
OK(tiles.length>0&&tiles.every(s=>s.includes('key=')),'mapa con llave CARTO ('+tiles.length+' teselas)');
await M.locator('#mapa-colombia').screenshot({path:'m2-mapa.png'});
log(JSON.stringify([U,V]));
await b.close();
