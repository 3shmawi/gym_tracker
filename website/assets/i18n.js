// Language toggle: ?lang=ar / ?lang=en, remembered per browser.
(function () {
  var stored = null;
  try { stored = localStorage.getItem('lang'); } catch (e) {}
  var param = new URLSearchParams(location.search).get('lang');
  var browser = (navigator.language || 'en').slice(0, 2) === 'ar' ? 'ar' : 'en';
  apply(param || stored || browser);

  function apply(lang) {
    lang = lang === 'ar' ? 'ar' : 'en';
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    try { localStorage.setItem('lang', lang); } catch (e) {}
    var button = document.getElementById('lang-toggle');
    if (button) button.textContent = lang === 'ar' ? 'English' : 'العربية';
  }
  document.addEventListener('DOMContentLoaded', function () {
    apply(document.documentElement.lang);
    var button = document.getElementById('lang-toggle');
    if (button) button.addEventListener('click', function () {
      apply(document.documentElement.lang === 'ar' ? 'en' : 'ar');
    });
  });
})();
