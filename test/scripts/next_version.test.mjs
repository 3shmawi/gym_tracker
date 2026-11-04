// scripts/next_version.sh: Conventional Commits → next app version.
// The captain dashboard (dashboard/) deploys on its own, so a commit that
// changes only dashboard/ must never release the mobile app.
// Run: node --test test/scripts/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'scripts', 'next_version.sh');

function repo() {
  const dir = mkdtempSync(join(tmpdir(), 'next-version-'));
  const git = (...args) =>
    execFileSync('git', args, {
      cwd: dir,
      env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@example.com', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@example.com' },
      encoding: 'utf8',
    });
  git('init', '-q', '-b', 'main');
  mkdirSync(join(dir, 'scripts'));
  copyFileSync(script, join(dir, 'scripts', 'next_version.sh'));
  writeFileSync(join(dir, 'pubspec.yaml'), 'name: azm\nversion: 1.0.0+1\n');
  git('add', '.');
  git('commit', '-q', '-m', 'chore: start');
  git('tag', 'v1.2.3');
  const commit = (paths, message) => {
    for (const path of [paths].flat()) {
      mkdirSync(join(dir, dirname(path)), { recursive: true });
      writeFileSync(join(dir, path), `${message}\n${Math.random()}\n`);
    }
    git('add', '.');
    git('commit', '-q', '-m', message);
  };
  const next = () => execFileSync('bash', ['scripts/next_version.sh'], { cwd: dir, encoding: 'utf8' }).trim();
  return { dir, commit, next, done: () => rmSync(dir, { recursive: true, force: true }) };
}

test('a feat that changes only dashboard/ is skipped', () => {
  const r = repo();
  try {
    r.commit('dashboard/src/main.tsx', 'feat: dashboard sign-in');
    assert.equal(r.next(), 'skip');
  } finally { r.done(); }
});

test('a feat in the app still releases a minor', () => {
  const r = repo();
  try {
    r.commit('dashboard/src/main.tsx', 'feat: dashboard sign-in');
    r.commit('lib/main.dart', 'fix: app crash');
    assert.equal(r.next(), '1.2.4');
    r.commit('lib/feature.dart', 'feat: app feature');
    assert.equal(r.next(), '1.3.0');
  } finally { r.done(); }
});

test('a commit touching dashboard/ and the app counts', () => {
  const r = repo();
  try {
    r.commit(['dashboard/a.ts', 'lib/a.dart'], 'feat: shared change');
    assert.equal(r.next(), '1.3.0');
  } finally { r.done(); }
});

test('a breaking dashboard-only commit is still skipped', () => {
  const r = repo();
  try {
    r.commit('dashboard/x.ts', 'feat!: new dashboard');
    assert.equal(r.next(), 'skip');
  } finally { r.done(); }
});

test('docs-only commits still skip', () => {
  const r = repo();
  try {
    r.commit('docs/a.md', 'docs: notes');
    assert.equal(r.next(), 'skip');
  } finally { r.done(); }
});
