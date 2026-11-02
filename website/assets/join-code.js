// Pure helpers for the join page (no DOM). Loaded by join.js in the browser
// and by test/website/join_code.test.js in Node.
(function (root) {
  'use strict';

  // Keep in sync with the SQL generator, the Edge Function and the app's
  // InviteCode: 6 characters from 31 (no 0 O 1 I L).
  var CODE = /^[A-HJKMNP-Z2-9]{6}$/;
  // ASCII only BEFORE upper-casing, so "ß" or "ſ" can never fold into a letter.
  var RAW = /^[A-Za-z0-9]{6}$/;

  // The code in a path like /join/ABC234 (a trailing slash is fine), or null.
  // Nothing else in the address is looked at: no query, no hash, no extra
  // segments.
  function codeFromPath(pathname) {
    if (typeof pathname !== 'string' || pathname.length > 64) return null;
    var match = /^\/join\/([^\/]*)\/?$/.exec(pathname);
    if (!match) return null;
    var segment;
    try { segment = decodeURIComponent(match[1]); } catch (e) { return null; }
    if (!RAW.test(segment)) return null;
    var code = segment.toUpperCase();
    return CODE.test(code) ? code : null;
  }

  // 'ios' | 'android' | 'desktop' | 'other'. iPadOS 13+ reports itself as a Mac.
  function platform(userAgent, platformName, maxTouchPoints) {
    var ua = typeof userAgent === 'string' ? userAgent : '';
    if (/android/i.test(ua)) return 'android';
    if (/iphone|ipad|ipod/i.test(ua)) return 'ios';
    if (platformName === 'MacIntel' && maxTouchPoints > 1) return 'ios';
    if (/windows|macintosh|linux|cros|x11/i.test(ua)) return 'desktop';
    return 'other';
  }

  // The app's custom-scheme link; the code must already be valid.
  function appLink(code) {
    return CODE.test(code) ? 'azm://join/' + code : 'azm://join';
  }

  var api = { codeFromPath: codeFromPath, platform: platform, appLink: appLink };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.AzmJoinCode = api;
})(typeof self !== 'undefined' ? self : this);
