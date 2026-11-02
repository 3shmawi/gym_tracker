// Tests for website/assets/join-code.js and join.js (run: node --test test/website).
// No dependencies: join.js runs against a tiny fake DOM.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const assets = path.join(__dirname, '..', '..', 'website', 'assets');
const logic = require(path.join(assets, 'join-code.js'));

test('a valid code is read from /join/<code>, upper-cased', () => {
  assert.equal(logic.codeFromPath('/join/ABC234'), 'ABC234');
  assert.equal(logic.codeFromPath('/join/abc234'), 'ABC234');
  assert.equal(logic.codeFromPath('/join/hjk2mn/'), 'HJK2MN');
  assert.equal(logic.codeFromPath('/join/%41BC234'), 'ABC234');
});

test('every hostile or malformed path gives no code', () => {
  const bad = [
    '/join', '/join/', '/join//', '/join/ABC23', '/join/ABC2345', '/join/ABC230', '/join/ABC23O',
    '/join/ABC231', '/join/ABC23I', '/join/ABC23L', '/join/ABC234/extra', '/join/ABC234/../x',
    '/joinx/ABC234', '/x/join/ABC234', '/JOIN/ABC234', '//join/ABC234',
    '/join/<script>alert(1)</script>', "/join/'; drop table invites;--", '/join/javascript:alert(1)',
    '/join/https://evil.example', '/join/%3Cscript%3E', '/join/%00ABC23', '/join/ABC23%0A',
    '/join/%E0%A4%A', '/join/%ZZ', '/join/ſſſſſſ', '/join/ßßßßßß', '/join/ＡＢＣ２３４', '/join/ÄBC234',
    '/join/' + 'A'.repeat(5000), '', null, undefined, 123, {}, ['/join/ABC234'],
  ];
  for (const p of bad) assert.equal(logic.codeFromPath(p), null, String(p).slice(0, 40));
});

test('only the path is read: a query or hash cannot supply a code', () => {
  assert.equal(logic.codeFromPath('/join'), null);
  // join.js passes location.pathname, which never holds ? or #; a literal one is refused.
  assert.equal(logic.codeFromPath('/join?c=ABC234'), null);
  assert.equal(logic.codeFromPath('/join/ABC234?x=1'), null);
  assert.equal(logic.codeFromPath('/join/ABC234#x'), null);
});

test('platform detection', () => {
  assert.equal(logic.platform('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)', 'iPhone', 5), 'ios');
  assert.equal(logic.platform('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 'MacIntel', 5), 'ios');
  assert.equal(logic.platform('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 'MacIntel', 0), 'desktop');
  assert.equal(logic.platform('Mozilla/5.0 (Linux; Android 15; Pixel 9)', 'Linux armv8l', 5), 'android');
  assert.equal(logic.platform('Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'Win32', 0), 'desktop');
  assert.equal(logic.platform('Mozilla/5.0 (X11; Linux x86_64)', 'Linux x86_64', 0), 'desktop');
  assert.equal(logic.platform('', '', 0), 'other');
  assert.equal(logic.platform(undefined, undefined, undefined), 'other');
});

test('the app link is only built from a valid code', () => {
  assert.equal(logic.appLink('ABC234'), 'azm://join/ABC234');
  for (const bad of ['', 'abc234', 'ABC23', '<script>', 'ABC234/../x', null, undefined, 5]) {
    assert.equal(logic.appLink(bad), 'azm://join');
  }
});

// --- join.js against a fake DOM -------------------------------------------
function fakeElement(extra = {}) {
  const attrs = {};
  const handlers = {};
  return Object.assign({
    hidden: false, textContent: '',
    attrs, setAttribute(k, v) { attrs[k] = v; }, getAttribute(k) { return attrs[k]; },
    addEventListener(name, fn) { handlers[name] = fn; }, handlers,
    querySelector() { return null; },
  }, extra);
}

function runPage(pathname, { clipboard = true, ua = 'Mozilla/5.0 (iPhone)' } = {}) {
  const els = {};
  for (const id of ['codecard', 'code', 'open', 'copy', 'copied']) els[id] = fakeElement();
  els.codecard.hidden = true; els.copy.hidden = true; els.copied.hidden = true;
  const okPanel = fakeElement(); const badPanel = fakeElement({ hidden: true }); const valid = fakeElement();
  const page = fakeElement({
    querySelector(sel) { return { '.panel.ok': okPanel, '.panel.bad': badPanel, '.foot .valid': valid }[sel] || null; },
  });
  const written = [];
  const sandbox = {
    self: null,
    document: { getElementById: (id) => (id === 'join' ? page : els[id] || null) },
    location: { pathname },
    navigator: { userAgent: ua, platform: 'iPhone', maxTouchPoints: 5,
      clipboard: clipboard ? { writeText: (t) => { written.push(t); return Promise.resolve(); } } : undefined },
  };
  sandbox.self = sandbox;
  sandbox.AzmJoinCode = logic;
  vm.runInNewContext(fs.readFileSync(path.join(assets, 'join.js'), 'utf8'), sandbox);
  return { els, page, okPanel, badPanel, valid, written };
}

test('join.js shows a valid code as text and links to the app', () => {
  const r = runPage('/join/hjk2mn');
  assert.equal(r.page.attrs['data-state'], 'ok');
  assert.equal(r.page.attrs['data-platform'], 'ios');
  assert.equal(r.els.code.textContent, 'HJK2MN');
  assert.equal(r.els.codecard.hidden, false);
  assert.equal(r.els.open.attrs.href, 'azm://join/HJK2MN');
  assert.equal(r.badPanel.hidden, true);
  r.els.copy.handlers.click();
  assert.deepEqual(r.written, ['HJK2MN']);
});

test('join.js hides copy when the clipboard is unavailable', () => {
  const r = runPage('/join/HJK2MN', { clipboard: false });
  assert.equal(r.els.copy.hidden, true);
});

test('join.js prints nothing from a hostile address and shows the "incomplete" panel', () => {
  for (const p of ['/join', '/join/<img src=x onerror=alert(1)>', '/join/ABC234/x', '/join/' + 'A'.repeat(500)]) {
    const r = runPage(p);
    assert.equal(r.page.attrs['data-state'], 'bad', p);
    assert.equal(r.els.code.textContent, '', p);
    assert.equal(r.els.codecard.hidden, true, p);
    assert.equal(r.els.open.attrs.href, undefined, p);
    assert.equal(r.badPanel.hidden, false, p);
    assert.equal(r.okPanel.hidden, true, p);
  }
});
