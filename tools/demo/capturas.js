// Capturas reales de la demo (plan B del artefacto si un visor no deja arrancar la app).
// Uso: node tools/demo/capturas.js <url-de-la-app> <carpeta-salida>
const { chromium } = require('playwright');

const RAIL = { perfil: [60, 70], biblioteca: [60, 295], big: [60, 666], ajustes: [60, 732] };

(async () => {
  const [url, out] = process.argv.slice(2);
  const b = await chromium.launch();
  const hechas = { android: [], mac: [] };
  for (const plat of ['android', 'mac']) {
    const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, locale: 'es-ES' });
    const p = await ctx.newPage();
    const ir = async () => { await p.goto(`${url}?${plat}#${plat}`); await p.waitForTimeout(9000); };
    const foto = async (n) => { await p.screenshot({ path: `${out}/${plat}-${n}.jpg`, type: 'jpeg', quality: 80 }); hechas[plat].push(n); };
    await ir(); await foto('home');
    await p.mouse.click(700, 400); await p.keyboard.press('ArrowDown'); await p.waitForTimeout(2500); await foto('juego');
    for (const n of ['biblioteca', 'perfil', 'ajustes']) {
      await ir(); await p.mouse.click(...RAIL[n]); await p.waitForTimeout(3000); await foto(n);
    }
    await ir(); await p.mouse.click(...RAIL.big); await p.mouse.move(1270, 10); await p.waitForTimeout(3500); await foto('big');
    await ctx.close();
  }
  await b.close();
  console.log(JSON.stringify(hechas));
})();
