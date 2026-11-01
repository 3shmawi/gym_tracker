// Renders reference frames of the approved splash animation straight from
// docs/design/motion/splash_animation.dc.html in Chromium (Playwright), the
// way the design canvas shows it, without the wordmark (canvas preview only).
// test/core/ui/azm_logo_reference_test.dart compares the Flutter port with
// them. Re-run only when the .dc.html changes:
//
//   NODE_PATH=$(npm root -g) node scripts/motion_reference.js
//
// Frames: 336 px square on #07120C, viewBox centred on the static logo's
// centre (48.5, 50) and 112 units wide, the same box AzmLogoPainter paints.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.join(__dirname, '..');
const out = path.join(root, 'test/core/ui/motion_reference');
const frames = [0, 0.18, 0.3, 0.48, 0.5, 0.6, 0.66, 0.75, 0.79, 0.9, 0.93, 1];

const source = fs.readFileSync(
  path.join(root, 'docs/design/motion/splash_animation.dc.html'),
  'utf8',
);
const style = source.match(/<style>([\s\S]*?)<\/style>/)[1];
const svg = source
  .match(/(<svg class="anim"[\s\S]*?<\/svg>)/)[1]
  .replace(
    /width="270" height="230" viewBox="[^"]*"/,
    'width="336" height="336" viewBox="-7.5 -6 112 112"',
  );
const html =
  `<!doctype html><html><head><style>${style}</style></head>` +
  '<body style="margin:0;background:#07120C">' +
  `<div style="--d:2.6s;width:336px;height:336px">${svg}</div></body></html>`;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 336, height: 336 } });
  await page.setContent(html);
  // Start every animation first: seeking a not-yet-started one to 0 shows
  // a later frame.
  await page.evaluate(() =>
    Promise.all(document.getAnimations().map((a) => a.ready)),
  );
  for (const t of frames) {
    await page.evaluate((t) => {
      for (const a of document.getAnimations()) {
        a.pause();
        a.currentTime = 2600 * t;
      }
    }, t);
    await page.screenshot({ path: path.join(out, `frame_${t}.png`) });
  }
  await browser.close();
})();
