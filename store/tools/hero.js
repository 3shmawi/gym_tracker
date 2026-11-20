// App Store "Header" and "Search results" creative assets (iOS 27+), from the
// same raw renders as make.js. fastlane can't upload these yet: upload them in
// App Store Connect (see store/README.md -> App Store header and search).
//   cd store/tools && node hero.js
// Specs (Apple "Creative assets specifications", checked 2026-11-15):
//   Header 3840x1646 (21:9), art safe area 1646x661 at (1097, 493)
//   Search results 3840x2560 (3:2), art safe area 2168x1030 at (836, 765)
// No transparency; keep text short; no prices, URLs or other platforms.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const here = __dirname;
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'shots.json'), 'utf8'));
const hero = cfg.hero;
const raw = (screen, loc) => 'file://' + path.join(here, 'raw', `${screen}__storephone_${loc}_dark.png`);
const out = path.resolve(here, '../ios/app_store_assets');
const folder = (family) => family.replace(/[^A-Za-z0-9]/g, '');

(async () => {
  if (JSON.stringify(hero).includes('TODO')) {
    console.error('shots.json "hero" still has TODO texts');
    process.exit(1);
  }
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const page = await browser.newPage({ viewport: { width: 3840, height: 2560 } });
  await page.goto('file://' + path.join(here, 'hero.html'));
  await page.evaluate((o) => window.setup(o), { latin: folder(cfg.fonts.latin), arabic: folder(cfg.fonts.arabic), brand: cfg.brand });
  const [s1, s2, s3, s4] = hero.screens;
  for (const loc of ['ar', 'en']) {
    const t = hero[loc];
    const rtl = loc === 'ar';
    // Header: text in the safe area, four phones as atmosphere at the sides.
    await page.setViewportSize({ width: 3840, height: 1646 });
    await page.evaluate((o) => window.render(o), {
      w: 3840, h: 1646, dir: rtl ? 'rtl' : 'ltr', ...t, ws: 230, ts: 96,
      text: { x: 1097, y: 493, w: 1646, h: 661 },
      phones: [
        { x: 120, y: 260, w: 620, r: -8, img: raw(s3, loc) }, { x: 520, y: 120, w: 620, r: -3, img: raw(s1, loc) },
        { x: 2700, y: 120, w: 620, r: 3, img: raw(s2, loc) }, { x: 3100, y: 260, w: 620, r: 8, img: raw(s4, loc) },
      ],
    });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(out, `header_${loc}.png`) });
    // Search results: text and two phones, all inside the safe area.
    const sx = 836, sy = 765, sw = 2168, sh = 1030, pw = 440;
    const px = rtl ? sx + 40 : sx + sw - 2 * pw - 80;
    await page.setViewportSize({ width: 3840, height: 2560 });
    await page.evaluate((o) => window.render(o), {
      w: 3840, h: 2560, dir: rtl ? 'rtl' : 'ltr', ...t, ws: 200, ts: 80,
      text: { x: rtl ? sx + sw - 1150 : sx, y: sy, w: 1150, h: sh },
      phones: [
        { x: px, y: sy + 70, w: pw, r: rtl ? 4 : -4, img: raw(s2, loc) },
        { x: px + pw + 20, y: sy + 20, w: pw, r: rtl ? -3 : 3, img: raw(s1, loc) },
      ],
    });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(out, `search_${loc}.png`) });
  }
  console.log(`✓ App Store header (3840×1646) and search results (3840×2560) in ${path.relative(process.cwd(), out)}`);
  await browser.close();
})().catch((e) => { console.error(e.message || e); process.exit(1); });
