// Store screenshots + Google Play feature graphic and icon, from the app's
// real screens (test/store/store_screenshots_test.dart writes raw/).
//   cd store/tools && npm install && npx playwright install chromium && node make.js
// Writes straight into store/ (fastlane layout). See store/README.md.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const here = __dirname;
const store = path.resolve(here, '..');
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'shots.json'), 'utf8'));

// Sizes checked against Apple "Screenshot specifications" and Google Play
// "Add preview assets" (2026-11-15); fastlane maps them by pixel size.
// [name, width, height, raw kind, headTop, titleSize, subSize, devW, devTop, max, output path]
const TARGETS = [
  ['iPhone 6.9"', 1320, 2868, 'phone', 150, 128, 50, 1010, 760, 10, (l, i) => `ios/screenshots/${l.ios}/${i}_iphone69.png`],
  ['iPad 13"', 2064, 2752, 'tablet', 130, 140, 54, 1640, 720, 10, (l, i) => `ios/screenshots/${l.ios}/${i}_ipad13.png`],
  ['Play phone', 1080, 1920, 'phone', 70, 84, 34, 660, 470, 8, (l, i) => `android/${l.play}/images/phoneScreenshots/${i}.png`],
  ['Play 7"', 1080, 1920, 'tablet', 70, 84, 34, 900, 500, 8, (l, i) => `android/${l.play}/images/sevenInchScreenshots/${i}.png`],
  ['Play 10"', 1440, 2560, 'tablet', 100, 112, 44, 1200, 650, 8, (l, i) => `android/${l.play}/images/tenInchScreenshots/${i}.png`],
];
const LOCALES = [
  { code: 'ar', dir: 'rtl', ios: 'ar-SA', play: 'ar' },
  { code: 'en', dir: 'ltr', ios: 'en-US', play: 'en-US' },
];

const folder = (family) => family.replace(/[^A-Za-z0-9]/g, '');
const raw = (screen, kind, loc) => path.join(here, 'raw', `${screen}__store${kind}_${loc}_dark.png`);

function onColor(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
  const lum = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255);
  return (lum + 0.05) / 0.05 >= 1.05 / (lum + 0.05) ? '#000000' : '#FFFFFF';
}

function check() {
  const problems = [];
  if (JSON.stringify({ ...cfg, _help: '', hero: null }).includes('TODO')) problems.push('shots.json still has TODO texts');
  for (const s of cfg.shots) for (const kind of ['phone', 'tablet']) for (const l of LOCALES) {
    if (!fs.existsSync(raw(s.screen, kind, l.code))) problems.push(`missing ${path.relative(store, raw(s.screen, kind, l.code))}`);
  }
  if (problems.length) {
    console.error(problems.join('\n') + '\n\nRun the screen renders first (store/README.md -> Screenshots).');
    process.exit(1);
  }
}

// Apple refuses images with an alpha channel: PNG colour type must be 2 (RGB).
function assertNoAlpha(file) {
  const b = fs.readFileSync(file);
  if (b[25] !== 2) throw new Error(`${file} has an alpha channel (PNG colour type ${b[25]})`);
}

(async () => {
  check();
  const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const page = await browser.newPage({ viewport: { width: 1320, height: 2868 } });
  const fonts = { latin: folder(cfg.fonts.latin), arabic: folder(cfg.fonts.arabic) };
  await page.goto('file://' + path.join(here, 'shot.html'));
  await page.evaluate((o) => window.setup(o), { ...fonts, brand: cfg.brand, onBrand: onColor(cfg.brand) });
  await page.evaluate(() => document.fonts.ready);

  for (const [name, w, h, kind, headTop, titleSize, subSize, devW, devTop, max, out] of TARGETS) {
    // Old images of this size are removed first, so a shorter list leaves no stale file.
    for (const l of LOCALES) {
      const first = path.join(store, out(l, 1));
      const suffix = path.basename(first).replace(/^1/, '');
      const dir = path.dirname(first);
      if (!fs.existsSync(dir)) continue;
      for (const f of fs.readdirSync(dir)) if (new RegExp(`^\\d+${suffix.replace('.', '\\.')}$`).test(f)) fs.rmSync(path.join(dir, f));
    }
    await page.setViewportSize({ width: w, height: h });
    for (const l of LOCALES) {
      for (const [i, s] of cfg.shots.slice(0, max).entries()) {
        const missing = await page.evaluate((o) => window.render(o), {
          w, h, kind, headTop, titleSize, subSize, devW, devTop, dir: l.dir, ...s[l.code],
          img: 'file://' + raw(s.screen, kind, l.code),
        });
        if (missing) throw new Error(missing);
        await page.evaluate(() => document.fonts.ready);
        const file = path.join(store, out(l, i + 1));
        fs.mkdirSync(path.dirname(file), { recursive: true });
        await page.screenshot({ path: file, clip: { x: 0, y: 0, width: w, height: h }, omitBackground: false });
        assertNoAlpha(file);
      }
    }
    console.log(`✓ ${name} (${w}×${h})`);
  }

  // Google Play feature graphic (1024×500, the listing's header).
  await page.setViewportSize({ width: 1024, height: 500 });
  await page.goto('file://' + path.join(here, 'feature.html'));
  await page.evaluate((o) => window.setup(o), { ...fonts, brand: cfg.brand });
  await page.evaluate(() => document.fonts.ready);
  const [a, b] = cfg.feature.screens;
  for (const l of LOCALES) {
    await page.evaluate((o) => window.render(o), {
      dir: l.dir, ...cfg.feature[l.code],
      a: 'file://' + raw(a, 'phone', l.code), b: 'file://' + raw(b, 'phone', l.code),
    });
    await page.evaluate(() => document.fonts.ready);
    const file = path.join(store, `android/${l.play}/images/featureGraphic.png`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await page.screenshot({ path: file });
    assertNoAlpha(file);
  }
  console.log('✓ Play feature graphic (1024×500)');

  // Google Play hi-res icon (512×512) from the app icon.
  const icon = path.resolve(store, '../assets/branding/icon.png');
  await page.setViewportSize({ width: 512, height: 512 });
  await page.setContent(`<body style="margin:0"><img src="file://${icon}" style="width:512px;height:512px;display:block"></body>`);
  await page.waitForLoadState('load');
  for (const l of LOCALES) await page.screenshot({ path: path.join(store, `android/${l.play}/images/icon.png`) });
  console.log('✓ Play icon (512×512)');
  await browser.close();
})().catch((e) => { console.error(e.message || e); process.exit(1); });
