import { chromium, devices } from 'playwright-core';
const BASE='http://localhost:3000/';
const ts=Date.now().toString().slice(-6);
const A={n:'Ana María Pérez',u:'e2e_ana_'+ts,e:`e2e.ana.${ts}@avancemos.co`},B={n:'Beto Carlos Ruiz',u:'e2e_beto_'+ts,e:`e2e.beto.${ts}@avancemos.co`};
const PASS='PruebaSegura#2026';
const b=await chromium.launch({executablePath:process.env.CHROMIUM||'/snap/bin/chromium',args:['--no-sandbox','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream']});
const log=(...a)=>console.log(...a); let fallos=0;
const OK=(c,m)=>{if(!c)fallos++;log((c?'✅':'❌')+' '+m)};
async function ctx(name,mobile=true){const c=await b.newContext(mobile?{...devices['Pixel 7']}:{viewport:{width:1366,height:900}});const p=await c.newPage();
 p.on('pageerror',e=>log(`  [${name}] PAGEERROR`,e.message.slice(0,200)));
 p.on('console',m=>{if(m.type()==='error'&&!/fonts|ERR_NAME|Failed to load resource/.test(m.text()))log(`  [${name}] console:`,m.text().slice(0,200))});
 p.on('response',r=>{if(r.status()>=400&&!/fonts|soporte-ia/.test(r.url()))log(`  [${name}] HTTP ${r.status()}`,r.url().slice(0,120))});
 p.on('dialog',d=>{d.accept(d.type()==='prompt'?'Motivo de prueba':undefined)});return p;}
const esperar=ms=>new Promise(r=>setTimeout(r,ms));
const txt=async (p,sel)=>(await p.locator(sel).first().innerText().catch(()=>'')).replace(/\s+/g,' ').trim();
async function registrar(p,x){
 await p.goto(BASE+'unete.html');
 await p.fill('#nombre',x.n);await p.fill('#username',x.u);await p.fill('#email',x.e);await p.fill('#password',PASS);
 await p.waitForFunction(()=>document.querySelectorAll('#departamento option').length>1,null,{timeout:20000});
 await p.selectOption('#departamento','11');
 await p.waitForFunction(()=>document.querySelectorAll('#municipio option').length>1,null,{timeout:20000});
 await p.selectOption('#municipio',{index:1});
 if(await p.locator('#localidad').isVisible()) await p.selectOption('#localidad',{index:1});
 await p.fill('#motivo','Quiero aportar a mi región.');
 for(const c of ['#check-mayor','#check-terminos','#check-datos-sensibles']) await p.check(c);
 await p.click('#btn-enviar');
 OK(await p.waitForSelector('#revision-box',{state:'visible',timeout:20000}).then(()=>true).catch(()=>false),'registro '+x.u);
}
async function login(p,email,pass){
 await p.goto(BASE+'ingresar.html');await p.fill('#email',email);await p.fill('#password',pass);await p.click('#btn-login');
 OK(await p.waitForURL(u=>!u.href.includes('ingresar'),{timeout:40000}).then(()=>true).catch(()=>false),'login '+email);
}
async function modalAccion(p,textoBoton){const m=p.locator('.modal-overlay.abierto').last();await m.getByRole('button',{name:textoBoton}).click();await esperar(1500);}

const PA=await ctx('ana'),PB=await ctx('beto'),ADM=await ctx('admin',false);
await registrar(PA,A);await registrar(PB,B);
await login(ADM,'admin@avancemos.co',process.env.ADMP);
await ADM.goto(BASE+'admin.html#aprobaciones');await esperar(3500);
for(const x of [A,B]){const card=ADM.locator('.aprobacion-tarjeta',{hasText:x.u});
 OK(await card.count()===1 && (await card.innerText()).includes(x.e),'solicitud con nombre completo y correo: '+x.u);
 await card.getByText('Aprobar Usuario').click();await esperar(1500);}

