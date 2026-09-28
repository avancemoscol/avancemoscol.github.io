// Prueba E2E: registro de 2 usuarios, aprobación por admin, publicar, seguir, DM, me gusta y comentarios.
// Uso: python3 -m http.server 3000 & ; cd tests && npm i playwright-core && ADMP='<clave admin>' node e2e.mjs
import { chromium } from 'playwright-core';
const BASE='http://localhost:3000/';
const ts=Date.now().toString().slice(-6);
const users=[{n:'Prueba Ana '+ts,u:'e2e_ana_'+ts,e:`e2e.ana.${ts}@avancemos.co`},{n:'Prueba Beto '+ts,u:'e2e_beto_'+ts,e:`e2e.beto.${ts}@avancemos.co`}];
const PASS='PruebaSegura#2026';
const b=await chromium.launch({executablePath:process.env.CHROMIUM || '/snap/bin/chromium',args:['--no-sandbox']});
const log=(...a)=>console.log(...a);
async function ctx(name){const c=await b.newContext();const p=await c.newPage();
 p.on('pageerror',e=>log(`  [${name}] PAGEERROR`,e.message.slice(0,200)));
 p.on('console',m=>{if(m.type()==='error'&&!m.text().includes('fonts'))log(`  [${name}] console:`,m.text().slice(0,200))});
 p.on('requestfailed',r=>{if(!r.url().includes('fonts'))log(`  [${name}] REQFAIL`,r.failure()?.errorText==='net::ERR_ABORTED'?'':r.url().slice(0,100),r.failure()?.errorText)});
 p.on('dialog',d=>{log(`  [${name}] dialog:`,d.message().slice(0,120)); d.accept(d.type()==='prompt'?'ok':undefined)});
 return p;}
async function toast(p){await p.waitForTimeout(1500);return (await p.locator('.toast').allTextContents()).join(' | ');}
async function registrar(p,x){
 await p.goto(BASE+'unete.html');
 await p.fill('#nombre',x.n);await p.fill('#username',x.u);await p.fill('#email',x.e);await p.fill('#password',PASS);
 await p.waitForFunction(()=>document.querySelectorAll('#departamento option').length>1,null,{timeout:15000});
 await p.selectOption('#departamento',{index:1});
 await p.waitForFunction(()=>document.querySelectorAll('#municipio option').length>1,null,{timeout:15000});
 await p.selectOption('#municipio',{index:1});
 await p.selectOption('#rol',{index:0}).catch(()=>{});
 await p.fill('#motivo','Quiero aportar a mi región con propuestas sensatas.');
 for(const c of ['#check-mayor','#check-terminos','#check-datos-sensibles']) await p.check(c);
 await p.click('#btn-enviar');
 await p.waitForSelector('#revision-box',{state:'visible',timeout:15000}).then(()=>log('OK registro',x.u)).catch(async()=>log('FALLO registro',x.u,await toast(p)));
}
async function login(p,email,pass){
 await p.goto(BASE+'ingresar.html');await p.fill('#email',email);await p.fill('#password',pass);await p.click('#btn-login');
 await p.waitForURL(u=>!u.href.includes('ingresar'),{timeout:40000}).then(()=>log('OK login',email,'->',p.url())).catch(async()=>log('FALLO login',email,await toast(p)));
}
const A=await ctx('ana'),B=await ctx('beto'),ADM=await ctx('admin');
await registrar(A,users[0]);await registrar(B,users[1]);
await login(ADM,'admin@avancemos.co',process.env.ADMP);
await ADM.goto(BASE+'admin.html');await ADM.waitForTimeout(3000);
log('admin label:',await ADM.textContent('#admin-usuario-label'));
await ADM.click("a[href='#aprobaciones']");await ADM.waitForTimeout(3000);
for(const x of users){const card=ADM.locator('.aprobacion-tarjeta',{hasText:x.u});
 if(await card.count()){await card.getByText('Aprobar Usuario').click();log('aprobar',x.u,await toast(ADM));}else log('FALLO: no aparece solicitud de',x.u);}
