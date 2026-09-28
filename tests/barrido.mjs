import { chromium, devices } from 'playwright-core';
const b=await chromium.launch({executablePath:process.env.CHROMIUM || '/snap/bin/chromium',args:['--no-sandbox']});
const pages=process.argv.slice(2);
for (const [nombre,opts] of [['movil360',{...devices['Galaxy S9+'],viewport:{width:360,height:740}}],['escritorio',{viewport:{width:1366,height:850}}]]) {
  const c=await b.newContext(opts);
  for (const pg of pages){const p=await c.newPage();const errs=[];
    p.on('pageerror',e=>errs.push('PAGEERROR '+e.message.slice(0,120)));
    p.on('console',m=>{if(m.type()==='error'&&!/fonts|ERR_NAME/.test(m.text()))errs.push('console '+m.text().slice(0,120))});
    p.on('response',r=>{if(r.status()>=400&&!/fonts/.test(r.url()))errs.push('HTTP '+r.status()+' '+r.url().slice(0,100))});
    p.on('dialog',d=>d.dismiss());
    await p.goto('http://localhost:3000/'+pg,{waitUntil:'networkidle'}).catch(e=>errs.push('NAV '+e.message.slice(0,80)));
    await p.waitForTimeout(1200);
    const sw=await p.evaluate(()=>document.documentElement.scrollWidth).catch(()=>0);
    const vw=opts.viewport.width;
    if(errs.length||sw>vw) console.log(`[${nombre}] ${pg} ancho=${sw}${sw>vw?' ❌DESBORDE':''}\n   `+errs.join('\n   '));
    await p.close();}
  await c.close();
}
console.log('barrido terminado');await b.close();