// --- Admin: usuarios (datos completos, etiqueta, rol)
await ADM.click("a[href='#usuarios']");await esperar(2500);
await ADM.fill('#contenido-usuarios input[type=search]',A.u);await esperar(2500);
const filaA=ADM.locator('#contenido-usuarios tr',{hasText:A.u});
OK((await filaA.innerText()).includes(A.n)&&(await filaA.innerText()).includes(A.e),'admin ve nombre completo y correo de Ana');
await filaA.getByText('Ver / editar').click();await esperar(800);
const modalU=ADM.locator('.modal-overlay.abierto').last();
await modalU.locator('input[placeholder^="Ej. Líder"]').fill('Líder de Bogotá');
await modalU.locator('select').nth(3).selectOption('voluntario').catch(()=>{});
await modalU.getByRole('button',{name:'Agregar rol'}).click();await esperar(1500);
OK((await modalU.innerText()).includes('voluntario'),'admin asigna rol voluntario');
await modalAccion(ADM,'Guardar cambios');
await ADM.fill('#contenido-usuarios input[type=search]',A.u);await esperar(2500);
OK((await ADM.locator('#contenido-usuarios tr',{hasText:A.u}).innerText()).includes('Líder de Bogotá'),'etiqueta "Líder de Bogotá" guardada');

// --- Admin: encuesta obligatoria
await ADM.click("a[href='#anuncios']");await esperar(2000);
await ADM.getByRole('button',{name:'🗳️ Nueva votación'}).click();await esperar(600);
const mA=ADM.locator('.modal-overlay.abierto').last();
await mA.locator('input[maxlength="160"]').fill('Votación E2E '+ts+': ¿tema del próximo foro?');
await mA.locator('textarea').first().fill('Elige el tema prioritario para tu región.');
await mA.locator('textarea[placeholder="Una opción por línea"]').fill('Educación\nSeguridad\nEmpleo');
await mA.locator('label.admin-check',{hasText:'Obligatorio'}).locator('input').check();
await modalAccion(ADM,'Publicar');
OK((await txt(ADM,'#contenido-anuncios')).includes('Votación E2E '+ts),'admin publica votación obligatoria');

// --- Admin: evento
await ADM.click("a[href='#eventos']");await esperar(2000);
await ADM.getByRole('button',{name:'➕ Crear evento'}).click();await esperar(600);
const mE=ADM.locator('.modal-overlay.abierto').last();
await mE.locator('input[maxlength="140"]').fill('Foro E2E '+ts);
await mE.locator('textarea').first().fill('Encuentro de prueba.');
const f=new Date(Date.now()+3*86400000);const loc=new Date(f-f.getTimezoneOffset()*60000).toISOString().slice(0,16);
await mE.locator('input[type=datetime-local]').first().fill(loc);
await modalAccion(ADM,'Guardar evento');
OK((await txt(ADM,'#contenido-eventos')).includes('Foro E2E '+ts),'admin crea evento');

// --- Ana: votación obligatoria al entrar
await login(PA,A.e,PASS);await esperar(3500);
const modalVoto=PA.locator('.modal-anuncio.abierto',{hasText:'Votación E2E '+ts});
OK(await modalVoto.count()===1,'Ana ve la votación obligatoria al entrar');
await PA.keyboard.press('Escape');await esperar(500);
OK(await modalVoto.count()===1 && await modalVoto.locator('button[aria-label=Cerrar]').count()===0,'la votación obligatoria no se puede cerrar sin votar');
await modalVoto.locator('label.anuncio-opcion',{hasText:'Empleo'}).click();
await modalVoto.getByRole('button',{name:'Votar'}).click();await esperar(2500);
OK((await modalVoto.innerText()).includes('1 respuesta')||(await modalVoto.innerText()).includes('respuestas'),'se muestran resultados tras votar');
await modalVoto.getByRole('button',{name:'Continuar'}).click();await esperar(800);
while(await PA.locator('.modal-anuncio.abierto').count()){const m=PA.locator('.modal-anuncio.abierto').last();const bt=m.getByRole('button',{name:/Entendido|Continuar/});if(await bt.count())await bt.first().click();else break;await esperar(800);}

