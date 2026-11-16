// The «من الصفر لحد النهارده» episodes, as data on top of journey.html.
// Every fact has its source next to it (commit, PR or docs/ file); the plan
// with captions is docs/social/journey_series.md, the facts are in
// docs/social/journey_timeline.md. Text: *x y* = accent colour.
// Images: assets/g/<golden>.jpg = test/features/*/presentation/goldens/<golden>/phone_ar_dark.png
//         assets/store/<n>.jpg  = store/android/ar/images/phoneScreenshots/<n>.png
window.SERIES = {
  name: 'من الصفر لحد النهارده',
  total: 11,
  handle: 'Mohager',
  url: 'azmm.pages.dev',
  follow: 'تابع للحلقة الجاية',
};

window.EPISODES = [
  {
    id: '00', n: 0, title: 'تريلر', dates: '31 أكتوبر ← 15 نوفمبر', hue: 0, seed: 10, key: 0,
    coverTitle: '16 يوم.. *من الصفر*', coverSub: 'رحلة بناء عزم، حلقة حلقة', coverImg: 'assets/store/1.jpg',
    cta: 'الحلقة الأولى: *اليوم صفر*',
    scenes: [
      { type: 'hook', d: 4, kicker: 'سلسلة جديدة', text: 'آخر مرة *شِلت كام؟*' },                       // docs/brand/promo_video (the problem line)
      { type: 'say', d: 4, text: 'في 16 يوم بنيت تطبيق جيم *بيفتكرلك.*' },                               // git log: 2026-10-31 → 2026-11-15
      { type: 'counters', d: 6, caption: 'بالأرقام', items: [                                            // journey_timeline.md → Numbers
        { n: 16, label: 'يوم' }, { n: 130, label: 'commit' }, { n: 117, label: 'PR اتدمج' }, { n: 72, label: 'إصدار' }] },
      { type: 'fan', d: 5, caption: 'تمرينك الجاي، سجّل بضغطة، *والكاميرا بتعدّ*', imgs: ['assets/store/1.jpg', 'assets/store/2.jpg', 'assets/store/5.jpg'], label: 'صور الستور من شاشات حقيقية' },
      { type: 'timeline', d: 6, caption: 'كل مربع = *PR* اتدمج', countLabel: 'PR في 16 يوم' },
      { type: 'say', d: 4, text: 'من أول سطر لحد صفحة الستور.. *حلقة حلقة.*' },
    ],
  },
  {
    id: '01', n: 1, title: 'اليوم صفر', dates: '31 أكتوبر', hue: -6, seed: 11, key: 0,
    coverTitle: 'اليوم *صفر*', coverSub: 'فولدر فاضي.. وبعد يوم 310 ملف', coverImg: 'assets/g/next_workout_no_plan.jpg',
    cta: 'الحلقة الجاية: *أول شاشة*',
    scenes: [
      { type: 'hook', d: 4, kicker: '31 أكتوبر 2026', text: 'فولدر فاضي.. وبعد يوم: *310 ملف.*' },        // 247391e: 310 files
      { type: 'say', d: 4.5, kicker: 'الفكرة', text: 'تمرينك الجاي، *آخر وزن شِلته*، وتسجيل بسرعة.' },   // CLAUDE.md product line
      { type: 'counters', d: 5, caption: 'أول commit', items: [{ n: 310, label: 'ملف' }, { n: 11178, label: 'سطر' }] }, // 247391e --stat
      { type: 'chips', d: 6, caption: 'الأدوات اتقررت *من أول يوم*', items: ['Flutter', 'Supabase', 'Riverpod', 'Sentry', 'PostHog', 'go_router', 'عربي + English', 'GitHub Actions'] }, // docs/decisions/0001-initial-stack.md
      { type: 'diagram', d: 6, caption: 'كل feature *3 طبقات*', nodes: [                                  // CLAUDE.md → Feature layers
        { t: 'presentation', d: 'الشاشات والـ state' }, { t: 'domain', d: 'القواعد · Dart صافي' }, { t: 'data', d: 'الداتا والـ repositories' }] },
      { type: 'say', d: 5, text: 'القاعدة: *الدوكس قبل الكود*، وكل feature معاها تستات.' },                 // CLAUDE.md → Rules
    ],
  },
  {
    id: '02', n: 2, title: 'أول شاشة', dates: '1 نوفمبر', hue: 0, seed: 12, key: 2,
    coverTitle: 'أول *شاشة*', coverSub: 'وليه كل شاشة بتتجرب على 32 شكل', coverImg: 'assets/g/next_workout.jpg',
    cta: 'الحلقة الجاية: *أول باج من موبايل حقيقي*',
    scenes: [
      { type: 'hook', d: 4, text: 'شكله حلو.. *لحد ما فتحته على تابلت.*' },                                 // #1, b19a406
      { type: 'shot', d: 5.5, caption: 'التمرين الجاي جاهز: *زوّد، ثبّت، ولا قلّل*', img: 'assets/g/next_workout.jpg' }, // #1, docs/features/workout.md
      { type: 'shot', d: 5, caption: 'سجّل المجموعة *بضغطة*.. والراحة بتعدّ لوحدها', img: 'assets/g/active_workout_rest.jpg' }, // #1
      { type: 'split', d: 5.5, caption: 'الدرس', before: { tag: 'على التابلت', t: 'الكلام كبر *2.2×*', d: 'والزراير خدت خط تاني' }, after: { tag: 'الحل', t: 'المقاس محصور بين *0.9 و 1.15*', d: 'على أي شاشة' } }, // b19a406 body
      { type: 'code', d: 6, caption: 'سطرين.. *وخلصت*', file: 'lib/core/theme/app_dimens.dart', lines: ['static const minScale = 0.9;', 'static const maxScale = 1.15;'] }, // app_dimens.dart:17-18
      { type: 'counters', d: 5, items: [{ n: 32, label: 'شكل لكل شاشة في التستات' }], note: 'موبايلات وتابلت · عربي وإنجليزي · فاتح وغامق · خط كبير' }, // b19a406, docs/design.md
      { type: 'say', d: 4, kicker: 'نفس اليوم', text: 'مستويات، تقدّم.. *وأول إصدار v0.1.0*' },          // #5, #7, tag v0.1.0 (2026-11-01)
    ],
  },
  {
    id: '03', n: 3, title: 'الموبايل الحقيقي', dates: '2 ← 4 نوفمبر', hue: 6, seed: 13, key: 3,
    coverTitle: 'الأبلكيشن *بيقفل لوحده*', coverSub: 'أول باج من موبايل حقيقي', coverImg: 'assets/g/exercise_history.jpg',
    cta: 'الحلقة الجاية: *من لوحدك لجيم*',
    scenes: [
      { type: 'hook', d: 4, text: 'الأبلكيشن *بيقفل لوحده* وإنت بتعمل scroll.' },                         // #15
      { type: 'diagram', d: 6.5, caption: 'إيه اللي حصل؟', nodes: [                                         // f1cdd93 body
        { t: 'كارت زجاج واحد', d: 'حوالين الهيستوري كله' },
        { t: 'بيصوّر اللي وراه', d: 'بطول الليستة كلها' },
        { t: 'الذاكرة خلصت', d: 'و iOS قفل التطبيق', kind: 'bad' }] },
      { type: 'code', d: 6.5, caption: 'الحل: *كارت عادي* للليستة الطويلة', file: 'lib/core/ui/app_ui.dart', lines: ['if (tall) {', '  return GlassContainer.card(', '    surfaceStyle: GlassSurfaceStyle.solid,', '    // …', '  );', '}'], hl: [2] }, // f1cdd93
      { type: 'counters', d: 5.5, caption: 'وبعدين *قِسنا*', items: [{ n: 19, pre: '4–', suf: '×', label: 'الـ blur كان بيكلّف كده في رسم الشاشة' }], note: 'الحل: الكروت بنفس الشكل.. من غير blur' }, // cb855d0, docs/performance.md
      { type: 'say', d: 4.5, text: 'ومن ساعتها: *workflow للأداء* بيقيس قبل وبعد.' },                     // cb855d0 (perf label / manual)
      { type: 'shot', d: 4.5, caption: 'وكمان: *"الراحة خلصت"* والموبايل مقفول', img: 'assets/g/next_workout_resting.jpg' }, // #12
    ],
  },
  {
    id: '04', n: 4, title: 'من لوحدك لجيم', dates: '2 ← 5 نوفمبر', hue: -4, seed: 14, key: 5,
    coverTitle: 'من لوحدك *لجيم*', coverSub: 'QR واحد.. والمتدرب جوّه', coverImg: 'assets/g/joined_trainee.jpg',
    cta: 'الحلقة الجاية: *اتعلّم التمرين صح*',
    scenes: [
      { type: 'hook', d: 4.5, text: 'الكابتن عايز يعرف المتدرب شال كام.. *من غير ما يسأله.*' },            // docs/decisions/gym_accounts.md
      { type: 'chips', d: 6, caption: 'القرارات *قبل الكود*', items: ['اللي لوحده يفضل من غير حساب', 'الكابتن يضيف المتدرب', 'QR لمرة واحدة · 7 أيام', 'كود 6 حروف تحت الـ QR', 'التمرين ملك صاحبه'] }, // gym_accounts.md §1
      { type: 'diagram', d: 6, nodes: [                                                                       // gym_accounts.md §1, #20 #21 #27
        { t: 'الكابتن يطبع كارت QR' }, { t: 'المتدرب يعمل scan' }, { t: 'اللينك يفتح التطبيق' }, { t: 'جوّه الجيم', kind: 'good' }] },
      { type: 'code', d: 6, caption: 'باج: *الكود كان بيضيع* من اللينك', file: 'website/_redirects', lines: ['- /join/*  /join.html  200', '+ /join/*  /join  200'], note: 'الاستضافة كانت بتحوّل .html وبتشيل الكود (308)' }, // ae2f316 (#60)
      { type: 'shot', d: 5, caption: 'أهلًا بيك في *الجيم*', img: 'assets/g/joined_trainee.jpg', label: 'شاشة حقيقية · الجيم تجريبي' }, // #27, golden joined_trainee
    ],
  },
  {
    id: '05', n: 5, title: 'اتعلّم التمرين صح', dates: '3 ← 4 نوفمبر', hue: 4, seed: 15, key: 7,
    coverTitle: 'ليه الفيديو *مبيكملش*؟', coverSub: 'قرار، مش باج', coverImg: 'assets/g/exercise_guide.jpg',
    cta: 'الحلقة الجاية: *داشبورد الكابتن*',
    scenes: [
      { type: 'hook', d: 4.5, text: 'ليه الفيديو *مبيكملش* لما تخرج من التطبيق؟' },                       // docs/decisions/video_outside_app.md
      { type: 'say', d: 3, text: '*ده قرار.* مش باج.' },
      { type: 'shot', d: 5, caption: 'مكتبة تمارين *برسومات وخطوات*', img: 'assets/g/exercise_guide.jpg' }, // #31 #33
      { type: 'options', d: 6.5, kicker: 'قواعد YouTube API', caption: 'الفيديو برة التطبيق؟', items: [   // video_outside_app.md → Options A–C
        { t: 'Picture-in-Picture', d: 'ممنوع: player في الخلفية' },
        { t: 'صوت في الخلفية', d: 'ممنوع برضه' },
        { t: 'ميني بلاير جوّه التطبيق', d: 'مسموح، وده اللي اتعمل', ok: true }] },                    // #48 #50
      { type: 'say', d: 4, text: 'بنقرا القواعد الأول.. *وبعدين نبني.*' },
      { type: 'fan', d: 5, caption: 'وصور *من الجيم نفسه* لكل تمرين', imgs: ['assets/g/exercise_guide_gym_four_pictures.jpg', 'assets/g/library.jpg', 'assets/g/library_chest.jpg'] }, // #36 #38
    ],
  },
  {
    id: '06', n: 6, title: 'داشبورد الكابتن', dates: '4 ← 12 نوفمبر', hue: -8, seed: 16, key: 3,
    coverTitle: 'والكابتن *؟*', coverSub: 'داشبورد ويب في 7 مراحل', coverImg: 'assets/g/gym_colour_navy_home.jpg',
    cta: 'الحلقة الجاية: *متخسرش تمرينك*',
    scenes: [
      { type: 'hook', d: 4, text: 'التطبيق للمتدرب.. *والكابتن؟*' },
      { type: 'say', d: 4.5, kicker: 'قرار 3 نوفمبر', text: 'مفيش أدوات كابتن في التطبيق.. *كله في داشبورد ويب.*' }, // gym_accounts.md §1 (changed 2026-11-03)
      { type: 'steps', d: 7.5, caption: '7 مراحل', items: [                                                // #53 #54 #72 #73 #74 #75 #82
        { no: 'D0', t: 'دخول بكود على الإيميل' }, { no: 'D1', t: 'الأعضاء وكروت QR' }, { no: 'D2', t: 'صور وفيديو التمارين' },
        { no: 'D3', t: 'خطة كل متدرب' }, { no: 'D4', t: 'قوالب الخطط' }, { no: 'D5', t: 'تقدّم المتدربين' }, { no: 'D6', t: 'لون الجيم' }] },
      { type: 'timeline', d: 5.5, caption: 'من 4 لـ 12 نوفمبر', highlight: [[53, 54], [72, 75], [82, 82], [84, 88]], countLabel: 'PR للداشبورد' }, // PR list
      { type: 'fan', d: 5.5, caption: 'والتطبيق بياخد *لون الجيم*', imgs: ['assets/g/gym_colour_navy_home.jpg', 'assets/g/gym_colour_yellow_workout.jpg', 'assets/g/next_workout.jpg'], label: 'شاشات حقيقية · ألوان تجريبية' }, // #81
      { type: 'counters', d: 4.5, items: [{ n: 234, label: 'تست للداشبورد لوحده' }] },                  // grep in dashboard/
    ],
  },
  {
    id: '07', n: 7, title: 'متخسرش تمرينك', dates: '11 ← 15 نوفمبر', hue: 8, seed: 17, key: 0,
    coverTitle: 'آخر *200* تمرين بس', coverSub: 'وإزاي بقى الهيستوري كله في أمان', coverImg: 'assets/g/backup_done_restored.jpg',
    cta: 'الحلقة الجاية: *الكاميرا بتعدّ*',
    scenes: [
      { type: 'hook', d: 4, text: 'كان بيحفظ *آخر 200 تمرين* بس.' },                                        // docs/designs/never_lose_history.md
      { type: 'split', d: 6, before: { tag: 'قبل', t: 'ملف JSON واحد', d: 'بيتكتب كله مع كل حفظ · آخر 200' }, after: { tag: 'بعد', t: 'قاعدة SQLite *على الموبايل*', d: 'الهيستوري كله' } }, // #90
      { type: 'shot', d: 5, caption: 'موبايل جديد؟ *تمارينك بترجع.*', img: 'assets/g/backup_done_restored.jpg' }, // #95
      { type: 'diagram', d: 6.5, kicker: 'باج اتمسك', nodes: [                                               // 3ae5f9c (#113)
        { t: 'الكابتن يقدر يقرا تمارين متدربيه' }, { t: 'والصلاحيات بتتجمع' },
        { t: 'الريستور جاب تمارينهم في هيستوري الكابتن', kind: 'bad' }] },
      { type: 'code', d: 6, caption: 'الحل: الطلب *بيسمّي الشخص*', file: 'restore (#113)', lines: ['if (person == null) {', '  return const RestorePage(sessions: []);', '}', '// …', "    .eq('person_id', person);"], hl: [4] }, // 3ae5f9c
      { type: 'say', d: 4, text: 'وتست بيتأكد من *الطلب نفسه.*' },                                          // restore_rows_test.dart (3ae5f9c)
    ],
  },
  {
    id: '08', n: 8, title: 'الكاميرا بتعدّ', dates: '12 ← 15 نوفمبر', hue: -2, seed: 18, key: 5,
    coverTitle: 'الكاميرا *بتعدّ*', coverSub: 'ضغط حقيقي.. على الموبايل نفسه', coverImg: 'assets/g/move_running.jpg',
    cta: 'الحلقة الجاية: *الجودة*',
    scenes: [
      { type: 'hook', d: 4, text: 'اعمل ضغط.. *والموبايل يعدّ.*' },                                         // #92
      { type: 'shot', d: 5, caption: 'العدّ *على الموبايل نفسه*', img: 'assets/g/move_running.jpg' },      // #92 #98 #99
      { type: 'chips', d: 5, caption: 'الخصوصية *أولًا*', items: ['مفيش تسجيل', 'مفيش صور', 'ولا حاجة بتخرج من الموبايل', 'عدّاد يدوي لو مش عايز كاميرا'] }, // docs/designs/move_games.md → Goal 4
      { type: 'steps', d: 7, caption: '4 مشاكل *من موبايلات حقيقية*', items: [
        { no: '#104', t: 'التطبيق بيقفل أول ما يفتح', d: 'Android release' },
        { no: '#105', t: 'الكاميرا وقفت ورا رسالة الإذن' },
        { no: '#106', t: 'موبايل OPPO اتقال عليه بطيء', d: 'وصاحبه لسه قاعد' },
        { no: '#108', t: 'العدّ وقف بعد الرجوع للتطبيق' }] },
      { type: 'diagram', d: 6, caption: 'إزاي بنختبر العدّ؟', nodes: [                                    // a80c875 (#103)
        { t: 'فيديو ضغط حقيقي', d: 'بيفضل على الكمبيوتر' }, { t: '13 مفصل وأوقات بس', d: 'مفيش فيديو في الريبو' }, { t: 'التست يعدّ ويقارن', kind: 'good' }] },
      { type: 'say', d: 4, text: 'الفكرة من لعبة viral.. *بس ولا حاجة منها اتنسخت.*' },                  // move_games.md → Originality rule
    ],
  },
  {
    id: '09', n: 9, title: 'الجودة', dates: 'من أول يوم', hue: 2, seed: 19, key: 2,
    coverTitle: '*1,649* تست', coverSub: 'ليه؟', coverImg: 'assets/g/next_workout.jpg',
    cta: 'الحلقة الجاية: *على الستور*',
    scenes: [
      { type: 'hook', d: 4, text: '*1,649* تست.. ليه؟' },                                                     // journey_timeline.md → Numbers
      { type: 'counters', d: 6, items: [{ n: 1649, label: 'تست Flutter' }, { n: 234, label: 'تست للداشبورد' }, { n: 25, label: 'ملف تست لصلاحيات الداتابيز' }, { n: 32, label: 'شكل لكل شاشة' }] },
      { type: 'fan', d: 5, caption: 'نفس الشاشة: *عربي وإنجليزي، فاتح وغامق*', imgs: ['assets/g/next_workout.jpg', 'assets/g/next_workout_en_light.jpg', 'assets/g/next_workout_small.jpg'], label: 'صور التستات نفسها' }, // goldens
      { type: 'diagram', d: 6.5, caption: 'كل PR', nodes: [                                                   // CLAUDE.md → Quality gates, Security
        { t: 'تستات + analyze + coverage' }, { t: 'فحص أسرار وثغرات', d: 'gitleaks · OSV-Scanner · zizmor' }, { t: 'merge = إصدار', kind: 'good' }] },
      { type: 'counters', d: 4.5, items: [{ n: 72, label: 'إصدار في 16 يوم' }] },                              // git tag -l 'v*'
      { type: 'say', d: 4, text: 'الـ main *محمي*: مفيش merge غير لما كله يبقى أخضر.' },                   // CLAUDE.md → Quality gates
    ],
  },
  {
    id: '10', n: 10, title: 'على الستور', dates: '14 ← 16 نوفمبر', hue: -5, seed: 20, key: 7,
    coverTitle: 'صفحة الستور.. *كود*', coverSub: 'عربي وإنجليزي، من الريبو', coverImg: 'assets/store/7.jpg',
    cta: 'آخر حلقة: *وصلنا لحد فين*',
    scenes: [
      { type: 'hook', d: 4, text: 'حتى صفحة الستور.. *كود.*' },                                              // store/README.md
      { type: 'fan', d: 5.5, caption: '8 صور، *عربي وإنجليزي*', imgs: ['assets/store/1.jpg', 'assets/store/6.jpg', 'assets/store/7.jpg'], label: 'معمولة من شاشات حقيقية' }, // #116
      { type: 'code', d: 6, caption: 'النصوص *في الريبو*', file: 'store/', lines: ['android/ar/title.txt', 'android/ar/full_description.txt', 'ios/ar-SA/description.txt', 'ios/ar-SA/release_notes.txt', 'play_app_content.json'] }, // store/ tree
      { type: 'diagram', d: 6, nodes: [                                                                       // store/README.md, #119–#124
        { t: 'تعديل نص في الريبو' }, { t: 'PR' }, { t: 'تشغيل Store listing', d: 'GitHub Actions' }, { t: 'الستور اتحدّث', kind: 'good' }] },
      { type: 'shot', d: 5, caption: 'أول مرة؟ *3 خطط جاهزة*', img: 'assets/g/next_workout_no_plan.jpg' }, // #107
      { type: 'say', d: 4, text: 'كده *جاهز للستور.*' },
    ],
  },
  {
    id: '11', n: 11, title: 'وصلنا لحد فين', dates: '16 نوفمبر', hue: 0, seed: 21, key: 0,
    coverTitle: 'وصلنا *لحد فين*', coverSub: '16 يوم · 117 PR · 72 إصدار', coverImg: 'assets/store/5.jpg',
    cta: 'جرّبه، *وقولّي أبني إيه بعد كده*',
    scenes: [
      { type: 'hook', d: 4, text: 'من فولدر فاضي.. *لده.*' },
      { type: 'timeline', d: 6.5, caption: 'الرحلة كلها', countLabel: 'PR في 16 يوم' },
      { type: 'counters', d: 6, items: [{ n: 7, label: 'features' }, { n: 20, label: 'صفحة' }, { n: 659, label: 'جملة × لغتين' }, { n: 72, label: 'إصدار' }] }, // journey_timeline.md → Numbers
      { type: 'say', d: 4.5, kicker: 'إزاي؟', text: 'مع AI coding agent.. *وكل سطر عدّى على تستات.*' },    // Co-Authored-By lines in git log
      { type: 'promo', d: 8, caption: 'وده *عزم* النهارده', from: 95 },    // docs/brand/promo_video (#112), 92–103 s
    ],
  },
];
