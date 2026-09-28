import { chromium, devices } from 'playwright-core';
const b=await chromium.launch({executablePath:process.env.CHROMIUM || '/snap/bin/chromium',args:['--no-sandbox']});
const OK=(c,m)=>console.log((c?'✅':'❌')+' '+m);
for (const [nombre,opts] of [['escritorio',{viewport:{width:1366,height:850}}],['movil',{...devices['Pixel 7']}]]) {
  const c=await b.newContext(opts);const p=await c.newPage();
  p.on('pageerror',e=>console.log('  PAGEERROR',e.message.slice(0,150)));
  p.on('response',r=>{if(r.status()>=400&&!/fonts/.test(r.url()))console.log('  HTTP',r.status(),r.url().slice(0,110))});
  p.on('dialog',d=>d.dismiss());
  await p.goto('http://localhost:3000/ingresar.html');await p.fill('#email','admin@avancemos.co');await p.fill('#password',process.env.ADMP);await p.click('#btn-login');
  await p.waitForURL(/admin\.html/,{timeout:40000});await p.waitForTimeout(3000);
  OK(true,`[${nombre}] admin entra al panel`);
  const sw=await p.evaluate(()=>document.documentElement.scrollWidth);OK(sw<=opts.viewport.width,`[${nombre}] sin desborde (${sw}px)`);
  await p.screenshot({path:`admin-${nombre}.png`});
  if(nombre==='movil'){await p.click("a[href='#aprobaciones']");await p.waitForTimeout(1500);await p.screenshot({path:'admin-movil-aprob.png'});OK(await p.locator('#sec-aprobaciones').isVisible(),'[movil] sección Aprobaciones accesible');}
  if(nombre==='escritorio'){
    await p.click("a[href='#estudio-ia']");await p.waitForTimeout(800);
    await p.screenshot({path:'admin-escritorio-ia.png'});await p.fill('#prompt-ia','Parque comunitario en un municipio colombiano con niños jugando al atardecer, sin rostros reconocibles');
    if(process.env.GENERAR) await p.click('#btn-generar-ia');
    await p.waitForFunction(()=>document.getElementById('btn-generar-ia').textContent.includes('Generar Imagen'),null,{timeout:120000}).catch(()=>{});
    const img=process.env.GENERAR?await p.locator('#preview-resultado-ia img').count():1;
    if(process.env.GENERAR) OK(img===1,'Estudio IA genera imagen');
    await p.locator('#preview-resultado-ia').screenshot({path:'admin-ia.png'});
  }
  await c.close();
}
await b.close();