// --- Ana: publicar con audio (WAV -> Opus)
function wav(seg=2){const sr=44100,n=sr*seg,buf=Buffer.alloc(44+n*2);buf.write('RIFF',0);buf.writeUInt32LE(36+n*2,4);buf.write('WAVE',8);buf.write('fmt ',12);buf.writeUInt32LE(16,16);buf.writeUInt16LE(1,20);buf.writeUInt16LE(1,22);buf.writeUInt32LE(sr,24);buf.writeUInt32LE(sr*2,28);buf.writeUInt16LE(2,32);buf.writeUInt16LE(16,34);buf.write('data',36);buf.writeUInt32LE(n*2,40);for(let i=0;i<n;i++)buf.writeInt16LE(Math.round(Math.sin(2*Math.PI*440*i/sr)*8000),44+i*2);return buf;}
const wavBuf=wav(3);
await PA.click('.barra-movil-publicar');await esperar(800);
const textoPost='Propuesta con audio E2E '+ts;
await PA.fill('#redactor-texto',textoPost);
await PA.setInputFiles('#redactor-input-archivo',{name:'nota.wav',mimeType:'audio/wav',buffer:wavBuf});
await PA.waitForSelector('#redactor-preview-media audio',{timeout:20000}).catch(()=>{});
const tamAudio=await PA.evaluate(async()=>{const a=document.querySelector('#redactor-preview-media audio');if(!a)return null;const r=await fetch(a.src);const bl=await r.blob();return {tipo:bl.type,tam:bl.size};});
OK(tamAudio && tamAudio.tipo==='audio/webm' && tamAudio.tam < wavBuf.length/5,`audio WAV (${Math.round(wavBuf.length/1024)} KB) convertido a Opus WebM (${tamAudio?Math.round(tamAudio.tam/1024):'?'} KB)`);
await PA.click('#btn-enviar-post');await esperar(4000);
OK(/revisión/.test((await PA.locator('.toast').allTextContents()).join(' ')),'publicación con audio enviada');
await PA.fill('#redactor-texto','Publicación para borrar '+ts);await PA.click('#btn-enviar-post');await esperar(3000);

// --- Admin aprueba (ve el audio en la bandeja)
await ADM.goto(BASE+'admin.html#aprobaciones');await esperar(3000);
await ADM.click('#aprobaciones-pestanas >> text=Publicaciones');await esperar(3000);
const cardPub=ADM.locator('.aprobacion-tarjeta',{hasText:textoPost});
OK(await cardPub.locator('audio').count()===1,'moderador escucha el audio antes de aprobar');
await cardPub.getByRole('button',{name:'Aprobar'}).click();await esperar(2000);
const cardBorrar=ADM.locator('.aprobacion-tarjeta',{hasText:'Publicación para borrar '+ts});
if(await cardBorrar.count()){await cardBorrar.getByRole('button',{name:'Aprobar'}).click();await esperar(1500);}

// --- Beto: ve primer nombre y etiqueta; mensajes solo si sigue
await login(PB,B.e,PASS);await esperar(3000);
while(await PB.locator('.modal-anuncio.abierto').count()){const m=PB.locator('.modal-anuncio.abierto').last();
 if(await m.locator('label.anuncio-opcion').count()){await m.locator('label.anuncio-opcion').first().click();await m.getByRole('button',{name:/Votar|Enviar/}).click();await esperar(2000);await m.getByRole('button',{name:'Continuar'}).click();}
 else await m.getByRole('button',{name:/Entendido/}).click(); await esperar(800);}
