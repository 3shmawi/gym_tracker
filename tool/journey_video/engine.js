// Journey series engine: builds one episode (window.EPISODES, ?ep=03) on the
// template in journey.html. Every movement is a paused Web Animation or a
// tick function of t, so __seek(t) puts the page at any exact time (same
// approach as docs/brand/promo_video/timeline.js).
const Q = new URLSearchParams(location.search);
const EP = window.EPISODES.find(e => e.id === (Q.get('ep') || '00'));
const S = window.SERIES;
const INTRO = 2, OUTRO = 4;
const EO = 'cubic-bezier(.16,1,.3,1)', EIO = 'cubic-bezier(.65,0,.35,1)', BACK = 'cubic-bezier(.34,1.56,.64,1)';
const $ = (s, r = document) => (typeof s === 'string' ? r.querySelector(s) : s);
const $$ = (s, r = document) => (typeof s === 'string' ? [...r.querySelectorAll(s)] : s instanceof Element ? [s] : [...s]);
const TK = [], HITS = [], WIN = [];
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const easeOut = x => 1 - Math.pow(1 - x, 3);
const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function A(target, kf, at, dur, ease = EO, o = {}) {
  $$(target).forEach((el, i) => {
    const props = Object.keys(kf[0]).filter(k => !['offset', 'easing'].includes(k));
    el.__seen = el.__seen || new Set();
    const first = props.every(p => !el.__seen.has(p));
    props.forEach(p => el.__seen.add(p));
    const a = el.animate(kf, { delay: (at + (o.stagger || 0) * i) * 1000, duration: dur * 1000, easing: ease, fill: o.fill || (first ? 'both' : 'forwards'), iterations: o.iterations || 1 });
    a.pause();
  });
}
const fin = (el, at, dur = .7, y = 40) => A(el, [{ opacity: 0, transform: `translateY(${y}px)` }, { opacity: 1, transform: 'none' }], at, dur);
const pop = (el, at, dur = .6, o) => A(el, [{ opacity: 0, transform: 'scale(.6)' }, { opacity: 1, transform: 'scale(1)' }], at, dur, BACK, o);

