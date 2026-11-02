// Join page (docs/decisions/gym_accounts.md §7). It only DISPLAYS a code and
// links to the app or a store: it never calls a backend (the CSP has
// connect-src 'none') and never joins anything. The code from the address is
// checked first and is only ever written with textContent.
(function () {
  'use strict';
  var logic = self.AzmJoinCode;
  var page = document.getElementById('join');
  if (!logic || !page) return;

  function show(el, visible) { if (el) el.hidden = !visible; }
  var okPanel = page.querySelector('.panel.ok');
  var badPanel = page.querySelector('.panel.bad');
  var foot = document.getElementById('foot');
  var codeCard = document.getElementById('codecard');
  var codeEl = document.getElementById('code');
  var openLink = document.getElementById('open');
  var copyBtn = document.getElementById('copy');
  var copied = document.getElementById('copied');

  page.setAttribute('data-platform',
    logic.platform(navigator.userAgent, navigator.platform, navigator.maxTouchPoints || 0));

  var code = logic.codeFromPath(location.pathname);
  if (code === null) {
    page.setAttribute('data-state', 'bad');
    show(okPanel, false);
    show(badPanel, true);
    show(foot, false);
    return;
  }

  page.setAttribute('data-state', 'ok');
  codeEl.textContent = code;
  show(codeCard, true);
  openLink.setAttribute('href', logic.appLink(code));

  if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
    show(copyBtn, true);
    copyBtn.addEventListener('click', function () {
      navigator.clipboard.writeText(code).then(function () { show(copied, true); }, function () {});
    });
  }
})();