await PB.goto(BASE+'app.html#/u/'+A.u);await esperar(3500);
const cab=await txt(PB,'.perfil-cabecera');
OK(cab.includes('Ana')&&!cab.includes('Pérez')&&!cab.includes('María'),'Beto ve solo el primer nombre de Ana: "'+cab.slice(0,40)+'"');
OK(cab.includes('Líder de Bogotá'),'Beto ve la etiqueta junto a la insignia');
const api=await PB.evaluate(async()=>{const {supabase}=await import('./js/supabase.js');const r=await supabase.from('perfiles').select('nombre').limit(1);return r.error?.code||'leyo'});
OK(api==='42501','la API no entrega el nombre completo a otros usuarios ('+api+')');
OK(await PB.locator('.perfil-acciones button',{hasText:'Mensaje'}).isDisabled(),'botón Mensaje deshabilitado si no la sigue');
await PB.locator('.perfil-acciones button',{hasText:'Seguir'}).click();await esperar(2000);
OK(!(await PB.locator('.perfil-acciones button',{hasText:'Mensaje'}).isDisabled()),'al seguirla se habilita Mensaje');
OK((await txt(PB,'.perfil-cuerpo')).includes(textoPost),'Beto ve la publicación aprobada de Ana en su perfil');
await PB.locator('.perfil-acciones button',{hasText:'Mensaje'}).click();await esperar(2500);
await PB.fill('#input-chat','Hola Ana '+ts);await PB.click('#btn-chat-enviar');await esperar(2000);
OK((await txt(PB,'#mensajes-lista')).includes('Hola Ana '+ts),'Beto envía mensaje a quien sigue');

// --- Ana: no sigue a Beto -> no puede responder
await PA.goto(BASE+'app.html#/mensajes');await PA.reload();await esperar(3500);
OK((await txt(PA,'#vista-contenido')).includes('Beto')&&(await txt(PA,'#vista-contenido')).includes('Hola Ana '+ts),'Ana ve la conversación con primer nombre y vista previa');
await PA.locator('.conv-item').first().click();await esperar(3000);
OK(await PA.locator('#input-chat').isDisabled()&&(await txt(PA,'#chat-aviso')).includes('Solo puedes escribir'),'Ana no puede responder porque no sigue a Beto');
// intento directo por API también bloqueado
const bloq=await PA.evaluate(async(conv)=>{const {supabase}=await import('./js/supabase.js');const {data:{user}}=await supabase.auth.getUser();const r=await supabase.from('mensajes').insert({conversacion_id:conv,autor_id:user.id,contenido:'forzado'});return r.error?.code||'insertado'},PA.url().split('/').pop());
OK(bloq==='42501','la base de datos bloquea el mensaje aunque se fuerce por API ('+bloq+')');

