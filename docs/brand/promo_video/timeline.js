// Deterministic timeline: every animation is a paused Web Animation; __seek(t) sets them all.
const D = 103;
const $ = (s, r = document) => (typeof s === 'string' ? r.querySelector(s) : s);
const $$ = (s, r = document) => (typeof s === 'string' ? [...r.querySelectorAll(s)] : (s instanceof Element) ? [s] : [...s]);
const EO = 'cubic-bezier(.16,1,.3,1)';
const EIO = 'cubic-bezier(.65,0,.35,1)';
const EI = 'cubic-bezier(.5,0,.75,0)';
const BACK = 'cubic-bezier(.34,1.56,.64,1)';
const TK = [];
let rngS = 7;
const rnd = () => { rngS |= 0; rngS = (rngS + 0x6D2B79F5) | 0; let t = Math.imul(rngS ^ (rngS >>> 15), 1 | rngS); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };

function A(target, kf, at, dur, ease = EO, o = {}) {
  $$(target).forEach((el, i) => {
    const frames = Array.isArray(kf) ? kf : [kf];
    const props = Object.keys(frames[0]).filter(k => !['offset', 'easing', 'composite'].includes(k));
    el.__seen = el.__seen || new Set();
    const first = props.every(p => !el.__seen.has(p));
    props.forEach(p => el.__seen.add(p));
    const st = at + (o.stagger || 0) * i;
    const a = el.animate(frames, { delay: st * 1000, duration: dur * 1000, easing: ease, fill: o.fill || (first ? 'both' : 'forwards'), iterations: o.iterations || 1 });
    a.pause();
  });
}
const fin = (el, at, dur = .7, y = 40, o = {}) => A(el, [{ opacity: 0, transform: `translateY(${y}px)` }, { opacity: 1, transform: 'translateY(0px)' }], at, dur, o.ease || EO, o);
const fout = (el, at, dur = .4, o = {}) => A(el, [{ opacity: 1 }, { opacity: 0 }], at, dur, o.ease || 'ease-in', o);
const pop = (el, at, dur = .6, o = {}) => A(el, [{ opacity: 0, transform: 'scale(.4)' }, { opacity: 1, transform: 'scale(1)' }], at, dur, BACK, o);
function tap(el, at) {
  el = $(el);
  const t = el.querySelector(':scope > .tap');
  if (t) A(t, [{ opacity: 0, transform: 'scale(.3)' }, { opacity: 1, transform: 'scale(.75)', offset: .25 }, { opacity: 0, transform: 'scale(1.7)' }], at, .65, 'ease-out');
  A(el, [{ scale: '1' }, { scale: '.94', offset: .3 }, { scale: '1' }], at, .4, 'ease-out');
}
function caption(c, tin, tout) {
  c = $(c);
  const eb = c.querySelector('.eyebrow');
  if (eb) A(eb, [{ opacity: 0, transform: 'translateX(-40px)' }, { opacity: 1, transform: 'none' }], tin, .7);
  A(c.querySelectorAll('.ttl .ln > span'), [{ transform: 'translateY(115%)' }, { transform: 'translateY(0)' }], tin + .12, .9, EO, { stagger: .13 });
  c.querySelectorAll('.sub').forEach(s => fin(s, tin + .45, .8, 30));
  A(c.querySelectorAll('.chips .chip'), [{ opacity: 0, transform: 'translateY(24px) scale(.9)' }, { opacity: 1, transform: 'none' }], tin + .75, .6, BACK, { stagger: .09 });
  A(c, [{ opacity: 1, transform: 'translateX(0)' }, { opacity: 0, transform: 'translateX(60px)' }], tout, .45, 'ease-in', { fill: 'forwards' });
  A(c, [{ visibility: 'hidden' }, { visibility: 'visible' }], tin, .001, 'linear');
}
function screen(el, tin, tout, from = 'left') {
  const x = from === 'left' ? -390 : 0;
  if (from === 'fade') A(el, [{ opacity: 0, transform: 'scale(1.06)' }, { opacity: 1, transform: 'none' }], tin, .5);
  else A(el, [{ opacity: 0, transform: `translateX(${x}px)` }, { opacity: 1, transform: 'none' }], tin, .55);
  if (tout != null) A(el, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateX(140px)' }], tout, .45, EIO);
}
const tick = f => TK.push(f);
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const ease = x => 1 - Math.pow(1 - x, 3);

// ---------- logo CSS animation (approved splash, 2.6 s) ----------
const css = document.createElement('style');
css.textContent = `
#logoAnim .f1load,#logoAnim .f1arms,#logoAnim .f1all,#logoAnim .f2bar,#logoAnim .f2arms,#logoAnim .b3all,#logoAnim .mid,#logoAnim .f3grow,#logoAnim .pumpL,#logoAnim .pumpR{transform-box:fill-box}
#logoAnim *{animation-delay:.55s!important}
#logoAnim .f1load{animation:f1load var(--d) cubic-bezier(.2,.8,.2,1) both}
#logoAnim .f1arms{transform-origin:50% 100%;animation:f1arms var(--d) cubic-bezier(.2,.8,.2,1) both}
#logoAnim .f1all{animation:sideL var(--d) cubic-bezier(.4,0,.2,1) both}
#logoAnim .f2x{opacity:0;animation:f2appear var(--d) ease both}
#logoAnim .f2bar{animation:f2bar var(--d) both}
#logoAnim .f2arms{transform-origin:50% 100%;animation:f2arms var(--d) both}
#logoAnim .b3all{animation:sideR var(--d) cubic-bezier(.4,0,.2,1) both}
#logoAnim .f3x{opacity:0;animation:f3appear var(--d) ease both}
#logoAnim .f3grow{transform-origin:50% 100%;animation:f3grow var(--d) cubic-bezier(.2,.9,.3,1.2) both}
#logoAnim .b3fade{animation:b3fade var(--d) ease both}
#logoAnim .b2fade{animation:b2fade var(--d) ease both}
#logoAnim .mid{animation:midL var(--d) cubic-bezier(.4,0,.2,1) both}
#logoAnim .pumpL{transform-origin:95% 60%;animation:pump var(--d) both}
#logoAnim .pumpR{transform-origin:5% 60%;animation:pump var(--d) both}
@keyframes f1load{0%{transform:translateY(14px);opacity:1}18%{transform:translateY(0);opacity:1}24%{transform:translateY(10px);opacity:0}90%{transform:translateY(-6px);opacity:0}97%,100%{transform:translateY(0);opacity:1}}
@keyframes f1arms{0%{transform:scaleY(.3);opacity:1}18%{transform:scaleY(1);opacity:1}24%{transform:scaleY(.3);opacity:0}90%{transform:scaleY(.3);opacity:0}97%,100%{transform:scaleY(1);opacity:1}}
@keyframes sideL{0%,26%{transform:translateX(0)}32%,58%{transform:translateX(-4.5px)}62%{transform:translateX(0)}66%,87%{transform:translateX(-2.6px)}93%,100%{transform:translateX(0)}}
@keyframes sideR{0%,26%{transform:translateX(0)}32%,58%{transform:translateX(16px)}64%,100%{transform:translateX(0)}}
@keyframes f2appear{0%,27%{opacity:0}32%,53%{opacity:1}58%,100%{opacity:0}}
@keyframes f2bar{0%,32%{transform:translateY(16px)}48%{transform:translate(0,0)}50%{transform:translate(.8px,0)}52%{transform:translate(-.8px,0)}54%{transform:translate(0,0)}60%,100%{transform:translate(0,14px)}}
@keyframes f2arms{0%,32%{transform:scaleY(.3)}48%,54%{transform:scaleY(1)}60%,100%{transform:scaleY(.3)}}
@keyframes f3appear{0%,64%{opacity:0}69%,87%{opacity:1}92%,100%{opacity:0}}
@keyframes f3grow{0%,64%{transform:scale(.35,.9)}71%,100%{transform:scale(1,1)}}
@keyframes b2fade{0%,27%{opacity:1}32%,53%{opacity:0}58%,100%{opacity:1}}
@keyframes b3fade{0%,64%{opacity:1}69%,87%{opacity:0}92%,100%{opacity:1}}
@keyframes midL{0%,62%{transform:translateX(0)}66%,87%{transform:translateX(-14.1px)}93%,100%{transform:translateX(0)}}
@keyframes pump{0%,71%{transform:scale(1)}75%{transform:scale(1.12)}79%{transform:scale(1.02)}83%{transform:scale(1.1)}87%,100%{transform:scale(1)}}`;
document.head.appendChild(css);

function qrSvg(seed, size = 25) {
  rngS = seed;
  const m = [];
  for (let y = 0; y < size; y++) { m.push([]); for (let x = 0; x < size; x++) m[y].push(rnd() < .48); }
  const finder = (ox, oy) => { for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) { const e = x === 0 || y === 0 || x === 6 || y === 6; const c = x >= 2 && x <= 4 && y >= 2 && y <= 4; m[oy + y][ox + x] = e || c; } for (let i = -1; i < 8; i++) { [[ox + i, oy + 7], [ox + 7, oy + i], [ox + i, oy - 1], [ox - 1, oy + i]].forEach(([x, y]) => { if (x >= 0 && y >= 0 && x < size && y < size && !(x >= ox && x < ox + 7 && y >= oy && y < oy + 7)) m[y][x] = false; }); } };
  finder(0, 0); finder(size - 7, 0); finder(0, size - 7);
  let r = '';
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (m[y][x]) r += `<rect x="${x}" y="${y}" width="1.02" height="1.02"/>`;
  return `<svg viewBox="0 0 ${size} ${size}" style="width:100%;height:100%;display:block" fill="#0C1610" shape-rendering="crispEdges">${r}</svg>`;
}

