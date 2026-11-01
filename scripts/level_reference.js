// Renders the level figures (lv1, lv2, lv3) straight from
// docs/design/motion/level_figures.dc.html in Chromium (Playwright), like
// scripts/motion_reference.js does for the splash.
// test/core/ui/azm_level_reference_test.dart compares the Flutter port with
// them. Re-run only when the .dc.html changes:
//
//   NODE_PATH=$(npm root -g) node scripts/level_reference.js
//
// Frames: 240×280 px (4 px per unit of the 60×70 box) on #07120C.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.join(__dirname, '..');
const out = path.join(root, 'test/core/ui/level_reference');
const source = fs.readFileSync(
  path.join(root, 'docs/design/motion/level_figures.dc.html'),
  'utf8',
);
// The hidden <svg> holding the gradients and the lv1/lv2/lv3 symbols.
const defs = source.match(/(<svg width="0" height="0"[\s\S]*?<\/svg>)/)[1];

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 240, height: 280 } });
  for (const lv of ['lv1', 'lv2', 'lv3']) {
    await page.setContent(
      '<!doctype html><html><body style="margin:0;background:#07120C">' +
        defs +
        '<svg width="240" height="280" viewBox="0 0 60 70" style="display:block">' +
        `<use href="#${lv}"></use></svg></body></html>`,
    );
    await page.screenshot({ path: path.join(out, `${lv}.png`) });
  }
  await browser.close();
})();