// --- Ana: perfil propio, seguidores, editar y eliminar
await PA.goto(BASE+'app.html#/perfil');await esperar(3500);
OK((await txt(PA,'.perfil-cabecera')).includes('Ana María Pérez'),'Ana ve su nombre completo en su perfil');
const pubBorrar=PA.locator('.tarjeta-pub',{hasText:'Publicación para borrar '+ts});
await pubBorrar.getByRole('button',{name:'🗑️ Eliminar'}).click();await esperar(600);await modalAccion(PA,'Eliminar');
OK(await PA.locator('.tarjeta-pub',{hasText:'Publicación para borrar '+ts}).count()===0,'Ana elimina una publicación');
const pubEd=PA.locator('.tarjeta-pub',{hasText:textoPost});
await pubEd.getByRole('button',{name:'✏️ Editar'}).click();await esperar(600);
await PA.locator('.modal-overlay.abierto textarea').fill(textoPost+' (editada)');await modalAccion(PA,'Guardar cambios');
await esperar(2000);
OK((await txt(PA,'.perfil-cuerpo')).includes('(editada)')&&(await txt(PA,'.perfil-cuerpo')).includes('En revisión'),'Ana edita su publicación y vuelve a revisión');
await PA.locator('.perfil-pestanas .pestana',{hasText:'Seguidores'}).click();await esperar(2500);
OK((await txt(PA,'.perfil-cuerpo')).includes('Beto'),'Ana ve a Beto en sus seguidores');
await PA.locator('.perfil-cuerpo .persona-fila button',{hasText:'Seguir'}).click();await esperar(1500);
await PA.locator('.perfil-pestanas .pestana',{hasText:'Siguiendo'}).click();await esperar(2500);
OK((await txt(PA,'.perfil-cuerpo')).includes('Beto'),'Ana sigue a Beto desde su lista y aparece en Siguiendo');
await PA.goto(BASE+'app.html#/ajustes');await esperar(2000);
await PA.fill('#ajustes-bio','Docente y voluntaria en Bogotá '+ts);await PA.getByRole('button',{name:'Guardar biografía'}).click();await esperar(1500);
const nomBloq=await PA.evaluate(async()=>{const {supabase}=await import('./js/supabase.js');const {data:{user}}=await supabase.auth.getUser();const r=await supabase.from('perfiles').update({cargo_titulo:'Presidenta'}).eq('id',user.id);return r.error?.code||'actualizado'});
OK(nomBloq==='42501','el usuario solo puede editar su biografía (etiqueta bloqueada: '+nomBloq+')');

// --- Grupos
await PA.goto(BASE+'app.html#/grupos');await esperar(3000);
OK(await PA.locator('.grupo-tarjeta').count()>=36 && (await txt(PA,'.grupo-destacado')).includes('Bogotá'),'grupos organizados y Bogotá destacado para Ana');
await PA.goto(BASE+'index.html');await PA.locator('#mapa-colombia').scrollIntoViewIfNeeded();await esperar(3000);
const box=await PA.locator('#mapa-colombia').boundingBox();
await PA.locator('path.leaflet-interactive').nth(0).dispatchEvent('click');await esperar(1200);
OK(await PA.locator('.mapa-popup a[href*="chat.whatsapp.com"]').count()===1,'clic en el mapa abre el grupo de WhatsApp del departamento');
await PA.screenshot({path:'n-mapa.png'});
// --- Widget con usuario registrado
await PA.click('.widget-soporte-boton');await esperar(600);
await PA.fill('#widget-soporte-panel input','¿Cómo funcionan las insignias?');await PA.click('#widget-soporte-panel >> text=Enviar');await esperar(6000);
OK(/Te quedan 4/.test(await txt(PA,'.widget-pie-info')),'usuario registrado: '+(await txt(PA,'.widget-pie-info')));
OK(await PA.locator('#widget-soporte-panel input').getAttribute('maxlength')==='120','campo de pregunta limitado a 120 caracteres');

// --- Admin: publicaciones con comentarios
await PB.goto(BASE+'app.html');await PB.reload();await esperar(3000);
const pB=PB.locator('.tarjeta-pub',{hasText:'Propuesta con audio'}).first();
if(await pB.count()){await pB.locator('.pub-ver-comentarios').click();await esperar(1500);await PB.fill('.comentario-input','Comentario para moderar '+ts);await PB.click('.comentario-form button');await esperar(1500);}
await ADM.click("a[href='#publicaciones']");await esperar(3000);
await ADM.fill('#contenido-publicaciones input[type=search]',ts);await esperar(3000);
const cA=ADM.locator('#contenido-publicaciones .aprobacion-tarjeta').first();
OK((await cA.innerText()).includes('Ana María Pérez'),'admin ve todas las publicaciones con autor completo');
await cA.getByRole('button',{name:/Ver comentarios/}).click();await esperar(2000);
OK((await cA.innerText()).includes('Comentario para moderar')||(await cA.innerText()).includes('Sin comentarios'),'admin ve los comentarios de la publicación');
log(`\nFALLOS: ${fallos}`);
log(JSON.stringify([A,B]));
await b.close();
