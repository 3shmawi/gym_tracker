const { chromium } = require('playwright'); const path=require('path'); const fs=require('fs');
(async()=>{const b=await chromium.launch({args:['--allow-file-access-from-files']});
const p=await b.newPage({viewport:{width:1024,height:500}});
await p.goto('file://'+path.resolve(__dirname,'feature.html')); await p.evaluate(()=>document.fonts.ready);
const L={ar:{dir:'rtl',word:'عزم',tag:'تمرينك الجاي<br><b>جاهز قبل ما توصل</b>',sub:'آخر وزن · سجّل بضغطة · مؤقت راحة'},
 en:{dir:'ltr',word:'Azm',tag:'Your next workout,<br><b>ready before you arrive</b>',sub:'Last weights · One-tap logging · Rest timer'}};
for(const loc of ['ar','en']){const o={...L[loc],a:`raw/active_workout_log__storephone_${loc}_dark.png`,b:`raw/next_workout__storephone_${loc}_dark.png`};
await p.evaluate(o=>window.render(o),o); await p.evaluate(()=>document.fonts.ready);
const f=`out/android/${loc==='ar'?'ar':'en-US'}/images/featureGraphic.png`; fs.mkdirSync(path.dirname(f),{recursive:true});
await p.screenshot({path:f});}
await b.close();})();