function build() {
  // ---------- measure (before any animation exists) ----------
  const dm = $('#dmain').getBoundingClientRect();
  const posOf = (sel, dx = 0, dy = 0) => { const r = $(sel).getBoundingClientRect(); return [r.left - dm.left + r.width / 2 + dx, r.top - dm.top + r.height / 2 + dy]; };
  // need panes visible for measuring: they are all laid out (opacity untouched yet)
  const P = {
    add: posOf('#addBtn'), mk: posOf('#mkBtn'), edit: posOf('#tg1', -10, 0), apply: posOf('#applyBtn'),
    sw2: posOf('#sw2'), sw3: posOf('#sw3'), sw5: posOf('#sw5'), sw1: posOf('#sw1'),
  };

  // ---------- global ----------
  A('#fade', [{ opacity: 1 }, { opacity: 0 }], 0, .8, 'linear');
  A('#fade', [{ opacity: 0 }, { opacity: 1 }], 101.8, 1.1, 'linear', { fill: 'forwards' });
  A('.b1', [{ transform: 'translate(0,0) scale(1)' }, { transform: 'translate(-520px,260px) scale(1.15)' }, { transform: 'translate(-80px,120px) scale(1)' }], 0, D, 'ease-in-out');
  A('.b2', [{ transform: 'translate(0,0)' }, { transform: 'translate(620px,-200px)' }, { transform: 'translate(200px,-60px)' }], 0, D, 'ease-in-out');
  A('.b3', [{ transform: 'translate(0,0) scale(1)' }, { transform: 'translate(-400px,-200px) scale(1.5)' }, { transform: 'translate(300px,100px) scale(1)' }], 0, D, 'ease-in-out');
  A('.grid', [{ transform: 'translateY(0)' }, { transform: 'translateY(-160px)' }], 0, D, 'linear');
  A('#mark', [{ opacity: 0, transform: 'translateY(-20px)' }, { opacity: 1, transform: 'none' }], 14.4, .6);
  A('#mark', [{ opacity: 1 }, { opacity: 0 }], 61.6, .4, 'ease-in', { fill: 'forwards' });
  A('#mark', [{ opacity: 0 }, { opacity: 1 }], 66.6, .5, 'ease-out', { fill: 'forwards' });
  A('#mark', [{ opacity: 1 }, { opacity: 0 }], 91.5, .4, 'ease-in', { fill: 'forwards' });

  // ---------- S1 intro ----------
  A('#s1logo', [{ opacity: 0, transform: 'translateY(150px) scale(1)' }, { opacity: 1, transform: 'translateY(150px) scale(1.18)' }], .2, 1.2);
  A('#s1logo', [{ transform: 'translateY(150px) scale(1.18)' }, { transform: 'translateY(10px) scale(.82)' }], 3.25, .9, EIO);
  A('#s1ar', [{ opacity: 0, transform: 'translateY(70px)', filter: 'blur(14px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], 3.45, 1.0);
  A('#s1en', [{ opacity: 0, letterSpacing: '1em' }, { opacity: 1, letterSpacing: '.32em' }], 3.7, 1.2);
  fin('#s1tag', 4.5, .9, 30);
  A('#s1wrap', [{ opacity: 1, transform: 'scale(1)', filter: 'blur(0)' }, { opacity: 0, transform: 'scale(1.35)', filter: 'blur(10px)' }], 7.1, .9, EI);
  A('#flash', [{ opacity: 0 }, { opacity: .85, offset: .3 }, { opacity: 0 }], 7.75, .8, 'ease-out');

  // ---------- S2 problem ----------
  const notesTxt = ['بنش.. 20 ولا 22.5؟', 'آخر مرة كام عدّة؟', 'ظرافة ؟؟ × 10', 'الكشكول فين؟', 'اسكوات 60؟ 70؟', 'نسيت تاني..', 'كتف دمبل: ؟'];
  const pos = [[150, 150, -8], [1500, 190, 6], [130, 860, 5], [1530, 860, -6], [640, 930, -4], [1150, 110, 7], [620, 100, -3]];
  const notes = $('#notes');
  notesTxt.forEach((t, i) => {
    const d = document.createElement('div');
    d.className = 'abs note';
    d.style.cssText = `left:${pos[i][0]}px;top:${pos[i][1]}px;padding:16px 26px;background:#F3EEDC;color:#3b3322;border-radius:10px;font:700 34px Cairo,Inter;box-shadow:0 20px 40px -10px #000a;transform:rotate(${pos[i][2]}deg);white-space:nowrap`;
    d.innerHTML = `<div class="nt">${t}</div><div class="strike" style="position:absolute;left:10px;right:10px;top:50%;height:5px;border-radius:3px;background:#DC2626;transform-origin:right;transform:scaleX(0)"></div>`;
    notes.appendChild(d);
    A(d, [{ opacity: 0, transform: `rotate(${pos[i][2] * 3}deg) scale(.5)` }, { opacity: 1, transform: `rotate(${pos[i][2]}deg) scale(1)` }], 8.5 + i * .14, .6, BACK);
    A(d, [{ translate: '0 0' }, { translate: `${(rnd() - .5) * 60}px ${-30 - rnd() * 30}px` }], 8.5, 3, 'linear');
    A(d.querySelector('.strike'), [{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], 10.5 + i * .06, .3, EIO);
    A(d, [{ opacity: 1, transform: `rotate(${pos[i][2]}deg) scale(1)` }, { opacity: 0, transform: `rotate(${pos[i][2] * 4}deg) scale(.6)` }], 11.0 + i * .03, .45, EI);
  });
  fin('#s2l1', 8.15, .7, 30);
  A('#s2big .w', [{ opacity: 0, transform: 'translateY(90px) rotate(5deg) scale(.85)' }, { opacity: 1, transform: 'none' }], 8.55, .65, BACK, { stagger: .15 });
  A('#s2a', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-80px)' }], 11.0, .5, EI);
  A('#s2c1', [{ opacity: 0, transform: 'scale(1.25)', filter: 'blur(16px)' }, { opacity: 1, transform: 'scale(1)', filter: 'blur(0)' }], 11.35, .8);
  fin('#s2c2', 11.95, .7, 30);
  A('#s2b', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'scale(.92)' }], 13.6, .5, EI);

  // ---------- phone section ----------
  A('#phoneBob', [{ opacity: 0, transform: 'translateY(300px) rotateX(20deg) rotateY(-28deg) scale(.9)' }, { opacity: 1, transform: 'translateY(0) rotateX(0deg) rotateY(9deg) scale(1)' }], 13.95, 1.4);
  A('#phoneBob', [{ opacity: 1, transform: 'translateY(0) rotateX(0deg) rotateY(9deg) scale(1)' }, { opacity: 0, transform: 'translateY(240px) rotateX(10deg) rotateY(9deg) scale(.9)' }], 61.5, .7, EI);
  A('#phone', [{ transform: 'translateY(0) rotate(0deg)' }, { transform: 'translateY(-14px) rotate(-.6deg)' }, { transform: 'translateY(0) rotate(0deg)' }], 14, 6, 'ease-in-out', { iterations: 8 });
  // the rig sways a little between chapters
  A('#phoneRig', [{ transform: 'rotateY(0deg)' }, { transform: 'rotateY(-6deg)' }, { transform: 'rotateY(0deg)' }], 23, 2, EIO);

  // Today
  A('#scrToday', [{ opacity: 0 }, { opacity: 1 }], 14.2, .3, 'linear');
  fin('#scrToday .t-in', 14.5, .8, 30, { stagger: .1 });
  A('#scrToday .t-row', [{ opacity: 0, transform: 'translateX(-40px)' }, { opacity: 1, transform: 'none' }], 15.0, .6, EO, { stagger: .09 });
  const hl = $$('#scrToday .hl');
  [17.4, 17.9, 18.4, 18.9, 19.4].forEach((t, i) => A(hl[i], [{ transform: 'scale(1)', boxShadow: '0 0 0 0 rgba(255,255,255,0)' }, { transform: 'scale(1.25)', boxShadow: '0 0 0 7px rgba(255,255,255,.14)', offset: .35 }, { transform: 'scale(1)', boxShadow: '0 0 0 0 rgba(255,255,255,0)' }], t, .75, 'ease-out'));
  const c3chips = $$('#c3 .chip');
  [[0, 17.4], [1, 17.9], [0, 18.4], [2, 18.9], [3, 19.4]].forEach(([c, t]) => A(c3chips[c], [{ scale: '1' }, { scale: '1.12', offset: .35 }, { scale: '1' }], t, .75, 'ease-out'));
  tap('#startBtn', 22.35);
  caption('#c3', 14.7, 22.6);
  A('#scrToday', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateX(140px)' }], 22.85, .45, EIO);

  // Workout
  screen('#scrWork', 22.9, 35.2);
  A('#sc1 .nw', [{ opacity: 0 }, { opacity: 1 }], 23.6, .3, 'linear');
  tap('#plusBtn', 25.3);
  A('#wv1', [{ transform: 'translateY(0)', opacity: 1 }, { transform: 'translateY(-100%)', opacity: 0 }], 25.4, .35, EO);
  A('#wv2', [{ transform: 'translateY(100%)', opacity: 0 }, { transform: 'translateY(0)', opacity: 1 }], 25.4, .35, EO);
  const lls = $$('#logLbl .ll');
  const lblSwap = (a, b, t) => { A(lls[a], [{ transform: 'translateY(0)', opacity: 1 }, { transform: 'translateY(-100%)', opacity: 0 }], t, .3, EO, { fill: lls[a].__seen ? 'forwards' : 'both' }); A(lls[b], [{ transform: 'translateY(100%)', opacity: 0 }, { transform: 'translateY(0)', opacity: 1 }], t, .3, EO); };
  [1, 2, 3].forEach(i => A(lls[i], [{ opacity: 0 }, { opacity: 0 }], 0, .01, 'linear'));
  lls.forEach(l => (l.__seen = new Set()));
  lblSwap(0, 1, 26.6); lblSwap(1, 2, 32.85); lblSwap(2, 3, 33.6);
  const setDone = (n, t) => {
    A(`#sc${n} .on`, [{ opacity: 0, transform: 'scale(.6)' }, { opacity: 1, transform: 'scale(1)' }], t, .45, BACK);
    A(`#sc${n} .nw`, [{ opacity: 1 }, { opacity: 0 }], t, .2, 'linear');
    if (n < 3) A(`#sc${n + 1} .nw`, [{ opacity: 0 }, { opacity: 1 }], t + .1, .3, 'linear');
  };
  tap('#logBtn', 26.45); setDone(1, 26.6);
  const pb = $('#wprog i:first-child b');
  A(pb, [{ transform: 'scaleX(0)' }, { transform: 'scaleX(.34)' }], 26.6, .5);
  A(pb, [{ transform: 'scaleX(.34)' }, { transform: 'scaleX(.67)' }], 32.85, .5);
  A(pb, [{ transform: 'scaleX(.67)' }, { transform: 'scaleX(1)' }], 33.6, .5);
  A('#rest', [{ transform: 'translateY(110%)' }, { transform: 'translateY(0)' }], 26.95, .6);
  A('#rest', [{ transform: 'translateY(0)' }, { transform: 'translateY(110%)' }], 31.5, .5, EI);
  A('#restRing', [{ strokeDashoffset: 0 }, { strokeDashoffset: 552.9 }], 27.4, 3.4, 'linear');
  tick(t => { const p = clamp((t - 27.4) / 3.4); const s = Math.round(90 * (1 - p)); $('#restT').textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; });
  A('#notif', [{ transform: 'translateY(-170%)', opacity: 0 }, { transform: 'translateY(0)', opacity: 1 }], 30.85, .6, BACK);
  A('#notif', [{ transform: 'translateY(0)', opacity: 1 }, { transform: 'translateY(-170%)', opacity: 0 }], 32.3, .45, EI);
  A('#ph', [{ transform: 'translateX(0)' }, { transform: 'translateX(-5px)' }, { transform: 'translateX(5px)' }, { transform: 'translateX(-4px)' }, { transform: 'translateX(4px)' }, { transform: 'translateX(-2px)' }, { transform: 'translateX(0)' }], 30.9, .45, 'linear');
  tap('#logBtn', 32.7); setDone(2, 32.85);
  tap('#logBtn', 33.45); setDone(3, 33.6);
  tap('#logBtn', 34.7);
  caption('#c4', 23.15, 28.5);
  caption('#c4b', 28.85, 35.0);

  // Summary
  screen('#scrSum', 35.3, 43.3, 'fade');
  fin('#scrSum .u-in', 35.5, .7, 30, { stagger: .15 });
  A('#sumCheck', [{ transform: 'scale(0) rotate(-30deg)' }, { transform: 'scale(1) rotate(0)' }], 35.55, .7, BACK);
  tick(t => { const p = ease(clamp((t - 35.9) / 1.5)); $('#kVol').textContent = Math.round(6240 * p).toLocaleString('en-US'); });
  A('#scrSum .rec', [{ opacity: 0, transform: 'translateX(-40px)' }, { opacity: 1, transform: 'none' }], 36.4, .6, EO, { stagger: .12 });
  const conf = $('#confetti');
  rngS = 99;
  const cols = ['#22C55E', '#4ADE80', '#FBBF24', '#93C5FD', '#C4B5FD', '#F2F7F3'];
  for (let i = 0; i < 70; i++) {
    const p = document.createElement('i');
    const w = 6 + rnd() * 8, h = 8 + rnd() * 10;
    p.style.cssText = `position:absolute;left:195px;top:150px;width:${w}px;height:${h}px;border-radius:2px;background:${cols[i % cols.length]}`;
    conf.appendChild(p);
    const ang = rnd() * Math.PI * 2, sp = 120 + rnd() * 220;
    const dx = Math.cos(ang) * sp, dy = Math.sin(ang) * sp - 120;
    const r = (rnd() - .5) * 1080;
    A(p, [{ opacity: 0, transform: 'translate(0,0) rotate(0) scale(.3)' }, { opacity: 1, transform: `translate(${dx}px,${dy}px) rotate(${r / 2}deg) scale(1)`, offset: .35 }, { opacity: 0, transform: `translate(${dx * 1.3}px,${dy + 520}px) rotate(${r}deg) scale(1)` }], 35.95 + rnd() * .15, 2.0, 'cubic-bezier(.2,.6,.4,1)');
  }
  caption('#c5', 35.6, 43.1);
  $$('#c5 .lv').forEach(l => { const h = document.createElement('div'); h.className = 'hi'; l.appendChild(h); });
  A('#c5 .lv', [{ opacity: 0, transform: 'translateY(40px) scale(.9)' }, { opacity: 1, transform: 'none' }], 36.7, .7, BACK, { stagger: .15 });
  const lvHi = (n, tin, tout) => { A(`#lv${n}t .hi`, [{ opacity: 0 }, { opacity: 1 }], tin, .35, 'linear'); A(`#lv${n}t .hi`, [{ opacity: 1 }, { opacity: 0 }], tout, .35, 'linear'); A(`#lv${n}t`, [{ scale: '1' }, { scale: '1.1', offset: .4 }, { scale: '1.04' }], tin, .6, BACK); if (tout < 50) A(`#lv${n}t`, [{ scale: '1.04' }, { scale: '1' }], tout, .4); A(`#lv${n}t b`, [{ color: '#A9B8AF' }, { color: '#F2F7F3' }], tin, .3, 'linear'); };
  lvHi(1, 38.2, 39.5); lvHi(2, 39.5, 40.9); lvHi(3, 40.9, 99);

  // Library -> exercise -> video
  screen('#scrLib', 43.35, 45.25);
  A('#scrLib .lt', [{ opacity: 0, transform: 'scale(.85)' }, { opacity: 1, transform: 'none' }], 43.6, .5, BACK, { stagger: .07 });
  tap('#ltPec', 44.85);
  screen('#scrEx', 45.3, 49.75);
  A('#vidCard', [{ opacity: 0, transform: 'translateY(30px)' }, { opacity: 1, transform: 'none' }], 45.6, .6);
  tap('#vidCard', 46.3);
  A('#player', [{ transform: 'translateY(110%)' }, { transform: 'translateY(0)' }], 46.5, .6);
  A('#player', [{ transform: 'translateY(0)', opacity: 1 }, { transform: 'translateY(60%)', opacity: 0 }], 48.15, .45, EI);
  A('#pbar', [{ width: '0%' }, { width: '40%' }], 46.9, 1.5, 'linear');
  A('.pfig', [{ transform: 'scaleX(1)' }, { transform: 'scaleX(.9) translateY(4px)' }, { transform: 'scaleX(1)' }], 46.9, 1.2, 'ease-in-out', { iterations: 3 });
  tap('#keepW', 47.85);
  A('#mini', [{ opacity: 0, transform: 'translate(120px,-230px) scale(1.75)' }, { opacity: 1, transform: 'none' }], 48.2, .7);
  A('#mbar', [{ width: '40%' }, { width: '75%' }], 48.3, 1.6, 'linear');
  caption('#c6', 43.6, 49.5);

  // Move
  screen('#scrMove', 49.8, 57.55, 'fade');
  const tower = $('#tower');
  const repT = []; for (let k = 0; k < 8; k++) repT.push(50.75 + .7 * (k + 1));
  rngS = 3;
  repT.forEach((t, k) => {
    const b = document.createElement('div');
    const off = (rnd() - .5) * 14;
    b.style.cssText = `position:absolute;left:${10 + off}px;bottom:${k * 39}px;width:120px;height:35px;border-radius:9px;background:linear-gradient(160deg,rgba(134,239,172,.95),rgba(34,197,94,.85) 55%,rgba(21,128,61,.9));border:1.5px solid rgba(255,255,255,.6);box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 6px 14px -6px #000`;
    tower.appendChild(b);
    A(b, [{ opacity: 0, transform: 'translateY(-420px)' }, { opacity: 1, transform: 'translateY(0)', offset: .75 }, { opacity: 1, transform: 'translateY(-6px) scaleY(.96)', offset: .88 }, { opacity: 1, transform: 'translateY(0)' }], t - .3, .45, 'cubic-bezier(.45,0,.8,.6)');
    A('#repN', [{ scale: '1' }, { scale: '1.35', offset: .3 }, { scale: '1' }], t, .4, 'ease-out');
  });
  tick(t => { $('#repN').textContent = repT.filter(x => t >= x).length; });
  A('#bodyIn', [{ transform: 'none' }, { transform: 'translateY(30px) rotate(-6deg)', offset: .45 }, { transform: 'none' }], 50.75, .7, 'ease-in-out', { iterations: 8 });
  A('#hint', [{ opacity: 0, transform: 'translateY(20px) scale(.8)' }, { opacity: 1, transform: 'none' }], 52.9, .4, BACK);
  A('#hint', [{ opacity: 1 }, { opacity: 0 }], 54.0, .3, 'linear');
  caption('#c7', 50.05, 57.35);

  // Backup
  screen('#scrBk', 57.6, null, 'fade');
  A('#tgl', [{ backgroundColor: 'rgba(255,255,255,.18)' }, { backgroundColor: '#22C55E' }], 58.5, .3, 'linear');
  A('#tgl > div', [{ transform: 'translateX(20px)' }, { transform: 'translateX(0)' }], 58.5, .35, EO);
  caption('#c8', 57.85, 61.4);
  pop('#phOld', 58.3, .5); pop('#cloud', 58.9, .6); pop('#phNew', 60.0, .6);
  $$('#fl1 i').forEach((d, i) => A(d, [{ opacity: .15 }, { opacity: 1 }, { opacity: .15 }], 58.6 + i * .15, .6, 'ease-in-out', { iterations: 3 }));
  $$('#fl2 i').forEach((d, i) => A(d, [{ opacity: .15 }, { opacity: 1 }, { opacity: .15 }], 59.5 + i * .15, .6, 'ease-in-out', { iterations: 3 }));

  // ---------- S9 captain ----------
  fin('#s9a', 62.1, .7, 30);
  A('#s9b', [{ opacity: 0, transform: 'scale(1.3)', filter: 'blur(18px)' }, { opacity: 1, transform: 'scale(1)', filter: 'blur(0)' }], 62.6, .9);
  fin('#s9c', 63.6, .8, 30);
  A('#s9w', [{ opacity: 1, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(1.3)' }], 65.35, .7, EI);

  // ---------- Dashboard ----------
  A('#brw', [{ opacity: 0, transform: 'perspective(2200px) translateY(160px) rotateX(16deg) scale(.9)' }, { opacity: 1, transform: 'perspective(2200px) translateY(0) rotateX(0deg) scale(1)' }], 65.95, 1.3);
  A('#brw', [{ opacity: 1, transform: 'perspective(2200px) translateY(0) rotateX(0deg) scale(1)' }, { opacity: 0, transform: 'perspective(2200px) translateY(0) rotateX(0deg) scale(.88)' }], 91.5, .6, EI);
  const navOn = (id, tin, tout) => { A(`#${id} .act`, [{ opacity: 0 }, { opacity: 1 }], tin, .3, 'linear'); A(`#${id}`, [{ color: '#A9B8AF' }, { color: '#F2F7F3' }], tin, .3, 'linear'); if (tout) { A(`#${id} .act`, [{ opacity: 1 }, { opacity: 0 }], tout, .3, 'linear'); A(`#${id}`, [{ color: '#F2F7F3' }, { color: '#A9B8AF' }], tout, .3, 'linear'); } };
  navOn('navM', 66.5, 74.0); navOn('navT', 74.0, 80.0); navOn('navP', 80.0, 86.0); navOn('navS', 86.0);
  const pane = (id, tin, tout) => { A(id, [{ opacity: 0, transform: 'translateY(24px)' }, { opacity: 1, transform: 'none' }], tin, .6); if (tout) A(id, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-16px)' }], tout, .35, EI); };
  pane('#pM', 66.4, 73.9); pane('#pT', 74.2, 79.9); pane('#pP', 80.2, 85.9); pane('#pS', 86.2);
  A('#pM .mr', [{ opacity: 0, transform: 'translateX(-30px)' }, { opacity: 1, transform: 'none' }], 66.9, .5, EO, { stagger: .08 });
  // cursor path
  const cur = $('#cur');
  const C = [[0, [720, 640]], [67.5, [720, 640]], [68.35, P.add], [70.35, P.add], [70.55, P.mk], [74.6, P.mk], [75.25, P.edit], [76.0, P.edit], [76.5, P.apply], [86.6, P.apply], [87.2, P.sw2], [88.4, P.sw2], [88.8, P.sw3], [89.6, P.sw3], [90.0, P.sw5], [90.8, P.sw5], [91.2, P.sw1]];
  for (let i = 1; i < C.length; i++) { const [t0, a] = C[i - 1], [t1, b] = C[i]; if (a === b && t0 !== 0) continue; A(cur, [{ transform: `translate(${a[0] - 6}px,${a[1] - 4}px)` }, { transform: `translate(${b[0] - 6}px,${b[1] - 4}px)` }], t0, Math.max(.01, t1 - t0), EIO); }
  A(cur, [{ opacity: 0 }, { opacity: 1 }], 67.4, .3, 'linear');
  A(cur, [{ opacity: 1 }, { opacity: 0 }], 77.2, .3, 'linear');
  A(cur, [{ opacity: 0 }, { opacity: 1 }], 86.5, .3, 'linear');
  A(cur, [{ opacity: 1 }, { opacity: 0 }], 91.4, .3, 'linear');
  const clickAt = (t, btn) => { A(cur.querySelector('.tap'), [{ opacity: 0, transform: 'scale(.3)' }, { opacity: 1, transform: 'scale(.8)', offset: .25 }, { opacity: 0, transform: 'scale(1.6)' }], t, .55, 'ease-out'); if (btn) A(btn, [{ scale: '1' }, { scale: '.94', offset: .3 }, { scale: '1' }], t, .35, 'ease-out'); };
  clickAt(68.45, '#addBtn');
  A('#mod', [{ opacity: 0, visibility: 'hidden' }, { opacity: 1, visibility: 'visible' }], 68.65, .3, 'linear');
  A('#mod', [{ opacity: 1 }, { opacity: 0 }], 73.6, .3, 'linear');
  A('#mbox', [{ opacity: 0, transform: 'scale(.92) translateY(20px)' }, { opacity: 1, transform: 'none' }], 68.7, .5, BACK);
  A('#mbox', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'scale(.94)' }], 70.75, .3, EI);
  const names = 'يوسف خالد\nمروان طارق\nكريم مصطفى';
  tick(t => { const n = Math.round(names.length * clamp((t - 69.0) / 1.3)); $('#taTxt').textContent = names.slice(0, n); $('#caret').style.opacity = (Math.floor(t * 2.5) % 2 || t < 70.4) ? 1 : 0; });
  clickAt(70.6, '#mkBtn');
  const qrs = $('#qrs');
  [['يوسف خالد', 'K7P2QX', 11], ['مروان طارق', 'M4TR8Z', 22], ['كريم مصطفى', 'Q9WD3H', 33]].forEach(([n, c, s], i) => {
    const d = document.createElement('div'); d.className = 'qr';
    d.innerHTML = `<div style="font:800 14px Cairo;color:#15803D">Power Gym · انضم لجيمك</div><div style="width:150px;height:150px">${qrSvg(s)}</div><div class="c">${c}</div><div class="nm">${n}</div>`;
    qrs.appendChild(d);
    A(d, [{ opacity: 0, transform: 'translateY(60px) rotate(-6deg) scale(.8)' }, { opacity: 1, transform: 'none' }], 70.9 + i * .14, .7, BACK);
  });
  $('#cqr').innerHTML = qrSvg(33);
  caption('#d1', 66.5, 73.9);

  // companion phone
  A('#cphRig', [{ opacity: 0, transform: 'translateY(420px) rotate(-10deg)' }, { opacity: 1, transform: 'translateY(0) rotate(4deg)' }], 71.35, .8);
  A('#cphRig', [{ opacity: 1, transform: 'translateY(0) rotate(4deg)' }, { opacity: 0, transform: 'translateY(420px) rotate(-6deg)' }], 73.7, .5, EI);
  A('#cphRig', [{ opacity: 0, transform: 'translateY(420px) rotate(-10deg)' }, { opacity: 1, transform: 'translateY(0) rotate(4deg)' }], 77.5, .7, EO, { fill: 'forwards' });
  A('#cphRig', [{ opacity: 1, transform: 'translateY(0) rotate(4deg)' }, { opacity: 0, transform: 'translateY(420px) rotate(-6deg)' }], 79.7, .5, EI);
  A('#cphRig', [{ opacity: 0, transform: 'translateY(420px) rotate(-10deg)' }, { opacity: 1, transform: 'translateY(0) rotate(4deg)' }], 86.4, .7, EO, { fill: 'forwards' });
  A('#cphRig', [{ opacity: 1, transform: 'translateY(0) rotate(4deg)' }, { opacity: 0, transform: 'translateY(420px) rotate(-6deg)' }], 91.4, .5, EI);
  A('#scanLine', [{ transform: 'translateY(0)' }, { transform: 'translateY(155px)' }, { transform: 'translateY(0)' }], 71.6, 1.0, 'ease-in-out');
  A('#cScan', [{ opacity: 1 }, { opacity: 0 }], 72.65, .25, 'linear');
  A('#cJoin', [{ opacity: 0, transform: 'scale(1.05)' }, { opacity: 1, transform: 'none' }], 72.65, .4);
  A('#cJoin', [{ opacity: 1 }, { opacity: 0 }], 74.5, .1, 'linear');
  A('#cJoin .logo', [{ transform: 'scale(0) rotate(-20deg)' }, { transform: 'scale(1) rotate(0)' }], 72.75, .6, BACK);
  A('#cToday', [{ opacity: 0 }, { opacity: 1 }], 74.6, .1, 'linear');
  A('#cToast', [{ opacity: 0, transform: 'translateY(-150%)' }, { opacity: 1, transform: 'none' }], 78.15, .6, BACK);
  A('#cToast', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-150%)' }], 81, .3, EI);

  // templates
  caption('#d2', 74.3, 79.9);
  clickAt(75.35);
  A('#editRow .hlrow', [{ opacity: 0 }, { opacity: 1 }], 75.35, .3, 'linear');
  A('#tg1', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-20px)' }], 75.55, .3, EO);
  A('#tg2', [{ opacity: 0, transform: 'translateY(20px)' }, { opacity: 1, transform: 'none' }], 75.55, .35, BACK);
  clickAt(76.55, '#applyBtn');
  const ap = $('#applied');
  const avc = ['#86EFAC', '#93C5FD', '#C4B5FD', '#FBBF24', '#F9A8D4', '#86EFAC', '#93C5FD', '#FBBF24', '#C4B5FD', '#86EFAC', '#F9A8D4', '#93C5FD'];
  const ltr = 'أمسعنيكحطرهل';
  avc.forEach((c, i) => { const a = document.createElement('div'); a.className = 'av'; a.style.cssText = `background:${c};width:34px;height:34px;margin-inline-start:-8px;border:2px solid #0A120E;font-size:13px`; a.textContent = ltr[i]; ap.appendChild(a); A(a, [{ opacity: 0, transform: 'scale(0)' }, { opacity: 1, transform: 'scale(1)' }], 76.8 + i * .05, .4, BACK); });
  const okc = document.createElement('span'); okc.className = 'pill p-ok'; okc.style.cssText = 'margin-inline-start:12px;height:34px;font-size:15px'; okc.innerHTML = '✓ اتطبّق على <span class="n">&nbsp;12&nbsp;</span> متدرب'; ap.appendChild(okc);
  pop(okc, 77.5, .5);

  // progress
  caption('#d3', 80.3, 85.9);
  const kp = [['#pk1', 14, v => Math.round(v)], ['#pk2', 87, v => Math.round(v) + '%'], ['#pk3', 9, v => Math.round(v)], ['#pk4', 18.6, v => v.toFixed(1)]];
  tick(t => { const p = ease(clamp((t - 80.6) / 1.3)); kp.forEach(([s, v, f]) => ($(s).textContent = f(v * p))); });
  A('#pk .kp', [{ opacity: 0, transform: 'translateY(30px)' }, { opacity: 1, transform: 'none' }], 80.45, .6, BACK, { stagger: .08 });
  const vals = [16, 17.5, 18, 20, 20, 22.5, 24, 26];
  const pts = vals.map((v, i) => [70 + i * 115, 270 - 17.5 * (v - 14)]);
  let d = `M${pts[0][0]} ${pts[0][1]}`;
  for (let i = 1; i < pts.length; i++) { const [x0, y0] = pts[i - 1], [x1, y1] = pts[i]; const mx = (x0 + x1) / 2; d += ` C${mx} ${y0} ${mx} ${y1} ${x1} ${y1}`; }
  $('#line').setAttribute('d', d);
  $('#area').setAttribute('d', d + ` L${pts[pts.length - 1][0]} 290 L${pts[0][0]} 290 Z`);
  const L = $('#line').getTotalLength();
  $('#line').style.strokeDasharray = L;
  A('#line', [{ strokeDashoffset: L }, { strokeDashoffset: 0 }], 81.0, 2.0, EIO);
  const g = $('#pts');
  pts.forEach(([x, y], i) => { const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle'); c.setAttribute('cx', x); c.setAttribute('cy', y); c.setAttribute('r', i === pts.length - 1 ? 10 : 7); c.setAttribute('fill', i === pts.length - 1 ? '#4ADE80' : '#0A120E'); c.setAttribute('stroke', '#22C55E'); c.setAttribute('stroke-width', 4); c.style.transformBox = 'fill-box'; c.style.transformOrigin = 'center'; g.appendChild(c); A(c, [{ opacity: 0, transform: 'scale(0)' }, { opacity: 1, transform: 'scale(1)' }], 81.0 + 2.0 * (i / (pts.length - 1)) * .95, .4, BACK); });
  tick(t => { const p = clamp((t - 81.0) / 2.0); $('#clipR').setAttribute('width', 900 * (p < .5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2)); });
  const rec = document.createElementNS('http://www.w3.org/2000/svg', 'g');
  rec.innerHTML = `<rect x="${pts[7][0] - 150}" y="${pts[7][1] - 62}" width="140" height="40" rx="20" fill="#22C55E"/><text x="${pts[7][0] - 80}" y="${pts[7][1] - 36}" text-anchor="middle" font-family="Cairo" font-weight="800" font-size="17" fill="#04210F">رقم جديد 🏆</text>`;
  g.appendChild(rec); rec.style.transformBox = 'fill-box'; rec.style.transformOrigin = 'center';
  pop(rec, 83.1, .6);

  // brand colour
  caption('#d4', 86.3, 91.4);
  const cph = $('#cph');
  const swRing = (n, tin, tout) => { A(`#sw${n} .ring`, [{ opacity: 0, transform: 'scale(.7)' }, { opacity: 1, transform: 'none' }], tin, .3, BACK); if (tout) A(`#sw${n} .ring`, [{ opacity: 1 }, { opacity: 0 }], tout, .2, 'linear'); };
  A('#sw1 .ring', [{ opacity: 1 }, { opacity: 1 }], 0, .01, 'linear'); A('#sw1 .ring', [{ opacity: 1 }, { opacity: 0 }], 87.4, .2, 'linear');
  $('#sw1 .ring').__seen = new Set(['opacity', 'transform']);
  const brandTo = (from, to, onFrom, onTo, t) => { A(cph, [{ '--brand': from, '--on-p': onFrom }, { '--brand': to, '--on-p': onTo }], t, .5, 'ease-in-out'); A('#gymLogo', [{ background: `linear-gradient(135deg,${from},#0b1310)` }, { background: `linear-gradient(135deg,${to},#0b1310)` }], t, .5, 'linear'); };
  clickAt(87.35, '#sw2'); swRing(2, 87.4, 88.6); brandTo('#22C55E', '#2563EB', '#04210F', '#FFFFFF', 87.45);
  clickAt(88.75, '#sw3'); swRing(3, 88.8, 89.9); brandTo('#2563EB', '#F59E0B', '#FFFFFF', '#1C1203', 88.85);
  clickAt(89.95, '#sw5'); swRing(5, 90.0, 91.1); brandTo('#F59E0B', '#A855F7', '#1C1203', '#FFFFFF', 90.05);
  clickAt(91.15, '#sw1'); swRing(1, 91.2); brandTo('#A855F7', '#22C55E', '#FFFFFF', '#04210F', 91.25);
  A('#cToday', [{ opacity: 1 }, { opacity: 1 }], 86.0, .01, 'linear');

  // ---------- recap + outro ----------
  const feats = [
    ['التمرينة الجاية', '📅'], ['اقتراح الوزن', '↑'], ['تسجيل بضغطة', '✓'], ['مؤقت الراحة', '⏱'], ['أرقام جديدة', '🏆'],
    ['المستويات', '💪'], ['صور وفيديو', '▶'], ['ألعاب الحركة', '🎮'], ['نسخة احتياطية', '☁'], ['عربي و English', '🌐'],
    ['الأعضاء والأكواد', '👥'], ['الخطط والقوالب', '📋'], ['تقدّم المتدربين', '📈'], ['لون الجيم', '🎨'], ['فاتح وغامق', '🌗'],
  ];
  const rc = $('#recap');
  const ttl = document.createElement('div'); ttl.className = 'abs'; ttl.style.cssText = 'left:0;right:0;top:250px;text-align:center;font:800 76px Cairo'; ttl.innerHTML = 'كل ده.. <span class="green glow">في عزم</span>'; rc.appendChild(ttl);
  fin(ttl, 92.0, .7, 40);
  A(ttl, [{ opacity: 1 }, { opacity: 0 }], 95.0, .4, 'ease-in');
  rngS = 5;
  feats.forEach(([t, ic], i) => {
    const col = i % 5, row = Math.floor(i / 5);
    const x = 1920 - (190 + col * 345) - 320, y = 420 + row * 100;
    const c = document.createElement('div'); c.className = 'chip abs';
    c.style.cssText = `left:${x}px;top:${y}px;width:320px;height:76px;justify-content:center;font-size:28px;${i >= 10 && i < 14 ? 'border-color:rgba(34,197,94,.5);background:rgba(34,197,94,.12)' : ''}`;
    c.innerHTML = `<span style="font-size:28px">${ic}</span>${t}`;
    rc.appendChild(c);
    const sx = (rnd() - .5) * 900, sy = (rnd() - .5) * 600;
    A(c, [{ opacity: 0, transform: `translate(${sx}px,${sy}px) scale(.5) rotate(${(rnd() - .5) * 40}deg)` }, { opacity: 1, transform: 'none' }], 92.2 + i * .05, .8, EO);
    const cx = 960 - (x + 160), cy = 540 - (y + 38);
    A(c, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: `translate(${cx}px,${cy}px) scale(.2)` }], 95.0 + i * .025, .55, EI);
  });
  A('#flash', [{ opacity: 0 }, { opacity: .8, offset: .3 }, { opacity: 0 }], 95.6, .9, 'ease-out', { fill: 'forwards' });
  A('#oLogo', [{ opacity: 0, transform: 'scale(.4)', filter: 'blur(20px)' }, { opacity: 1, transform: 'scale(1)', filter: 'blur(0)' }], 95.7, 1.0, BACK);
  A('#oWord', [{ opacity: 0, transform: 'translateY(50px)', filter: 'blur(12px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], 96.15, .9);
  fin('#oTag', 96.7, .8, 30);
  A('#oSub .chip', [{ opacity: 0, transform: 'translateY(30px)' }, { opacity: 1, transform: 'none' }], 97.3, .7, BACK, { stagger: .12 });
  fin('#oUrl', 97.9, .8, 20);
  fin('#credit', 98.2, .8, 0);
  A('#oLogo', [{ translate: '0 0' }, { translate: '0 -10px' }, { translate: '0 0' }], 97, 3, 'ease-in-out', { iterations: 2 });
  // keep the flash element visible in s14: move it
  // scenes
}

const scenes = [...document.querySelectorAll('.scene')];
function seek(t) {
  for (const s of scenes) s.style.visibility = (t >= +s.dataset.in && t < +s.dataset.out) ? 'visible' : 'hidden';
  // the flash lives in s1; the outro flash needs it visible too
  const fl = document.getElementById('flash');
  fl.style.visibility = (t < 8.6 || (t > 95.5 && t < 96.6)) ? 'visible' : 'hidden';
  for (const a of document.getAnimations()) { a.pause(); a.currentTime = t * 1000; }
  for (const f of TK) f(t);
}
window.__ready = document.fonts.ready.then(() => { build(); seek(0); return true; });
window.__seek = seek;
window.__D = D;