await login(A,users[0].e,PASS);await login(B,users[1].e,PASS);
// Ana publica
await A.goto(BASE+'app.html#/inicio');await A.waitForTimeout(3000);
if(await A.locator('#btn-cerrar-anuncio').count()) await A.click('#btn-cerrar-anuncio');
const texto='Publicación de prueba E2E '+ts+' sobre movilidad en mi municipio.';
if(await A.locator('#redactor-texto').isVisible()){await A.fill('#redactor-texto',texto);await A.click('#btn-enviar-post');log('publicar:',await toast(A));}else log('FALLO: redactor no visible para Ana');
// admin aprueba post si pendiente
await ADM.goto(BASE+'admin.html');await ADM.waitForTimeout(2500);await ADM.click("a[href='#aprobaciones']");await ADM.waitForTimeout(1500);
await ADM.click("#aprobaciones-pestanas >> text=Publicaciones");await ADM.waitForTimeout(2500);
const pc=ADM.locator('.aprobacion-tarjeta',{hasText:ts});
if(await pc.count()){await pc.getByRole('button',{name:'Aprobar'}).click();log('aprobar post:',await toast(ADM));}else log('post no requiere/aparece en moderación');
// Beto ve feed
await B.goto(BASE+'app.html#/inicio');await B.waitForTimeout(4000);if(await B.locator('#btn-cerrar-anuncio').count()) await B.click('#btn-cerrar-anuncio');
const post=B.locator('.tarjeta-pub',{hasText:texto}).first();
log('Beto ve post:',await post.count());log('feed beto:',(await B.textContent('#vista-contenido')).replace(/\s+/g,' ').slice(0,200));
if(await post.count()){ log('botones post:',(await post.locator('button').allTextContents()).map(s=>s.trim()).join(' / '));}
// perfil de Ana
await B.goto(BASE+'app.html#/u/'+users[0].u);await B.waitForTimeout(3000);
log('perfil:',(await B.textContent('#vista-contenido')).replace(/\s+/g,' ').slice(0,160));
if(await B.locator('#btn-seguir-perfil').count()){await B.click('#btn-seguir-perfil');log('seguir:',await toast(B));}
// Ana sigue a Beto para permitir DM
await A.goto(BASE+'app.html#/u/'+users[1].u);await A.waitForTimeout(3000);if(await A.locator('#btn-cerrar-anuncio').count()) await A.click('#btn-cerrar-anuncio');
await A.click('#btn-seguir-perfil');log('ana sigue:',await toast(A));
await B.goto(BASE+'app.html#/u/'+users[0].u);await B.waitForTimeout(3000);
if(await B.locator('#btn-mensaje-perfil').count()){await B.click('#btn-mensaje-perfil');await B.waitForTimeout(3000);log('url chat:',B.url());log('chat:',(await B.textContent('#vista-contenido')).replace(/\s+/g,' ').slice(0,200));
 if(await B.locator('#input-chat').count()){await B.fill('#input-chat','Hola Ana, mensaje E2E');await B.click('#btn-chat-enviar');await B.waitForTimeout(2500);log('mensajes:',(await B.textContent('#mensajes-lista')).replace(/\s+/g,' ').slice(0,150));}}
// comentar y me gusta
await B.goto(BASE+'app.html#/inicio');await B.waitForTimeout(4000);
const p2=B.locator('.tarjeta-pub',{hasText:texto}).first();
if(await p2.count()){await p2.getByText('❤️').first().click();await B.waitForTimeout(1500);log('tras like:',(await p2.innerText()).replace(/\s+/g,' ').slice(-80));
 await p2.getByText('💬').first().click();await B.waitForTimeout(2000);
 await B.fill('.comentario-input','Comentario E2E escritorio');await B.click('.comentario-form button');await B.waitForTimeout(2000);
 log('hilo comentarios:',(await B.locator('.comentarios-lista').innerText().catch(()=>'-')).replace(/\s+/g,' ').slice(0,150));}

for(const v of ['explorar','notificaciones','mensajes','grupos','eventos','ajustes','guardados']){await A.goto(BASE+'app.html#/'+v);await A.waitForTimeout(2000);log('Ana vista',v,':',(await A.textContent('#vista-contenido')).replace(/\s+/g,' ').slice(0,110));}
await A.screenshot({path:'ana.png'});await B.screenshot({path:'beto.png',fullPage:false});
console.log(JSON.stringify(users));
await b.close();
