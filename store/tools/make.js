// node make.js [only]  -> out/...
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const SHOTS = [
  ['next_workout', { eb: 'Next workout', title: 'Your next workout,<br><b>ready</b>', sub: "Last time's weights and what to lift today" },
    { eb: 'التمرينة الجاية', title: 'تمرينك الجاي<br><b>جاهز</b>', sub: 'آخر وزن شِلته والوزن اللي تشيله النهارده' }],
  ['active_workout_log', { eb: 'One tap', title: 'Log a set<br><b>in one tap</b>', sub: 'Weight and reps are already filled in' },
    { eb: 'ضغطة واحدة', title: 'سجّل المجموعة<br><b>بضغطة واحدة</b>', sub: 'الوزن والعدّات جاهزين قدامك' }],
  ['active_workout_rest', { eb: 'Rest timer', title: 'Rest, and Azm<br><b>calls you back</b>', sub: 'It rings even when your phone is locked' },
    { eb: 'مؤقت الراحة', title: 'ارتاح..<br><b>وعزم يرنّلك</b>', sub: 'حتى والموبايل مقفول' }],
  ['progress', { eb: 'Progress', title: 'Watch every lift<br><b>go up</b>', sub: 'Records, levels and every exercise' },
    { eb: 'التقدّم', title: 'شوف أوزانك<br><b>وهي بتطلع</b>', sub: 'أرقام جديدة ومستويات وتقدّم كل تمرين' }],
  ['move_running', { eb: 'Move games', title: 'Your camera<br><b>counts reps</b>', sub: 'On your phone only: no recording, no photos' },
    { eb: 'ألعاب الحركة', title: 'الكاميرا<br><b>بتعدّ ضغطك</b>', sub: 'على موبايلك بس: مفيش تسجيل ولا صور' }],
  ['exercise_guide', { eb: 'Exercise library', title: 'Learn<br><b>the right form</b>', sub: 'A drawing, steps and a how-to video' },
    { eb: 'مكتبة التمارين', title: 'اتعلم<br><b>الطريقة الصح</b>', sub: 'رسمة وخطوات وفيديو لكل تمرين' }],
  ['joined_trainee', { eb: 'Your gym', title: 'Join your gym<br><b>with a code</b>', sub: 'Your captain sets your plan' },
    { eb: 'جيمك', title: 'انضم لجيمك<br><b>بكود</b>', sub: 'الكابتن يظبطلك خطتك ويتابع تقدّمك' }],
  ['plan', { eb: 'Your plan', title: 'Plans that<br><b>fit you</b>', sub: 'Pick a ready plan or build your own' },
    { eb: 'خطتك', title: 'خطة<br><b>على مقاسك</b>', sub: 'اختار خطة جاهزة أو اعمل خطتك بنفسك' }],
  ['gym_colour_navy_home', { eb: 'Gym colours', title: "In your gym's<br><b>colours</b>", sub: 'The app takes the colour your gym chose' },
    { eb: 'ألوان الجيم', title: 'التطبيق<br><b>بلون جيمك</b>', sub: 'بياخد اللون اللي الجيم اختاره' }],
];

// target: [name, w, h, kind, headTop, titleSize, subSize, devW, devTop, max shots, folder fn]
const TARGETS = [
  ['ios_phone', 1320, 2868, 'phone', 150, 128, 50, 1010, 760, 9, (loc, i) => `ios/screenshots/${loc === 'ar' ? 'ar-SA' : 'en-US'}/${i}_iphone69.png`],
  ['ios_ipad', 2064, 2752, 'tablet', 130, 140, 54, 1640, 720, 9, (loc, i) => `ios/screenshots/${loc === 'ar' ? 'ar-SA' : 'en-US'}/${i}_ipad13.png`],
  ['android_phone', 1080, 1920, 'phone', 70, 84, 34, 660, 470, 8, (loc, i) => `android/${loc === 'ar' ? 'ar' : 'en-US'}/images/phoneScreenshots/${i}.png`],
  ['android_7', 1080, 1920, 'tablet', 70, 84, 34, 900, 500, 8, (loc, i) => `android/${loc === 'ar' ? 'ar' : 'en-US'}/images/sevenInchScreenshots/${i}.png`],
  ['android_10', 1440, 2560, 'tablet', 100, 112, 44, 1200, 650, 8, (loc, i) => `android/${loc === 'ar' ? 'ar' : 'en-US'}/images/tenInchScreenshots/${i}.png`],
];

(async () => {
  const only = process.argv[2];
  const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const p = await b.newPage({ viewport: { width: 2064, height: 2868 } });
  await p.goto('file://' + path.resolve(__dirname, 'shot.html'));
  await p.evaluate(() => document.fonts.ready);
  for (const [tname, w, h, kind, headTop, titleSize, subSize, devW, devTop, max, out] of TARGETS) {
    if (only && !tname.startsWith(only)) continue;
    for (const loc of ['ar', 'en']) {
      for (let i = 0; i < Math.min(max, SHOTS.length); i++) {
        const [scr, en, ar] = SHOTS[i];
        const t = loc === 'ar' ? ar : en;
        const img = `raw/${scr}__store${kind}_${loc}_dark.png`;
        await p.setViewportSize({ width: w, height: h });
        await p.evaluate(o => window.render(o), { w, h, dir: loc === 'ar' ? 'rtl' : 'ltr', ...t, img, kind, headTop, titleSize, subSize, devW, devTop });
        await p.evaluate(() => document.fonts.ready);
        const file = path.join('out', out(loc, i + 1));
        fs.mkdirSync(path.dirname(file), { recursive: true });
        await p.screenshot({ path: file, clip: { x: 0, y: 0, width: w, height: h } });
      }
    }
    console.log('done', tname);
  }
  await b.close();
})();
