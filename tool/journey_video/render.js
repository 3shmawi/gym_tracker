// Renders one journey episode from build/journey/ (prepared by build.sh).
//   node render.js plan   <ep>                 → plan_<ep>.json (times for music.py)
//   node render.js video  <ep> <out.mp4>       → silent video, 1080×1920, 30 fps
//   node render.js stills <ep> [t1,t2,…]       → stills/<ep>/t_<t>.jpg (default: key moments)
//   node render.js cover  <ep>                 → covers/<ep>.jpg
// The page is served over a local http server so the promo iframe is same-origin.
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.json': 'application/json' };
const FPS = 30;

function serve() {
  return new Promise(res => {
    const srv = http.createServer((q, r) => {
      const p = path.join(ROOT, decodeURIComponent(new URL(q.url, 'http://x').pathname));
      if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { r.writeHead(404); return r.end(); }
      r.writeHead(200, { 'content-type': TYPES[path.extname(p)] || 'application/octet-stream' });
      fs.createReadStream(p).pipe(r);
    }).listen(0, '127.0.0.1', () => res(srv));
  });
}

(async () => {
  const [, , mode, ep, arg] = process.argv;
  const srv = await serve();
  const base = `http://127.0.0.1:${srv.address().port}/journey.html?ep=${ep}`;
  const browser = await chromium.launch({ args: ['--font-render-hinting=none'] });
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => console.log('pageerror:', e.message));
  page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
  await page.goto(mode === 'cover' ? base + '&cover=1' : base);
  await page.evaluate(() => window.__ready);

  if (mode === 'plan') {
    fs.writeFileSync(path.join(ROOT, `plan_${ep}.json`), JSON.stringify(await page.evaluate(() => window.__plan), null, 1));
  } else if (mode === 'cover') {
    fs.mkdirSync(path.join(ROOT, 'covers'), { recursive: true });
    await page.screenshot({ path: path.join(ROOT, 'covers', `${ep}.jpg`), type: 'jpeg', quality: 92 });
  } else if (mode === 'stills') {
    const dir = path.join(ROOT, 'stills', ep); fs.mkdirSync(dir, { recursive: true });
    const ts = arg ? arg.split(',').map(Number) : await page.evaluate(() => window.__keyTimes);
    for (const t of ts) {
      await page.evaluate(t => window.__seek(t), t);
      await page.screenshot({ path: path.join(dir, `t_${t.toFixed(2)}.jpg`), type: 'jpeg', quality: 85 });
    }
    console.log('stills', ep, ts.join(','));
  } else if (mode === 'video') {
    const D = await page.evaluate(() => window.__D);
    const frames = Math.round(D * FPS);
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '23', '-tune', 'grain', '-pix_fmt', 'yuv420p', '-r', String(FPS), arg], { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let f = 0; f < frames; f++) {
      await page.evaluate(t => window.__seek(t), f / FPS);
      const buf = await page.screenshot({ type: 'jpeg', quality: 93 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (f % 300 === 0) console.log(ep, f, '/', frames);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
  }
  await browser.close();
  srv.close();
})();
