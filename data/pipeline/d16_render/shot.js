const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 440, height: 600 }, deviceScaleFactor: 2 });
  p.on('console', m => console.log('console:', m.text()));
  const http = require('http'), fs = require('fs'), path = require('path');
  const srv = http.createServer((req, res) => {
    const f = path.join(__dirname, decodeURIComponent(req.url.split('?')[0]));
    fs.readFile(f, (e, d) => { if (e) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': f.endsWith('.mjs') || f.endsWith('.js') ? 'text/javascript' : f.endsWith('.json') ? 'application/json' : 'text/html' }); res.end(d); });
  }).listen(8123);
  for (const z of process.argv.slice(2)) {
    await p.goto(`http://localhost:8123/page.html?style=wya-pins-style-1.json&lon=8.5417&lat=47.3769&z=${z}`);
    try { await p.waitForFunction('window.done === true', null, { timeout: 60000 }); } catch (e) { console.log('timeout', z); }
    await p.screenshot({ path: `z${z}.png` });
    console.log('shot', z);
  }
  await b.close(); srv.close();
})();
