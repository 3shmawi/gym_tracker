// Checks the built dashboard (dist/) before it can ship. Run after `npm run build`.
// - index.html: no inline script, no inline style, no style attributes;
// - _headers: the CSP and the other security headers are there, and
//   connect-src names only 'self' and our Supabase project; img-src only
//   'self' and the picture library's Cloudinary path;
// - no secret-looking strings anywhere in dist/.
// docs/security.md → "Captain dashboard".
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
const problems = [];
const fail = (message) => problems.push(message);

const html = readFileSync(join(dist, 'index.html'), 'utf8');
for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
  const [, attrs, body] = match;
  if (!/\bsrc=/.test(attrs) || body.trim() !== '') fail('index.html has an inline <script>');
}
if (/<style\b/i.test(html)) fail('index.html has an inline <style>');
if (/\sstyle=/i.test(html)) fail('index.html has a style= attribute');
if (/\son[a-z]+=/i.test(html)) fail('index.html has an inline event handler');

const headers = readFileSync(join(dist, '_headers'), 'utf8');
const csp = /Content-Security-Policy: (.+)/.exec(headers)?.[1] ?? '';
if (!csp) fail('_headers has no Content-Security-Policy');
const directives = Object.fromEntries(
  csp.split(';').map((d) => d.trim().split(/\s+/)).filter((d) => d[0]).map(([name, ...values]) => [name, values]),
);
const expect = (name, values) => {
  const got = (directives[name] ?? []).join(' ');
  if (got !== values.join(' ')) fail(`CSP ${name} is "${got}", expected "${values.join(' ')}"`);
};
expect('default-src', ["'self'"]);
const turnstile = Boolean(process.env.VITE_TURNSTILE_SITE_KEY);
const cf = 'https://challenges.cloudflare.com';
expect('script-src', turnstile ? ["'self'", cf] : ["'self'"]);
expect('frame-src', turnstile ? [cf] : ["'none'"]);
expect('style-src', ["'self'"]);
expect('object-src', ["'none'"]);
expect('base-uri', ["'none'"]);
expect('frame-ancestors', ["'none'"]);
const url = (process.env.VITE_SUPABASE_URL ?? '').replace(/\/+$/, '');
expect('connect-src', ["'self'", url, url.replace(/^https:/, 'wss:')]);
// Exercise pictures (D2): only this cloud's upload path, never the whole host.
const cloud = (process.env.VITE_CLOUDINARY_CLOUD_NAME ?? '').trim();
expect('img-src', cloud ? ["'self'", `https://res.cloudinary.com/${cloud}/image/upload/`] : ["'self'"]);
if (/unsafe-|\*|data:|blob:|http:/.test(csp)) fail('CSP allows unsafe-*, a wildcard, data:, blob: or http:');
for (const header of [
  'Strict-Transport-Security: max-age=31536000',
  'X-Content-Type-Options: nosniff',
  'X-Frame-Options: DENY',
  'Referrer-Policy: no-referrer',
  '! Access-Control-Allow-Origin',
]) {
  if (!headers.includes(header)) fail(`_headers is missing "${header}"`);
}
for (const line of headers.split('\n')) if (line.length > 2000) fail('_headers line over 2000 characters');

// Real key shapes, not the bare prefix (supabase-js and our own check name it).
const secret = /sb_secret_[A-Za-z0-9_-]{10,}|BEGIN [A-Z ]*PRIVATE KEY|SUPABASE_SECRET_KEY=/;
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path);
    else if (/\.(html|js|css|map|txt|json)$|_headers$/.test(name) && secret.test(readFileSync(path, 'utf8'))) {
      fail(`secret-looking text in dist/${path.slice(dist.length)}`);
    }
  }
};
walk(dist);

if (problems.length) {
  console.error(problems.map((p) => `✗ ${p}`).join('\n'));
  process.exit(1);
}
console.log('dist/ passes: no inline script or style, CSP and security headers present, no secrets.');