// Words: split on spaces only, so Arabic letters stay joined. *x y* = accent.
function words(text) {
  let acc = false;
  const toks = [];
  for (let tok of String(text).split(/\s+/).filter(Boolean)) {
    const open = tok.startsWith('*');
    const close = tok.slice(open ? 1 : 0).includes('*');
    tok = tok.replace(/\*/g, '');
    if (open) acc = true;
    const lat = /[A-Za-z0-9]/.test(tok) && !/[\u0600-\u06FF]/.test(tok);
    const prev = toks[toks.length - 1];
    // consecutive Latin words stay one LTR run ("GitHub Actions", "YouTube API")
    if (lat && prev && prev.lat && prev.acc === acc && /[A-Za-z]/.test(tok + prev.tok)) prev.tok += ' ' + tok;
    else toks.push({ tok, acc, lat });
    if (close) acc = false;
  }
  const html = toks.map(({ tok, acc, lat }) => {
    const cls = `w${acc ? ' acc' : ''}`;
    // trailing punctuation after a Latin run belongs to the RTL sentence, not inside the LTR run
    const m = lat && tok.match(/^(.*[A-Za-z0-9)])([.,:!?…]+)$/);
    if (m) return `<span class="${cls}"><span class="lat">${esc(m[1])}</span>${esc(m[2])}</span>`;
    return `<span class="${cls}${lat ? ' lat' : ''}">${esc(tok)}</span>`;
  }).join(' ');
  return `<span class="ws">${html}</span>`;  // one inline box, so flex parents keep the spaces
}
function reveal(root, at, budget = 1.2) {
  const ws = $$('.w', root);
  const per = Math.min(.16, budget / Math.max(1, ws.length));
  A(ws, [{ opacity: 0, transform: 'translateY(26px)', filter: 'blur(8px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], at, .55, EO, { stagger: per });
  return at + per * ws.length;
}
function count(el, n, at, dur, { pre = '', suf = '', dec = 0 } = {}) {
  TK.push(t => {
    const v = n * easeOut(clamp((t - at) / dur));
    el.textContent = pre + v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec }) + suf;
  });
  HITS.push(at + dur);
}
function textBlock(s) {
  const m = h('div', 'mid');
  if (s.kicker) m.appendChild(h('div', 'kicker', words(s.kicker)));
  m.appendChild(h('div', s.type === 'hook' ? 'big' : 'say', words(s.text)));
  if (s.sub) m.appendChild(h('div', 'sub', words(s.sub)));
  return m;
}
function topCap(s) {
  const top = h('div', 'top');
  if (s.kicker) top.appendChild(h('div', 'kicker', words(s.kicker)));
  if (s.caption) top.appendChild(h('div', 'cap', words(s.caption)));
  return top;
}
function revealTop(top, t0) {
  let t = t0 + .15;
  $$('.kicker', top).forEach(k => { pop(k, t, .5); t += .2; });
  return reveal(top, t, .9);
}

// ---------- code highlighting (small, per line) ----------
const KW = /^(final|const|static|return|if|await|async|class|extends|null|true|false|var|void|new|this|super|-keep|import)$/;
function hl(line) {
  const out = [];
  let m, rest = line;
  const push = (txt, cls) => [...txt].forEach(ch => out.push([ch, cls]));
  while (rest.length) {
    if ((m = rest.match(/^(\/\/.*|#.*)/))) { push(m[0], 'c'); rest = rest.slice(m[0].length); continue; }
    if ((m = rest.match(/^('[^']*'|"[^"]*")/))) { push(m[0], 's'); rest = rest.slice(m[0].length); continue; }
    if ((m = rest.match(/^-?[A-Za-z_$][\w$]*/))) {
      const w = m[0], nx = rest[w.length];
      push(w, KW.test(w) ? 'k' : /^[A-Z]/.test(w) ? 'ty' : nx === '(' ? 'fn' : '');
      rest = rest.slice(w.length); continue;
    }
    if ((m = rest.match(/^\d+(\.\d+)?/))) { push(m[0], 'nm'); rest = rest.slice(m[0].length); continue; }
    push(rest[0], ''); rest = rest.slice(1);
  }
  return out;
}

// ---------- scene builders: (s, t0, d) → element ----------
const B = {};
B.hook = B.say = (s, t0, d) => {
  const el = textBlock(s);
  let t = t0 + .15;
  $$('.kicker', el).forEach(k => { pop(k, t, .5); t += .25; });
  const main = $(s.type === 'hook' ? '.big' : '.say', el);
  t = reveal(main, t, s.type === 'hook' ? 1.3 : 1.5);
  HITS.push(t);
  const sub = $('.sub', el);
  if (sub) reveal(sub, t + .2, .9);
  return el;
};
B.counters = (s, t0, d) => {
  const el = h('div', 'mid');
  const top = topCap(s); top.style.position = 'static';
  if (s.kicker || s.caption) el.appendChild(top);
  const g = h('div', 'cgrid' + (s.items.length === 1 ? ' one' : ''));
  s.items.forEach((it, i) => {
    const tile = h('div', 'tile gl' + (s.items.length === 1 ? ' huge' : ''));
    const num = h('div', 'num', '0'), lbl = h('div', 'lbl', words(it.label));
    tile.append(num, lbl); g.appendChild(tile);
    const at = t0 + .45 + i * .32;
    A(tile, [{ opacity: 0, transform: 'translateY(60px) scale(.94)' }, { opacity: 1, transform: 'none' }], at, .6, EO);
    count(num, it.n, at + .1, Math.min(1.6, d * .35), it);
    reveal(lbl, at + .3, .5);
  });
  el.appendChild(g);
  if (s.note) { const n = h('div', 'note', words(s.note)); el.appendChild(n); reveal(n, t0 + .9 + s.items.length * .32, .8); }
  revealTop(top, t0);
  return el;
};
function phone(src, w) {
  const dv = h('div', 'dev'); dv.style.width = w + 'px'; dv.style.marginLeft = (-w / 2) + 'px';
  const im = h('img'); im.src = src; dv.appendChild(im); return dv;
}
B.shot = (s, t0, d) => {
  const el = h('div', ''); el.style.cssText = 'position:absolute;inset:0';
  const top = topCap(s); el.appendChild(top);
  const dv = phone(s.img, s.w || 500); dv.style.top = (s.y || 210) + 'px'; el.appendChild(dv);
  const lab = h('div', 'real', `<i></i>${words(s.label || 'شاشة حقيقية من التطبيق')}`); lab.style.top = (s.labelY || 1060) + 'px'; el.appendChild(lab);
  revealTop(top, t0);
  A(dv, [{ opacity: 0, transform: 'translateY(160px) rotate(-3deg)' }, { opacity: 1, transform: 'none' }], t0 + .35, .9, EO);
  A(dv, [{ scale: '1' }, { scale: '1.035' }], t0 + 1.2, Math.max(.5, d - 1.5), 'linear');
  pop(lab, t0 + 1.0, .5);
  HITS.push(t0 + .5);
  return el;
};
B.fan = (s, t0, d) => {
  const el = h('div', ''); el.style.cssText = 'position:absolute;inset:0';
  const top = topCap(s); el.appendChild(top);
  const pos = [{ x: 0, r: 0, w: 420, z: 3, y: 240 }, { x: 310, r: 8, w: 330, z: 2, y: 320 }, { x: -310, r: -8, w: 330, z: 2, y: 320 }];
  s.imgs.forEach((src, i) => {
    const p = pos[i]; const dv = phone(src, p.w);
    dv.style.top = p.y + 'px'; dv.style.zIndex = p.z; dv.style.padding = '10px'; dv.style.borderRadius = '48px';
    dv.querySelector('img').style.borderRadius = '38px';
    el.appendChild(dv);
    A(dv, [{ opacity: 0, transform: `translate(${p.x * .2}px,220px) rotate(0deg)` }, { opacity: 1, transform: `translate(${p.x}px,0) rotate(${p.r}deg)` }], t0 + .4 + (i ? .25 : 0), .9, EO);
  });
  if (s.label !== false) { const lab = h('div', 'real', `<i></i>${words(s.label || 'شاشات حقيقية من التطبيق')}`); lab.style.top = '1070px'; lab.style.zIndex = 5; el.appendChild(lab); pop(lab, t0 + 1.1, .5); }
  revealTop(top, t0); HITS.push(t0 + .5);
  return el;
};
B.code = (s, t0, d) => {
  const el = h('div', 'mid');
  const top = topCap(s); top.style.position = 'static'; el.appendChild(top);
  const card = h('div', 'code gl');
  card.appendChild(h('div', 'bar', `<span class="dots"><i></i><i></i><i></i></span>${esc(s.file)}`));
  const pre = h('pre');
  const spans = [];
  s.lines.forEach((ln, li) => {
    const row = h('span', 'ln' + (ln.startsWith('+ ') ? ' add' : ln.startsWith('- ') ? ' del' : '') + ((s.hl || []).includes(li) ? ' hl' : ''));
    hl(ln).forEach(([ch, cls]) => { const sp = h('span', cls || null); sp.textContent = ch; row.appendChild(sp); spans.push(sp); });
    if (!ln.length) spans.push(row);
    pre.appendChild(row);
  });
  card.appendChild(pre); el.appendChild(card);
  if (s.note) { const n = h('div', 'note', words(s.note)); el.appendChild(n); }
  const caret = h('span', 'caret');
  const tEnd = revealTop(top, t0);
  A(card, [{ opacity: 0, transform: 'translateY(60px)' }, { opacity: 1, transform: 'none' }], t0 + .3, .7);
  const ts = t0 + .9, dur = Math.min(d * .5, spans.length * .045);
  TK.push(t => {
    const k = Math.floor(spans.length * clamp((t - ts) / dur));
    spans.forEach((sp, i) => { if (!sp.classList.contains('ln')) sp.style.visibility = i < k ? 'visible' : 'hidden'; });
    const last = spans[Math.max(0, k - 1)];
    if (k === 0) pre.firstChild.prepend(caret);
    else if (last.classList.contains('ln')) last.appendChild(caret); else last.after(caret);
    caret.style.opacity = (t - ts > dur && Math.floor((t - ts - dur) * 2.2) % 2) ? 0 : 1;
  });
  HITS.push(ts + dur);
  if (s.note) reveal($('.note', el), ts + dur + .1, .8);
  return el;
};
B.diagram = (s, t0, d) => {
  const el = h('div', 'mid'); el.style.gap = '26px';
  const top = topCap(s); top.style.position = 'static'; if (s.kicker || s.caption) el.appendChild(top);
  const dia = h('div', 'dia');
  const gap = Math.min(1.15, (d - 1.8) / s.nodes.length);
  s.nodes.forEach((n, i) => {
    if (i) { const ar = h('div', 'arrow'); dia.appendChild(ar); A(ar, [{ transform: 'scaleY(0)' }, { transform: 'scaleY(1)' }], t0 + .7 + i * gap - .3, .3, EIO); }
    const nd = h('div', 'node gl' + (n.kind ? ' ' + n.kind : ''), `<div class="t">${words(n.t)}</div>${n.d ? `<div class="d">${words(n.d)}</div>` : ''}`);
    dia.appendChild(nd);
    A(nd, [{ opacity: 0, transform: 'translateY(40px) scale(.96)' }, { opacity: 1, transform: 'none' }], t0 + .7 + i * gap, .6, EO);
    HITS.push(t0 + .7 + i * gap);
  });
  el.appendChild(dia); revealTop(top, t0);
  return el;
};
B.options = (s, t0, d) => {
  const el = h('div', 'mid'); el.style.gap = '30px';
  const top = topCap(s); top.style.position = 'static'; el.appendChild(top);
  const box = h('div', 'opts');
  const gap = Math.min(1.1, (d - 1.8) / s.items.length);
  s.items.forEach((o, i) => {
    const it = h('div', 'opt gl ' + (o.ok ? 'good' : 'bad'), `<div class="mk">${o.ok ? '✓' : '✕'}</div><div><div class="t">${words(o.t)}</div>${o.d ? `<div class="d">${words(o.d)}</div>` : ''}</div>`);
    box.appendChild(it);
    A(it, [{ opacity: 0, transform: 'translateX(-80px)' }, { opacity: 1, transform: 'none' }], t0 + .8 + i * gap, .6, EO);
    pop($('.mk', it), t0 + 1.0 + i * gap, .5);
    HITS.push(t0 + 1.0 + i * gap);
  });
  el.appendChild(box); revealTop(top, t0);
  return el;
};
B.split = (s, t0, d) => {
  const el = h('div', 'mid');
  const top = topCap(s); top.style.position = 'static'; if (s.kicker || s.caption) el.appendChild(top);
  const sp = h('div', 'split');
  const mk = (k, o, tag) => h('div', `half gl ${k}`, `<div class="tag">${words(tag)}</div><div class="t">${words(o.t)}</div>${o.d ? `<div class="d">${words(o.d)}</div>` : ''}`);
  const b = mk('before', s.before, s.before.tag || 'قبل'), a = mk('after', s.after, s.after.tag || 'بعد');
  sp.append(b, a); el.appendChild(sp);
  revealTop(top, t0);
  A(b, [{ opacity: 0, transform: 'translateY(50px)' }, { opacity: 1, transform: 'none' }], t0 + .4, .6);
  const ta = t0 + d * .45;
  A(b, [{ opacity: 1 }, { opacity: .6 }], ta, .5, EIO);
  A(a, [{ opacity: 0, transform: 'translateY(50px) scale(.96)' }, { opacity: 1, transform: 'none' }], ta, .7, BACK);
  HITS.push(t0 + .4, ta);
  return el;
};
B.chips = (s, t0, d) => {
  const el = h('div', 'mid'); el.style.gap = '44px';
  const top = topCap(s); top.style.position = 'static'; el.appendChild(top);
  const box = h('div', 'chips');
  s.items.forEach(c => box.appendChild(h('div', 'chip gl', `<i></i><span>${words(c)}</span>`)));
  el.appendChild(box);
  const t = revealTop(top, t0);
  const per = Math.min(.35, (d - 2.2) / s.items.length);
  A($$('.chip', box), [{ opacity: 0, transform: 'translateY(40px) scale(.85)' }, { opacity: 1, transform: 'none' }], Math.max(t0 + .7, t - .3), .6, BACK, { stagger: per });
  s.items.forEach((_, i) => HITS.push(Math.max(t0 + .7, t - .3) + i * per));
  return el;
};
B.steps = (s, t0, d) => {
  const el = h('div', 'mid'); el.style.gap = '34px';
  const top = topCap(s); top.style.position = 'static'; el.appendChild(top);
  const box = h('div', 'steps');
  const per = Math.min(.7, (d - 2) / s.items.length);
  s.items.forEach((it, i) => {
    const st = h('div', 'step gl', `<div class="no">${esc(it.no || String(i + 1))}</div><div><div class="t">${words(it.t)}</div>${it.d ? `<div class="d">${words(it.d)}</div>` : ''}</div>`);
    box.appendChild(st);
    A(st, [{ opacity: 0, transform: 'translateX(-70px)' }, { opacity: 1, transform: 'none' }], t0 + .8 + i * per, .55, EO);
    HITS.push(t0 + .8 + i * per);
  });
  el.appendChild(box); revealTop(top, t0);
  return el;
};
const MONTHS = { '10': 'أكتوبر', '11': 'نوفمبر', '12': 'ديسمبر' };
const dayLabel = iso => `${+iso.slice(8, 10)} ${MONTHS[iso.slice(5, 7)]}`;
B.timeline = (s, t0, d) => {
  const el = h('div', 'mid'); el.style.gap = '30px';
  const top = topCap(s); top.style.position = 'static'; el.appendChild(top);
  const days = []; for (let x = new Date('2026-10-31T12:00:00Z'); x <= new Date('2026-11-15T12:00:00Z'); x = new Date(+x + 864e5)) days.push(x.toISOString().slice(0, 10));
  const on = n => !s.highlight || s.highlight.some(([a, b]) => n >= a && n <= b);
  const tl = h('div', 'tl'); const cw = 960 / days.length;
  const cols = days.map((dd, i) => { const c = h('div', 'col'); c.style.left = (960 - (i + .5) * cw - 22) + 'px'; tl.appendChild(c); return c; });
  tl.appendChild(h('div', 'axis'));
  [[0, 'right:0'], [8, 'left:50%;transform:translateX(-50%)'], [days.length - 1, 'left:0']].forEach(([i, css]) => { const l = h('div', 'dl', words(dayLabel(days[i]))); l.style.cssText += css; tl.appendChild(l); });
  const prs = [...window.PRS].sort((a, b) => a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : a[0] - b[0]);
  const ts = t0 + .9, dur = Math.min(d * .55, 3.2);
  const dots = prs.map(([n, day]) => { const dt = h('div', 'dot' + (on(n) ? ' on' : '')); cols[days.indexOf(day)].appendChild(dt); return dt; });
  A(dots, [{ opacity: 0, transform: 'scale(0)' }, { opacity: 1, transform: 'scale(1)' }], ts, .3, BACK, { stagger: dur / dots.length });
  const cnt = h('div', 'tlcount', ''); const lbl = h('div', 'note', words(s.countLabel || 'PR اتدمج'));
  const nOn = prs.filter(p => on(p[0])).length;
  count(cnt, nOn, ts, dur);
  el.append(tl, cnt, lbl);
  revealTop(top, t0); reveal(lbl, ts + .3, .6);
  return el;
};
B.promo = (s, t0, d) => {
  const el = h('div', 'mid'); el.style.gap = '40px'; el.style.padding = '0';
  const top = topCap(s); top.style.position = 'static'; el.appendChild(top);
  // the promo is 1920×1080: show its centre at 0.8× in a 1080-wide window
  const box = h('div', 'promo'); const fr = h('iframe'); fr.src = 'promo/index.html'; box.appendChild(fr); el.appendChild(box);
  if (s.note) { const n = h('div', 'note', words(s.note)); el.appendChild(n); reveal(n, t0 + 1, .8); }
  revealTop(top, t0);
  A(box, [{ opacity: 0, transform: 'scale(.92)' }, { opacity: 1, transform: 'none' }], t0 + .3, .7);
  WIN.push(fr.__ready = new Promise(res => fr.addEventListener('load', () => fr.contentWindow.__ready.then(res))));
  TK.push(t => { if (t >= t0 && t < t0 + d && fr.contentWindow && fr.contentWindow.__seek) fr.contentWindow.__seek(s.from + (t - t0)); });
  return el;
};

// ---------- intro / outro / header ----------
function intro() {
  const el = $('#intro');
  const m = h('div', 'mid'); m.style.top = '370px'; m.style.height = '1150px'; m.style.inset = 'auto'; m.style.left = '0'; m.style.right = '0'; m.style.position = 'absolute'; m.style.gap = '40px';
  const lg = h('div', 'logo', '<img src="assets/icon.png" alt="">'); const ring = h('div', 'ring');
  const wrap = h('div', ''); wrap.style.position = 'relative'; wrap.append(ring, lg);
  const nm = h('div', 'series', words(S.name.replace(/(النهارده)/, '*$1*')));
  const ep = h('div', 'epbig', words(EP.n ? `حلقة ${EP.n} · ${EP.title}` : EP.title));
  m.append(wrap, nm, ep); el.appendChild(m);
  A(lg, [{ opacity: 0, transform: 'scale(.3) rotate(-12deg)' }, { opacity: 1, transform: 'none' }], .05, .6, BACK);
  A(ring, [{ opacity: .9, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(2.4)' }], .35, .9, 'ease-out');
  reveal(nm, .3, .5); reveal(ep, .7, .3);
  A(m, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'scale(.92)' }], 1.72, .28, 'ease-in');
  A('#flash', [{ opacity: 0 }, { opacity: .55, offset: .4 }, { opacity: 0 }], 1.8, .5, 'ease-out');
  HITS.push(.05);
}
function outro(t0) {
  const el = $('#outro');
  const m = h('div', 'mid'); Object.assign(m.style, { position: 'absolute', top: '370px', height: '1150px', left: '0', right: '0', inset: 'auto', gap: '42px' });
  const nx = h('div', 'say', words(EP.cta)); nx.style.fontSize = '68px';
  const lg = h('div', 'logo', '<img src="assets/icon.png" alt="">'); lg.style.cssText = 'width:170px;height:170px;border-radius:42px';
  const hd = h('div', 'handle', esc(S.handle)); const url = h('div', 'url', esc(S.url));
  const fb = h('div', 'cta', words(S.follow));
  m.append(nx, lg, hd, fb, url); el.appendChild(m);
  reveal(nx, t0 + .1, .9);
  pop(lg, t0 + .9, .6); fin(hd, t0 + 1.2, .6, 30); pop(fb, t0 + 1.5, .6); fin(url, t0 + 1.8, .6, 20);
  A(fb, [{ scale: '1' }, { scale: '1.05' }, { scale: '1' }], t0 + 2.4, 1, 'ease-in-out', { iterations: 1 });
  HITS.push(t0 + .1, t0 + 1.5);
}
function header(D) {
  const n = EP.n;
  $('#epchip').innerHTML = n ? `حلقة <b class="n">${n}</b> من <span class="n">${S.total}</span>` : `<b>تريلر</b>`;
  $('#datechip').innerHTML = words(EP.dates || '');
  const segs = $('#segs');
  for (let i = 1; i <= S.total; i++) {
    const sg = h('div', 'seg' + (n && i < n ? ' done' : ''), '<div class="fill"></div>'); segs.appendChild(sg);
    if (i === n) A($('.fill', sg), [{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], INTRO, D - INTRO - OUTRO, 'linear');
  }
  A('#hdr', [{ opacity: 0, transform: 'translateY(-30px)' }, { opacity: 1, transform: 'none' }], INTRO - .1, .5);
  A('#hdr', [{ opacity: 1 }, { opacity: 0 }], D - OUTRO - .1, .4, 'ease-in');
}

// ---------- cover (still image, ?cover=1) ----------
function cover() {
  const st = $('#stage');
  $('#hdr').style.top = '236px';
  const m = h('div', ''); m.style.cssText = 'position:absolute;left:60px;right:60px;top:380px;display:flex;flex-direction:column;align-items:center;gap:26px;text-align:center;z-index:5';
  m.appendChild(h('div', 'cover-num', EP.n ? String(EP.n).padStart(2, '0') : '▶'));
  m.appendChild(h('div', 'cover-title', words(EP.coverTitle || EP.title)));
  m.appendChild(h('div', 'sub', words(EP.coverSub || '')));
  st.appendChild(m);
  const dv = phone(EP.coverImg, 560); dv.style.top = '1180px'; dv.style.transform = 'rotate(-6deg)'; dv.style.zIndex = 2; st.appendChild(dv);
  const sh = h('div', ''); sh.style.cssText = 'position:absolute;left:0;right:0;bottom:0;height:520px;background:linear-gradient(transparent,#07120Cdd 70%);z-index:3'; st.appendChild(sh);
}

// ---------- build + seek ----------
const plan = [];
function build() {
  document.documentElement.style.setProperty('--hue', (EP.hue || 0) + 'deg');
  let t = INTRO;
  for (const s of EP.scenes) {
    const el = B[s.type](s, t, s.d);
    const wrap = h('div', 'scene'); wrap.appendChild(el); wrap.dataset.in = t; wrap.dataset.out = t + s.d; $('#scenes').appendChild(wrap);
    if (s.type !== 'hook' || t > INTRO) A(wrap, [{ opacity: 0 }, { opacity: 1 }], t, .3, 'ease-out');
    A(wrap, [{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateY(-50px)', filter: 'blur(6px)' }], t + s.d - .32, .32, 'ease-in');
    plan.push({ type: s.type, t0: t, d: s.d, key: +(t + s.d * .82).toFixed(2) });
    t += s.d;
  }
  const D = t + OUTRO;
  $('#intro').dataset.in = 0; $('#intro').dataset.out = INTRO;
  $('#outro').dataset.in = t; $('#outro').dataset.out = D;
  intro(); outro(t); header(D);
  window.__D = D;
  window.__plan = { id: EP.id, D, intro: INTRO, cuts: [INTRO, ...plan.map(p => p.t0 + p.d)], hits: [...new Set(HITS.map(x => +x.toFixed(2)))].sort((a, b) => a - b), seed: EP.seed || 1, key: EP.key || 0, scenes: plan };
  window.__keyTimes = [1.1, ...plan.map(p => p.key), +(D - .6).toFixed(2)];
}
const layers = () => [...document.querySelectorAll('.scene,#intro,#outro')];
function seek(t) {
  for (const s of layers()) s.style.visibility = (t >= +s.dataset.in && t < +s.dataset.out) ? 'visible' : 'hidden';
  for (const a of document.getAnimations()) { a.pause(); a.currentTime = t * 1000; }
  for (const f of TK) f(t);
}
window.__ready = document.fonts.ready.then(async () => {
  if (Q.get('cover')) { header(10); cover(); for (const a of document.getAnimations()) { a.pause(); a.currentTime = 9000; } }
  else { build(); await Promise.all(WIN); seek(0); }
  await Promise.all([...document.images].map(im => im.complete ? 0 : new Promise(r => { im.onload = im.onerror = r; })));
  return true;
});
window.__seek = seek;
