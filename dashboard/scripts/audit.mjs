// `npm audit` with time-boxed exceptions. Fails on every advisory (low and
// above) except those listed in osv-scanner.toml, and fails when an entry
// there has no reason, no ignoreUntil date, or has expired. The same file
// makes OSV-Scanner skip the advisory, so both checks agree.
// docs/security.md → "Captain dashboard" → "Accepted advisories".
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const severities = new Set(['low', 'moderate', 'high', 'critical']);

/** The [[IgnoredVulns]] entries of an osv-scanner.toml (only the keys we write). */
export function parseIgnores(toml) {
  return toml
    .split(/^\[\[IgnoredVulns\]\]\s*$/m)
    .slice(1)
    .map((block) => ({
      id: /^id\s*=\s*"([^"]+)"/m.exec(block)?.[1] ?? '',
      until: /^ignoreUntil\s*=\s*(\d{4}-\d{2}-\d{2})\s*$/m.exec(block)?.[1] ?? null,
      reason: /^reason\s*=\s*"([^"]*)"/m.exec(block)?.[1]?.trim() ?? '',
    }));
}

/** Advisories in an `npm audit --json` report, by id (GHSA when known). */
export function advisories(report) {
  const found = new Map();
  for (const vuln of Object.values(report.vulnerabilities ?? {})) {
    for (const via of vuln.via ?? []) {
      if (typeof via !== 'object' || via === null) continue;
      if (!severities.has(via.severity)) continue;
      const id = /GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}/.exec(via.url ?? '')?.[0] ?? `npm-${String(via.source)}`;
      const entry = found.get(id) ?? { id, title: via.title ?? '', severity: via.severity, packages: new Set() };
      entry.packages.add(via.name ?? vuln.name);
      found.set(id, entry);
    }
  }
  return [...found.values()];
}

/**
 * Compares a report with the ignore list. `today` is YYYY-MM-DD (UTC).
 * Returns the problems (non-empty fails the check), the advisories ignored,
 * and ignore entries that matched nothing (a hint to remove them).
 */
export function checkAudit(report, ignores, today) {
  const problems = [];
  if (report.error) problems.push(`npm audit failed: ${report.error.summary ?? JSON.stringify(report.error)}`);
  const valid = new Map();
  for (const ignore of ignores) {
    if (!ignore.id) problems.push('osv-scanner.toml: an [[IgnoredVulns]] entry has no id');
    else if (!ignore.reason) problems.push(`osv-scanner.toml: ${ignore.id} has no reason`);
    else if (!ignore.until) problems.push(`osv-scanner.toml: ${ignore.id} has no ignoreUntil date`);
    else if (today >= ignore.until) problems.push(`osv-scanner.toml: ${ignore.id} expired on ${ignore.until}; re-check it (fix released? renew?)`);
    else valid.set(ignore.id, ignore);
  }
  const ignored = [];
  const seen = new Set();
  for (const advisory of advisories(report)) {
    seen.add(advisory.id);
    const packages = [...advisory.packages].join(', ');
    if (valid.has(advisory.id)) ignored.push(`${advisory.id} (${packages}) until ${valid.get(advisory.id).until}`);
    else problems.push(`${advisory.severity}: ${advisory.id} ${advisory.title} (${packages})`);
  }
  const unused = [...valid.keys()].filter((id) => !seen.has(id));
  return { problems, ignored, unused };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const root = new URL('../', import.meta.url);
  const toml = readFileSync(new URL('osv-scanner.toml', root), 'utf8');
  const run = spawnSync('npm', ['audit', '--json'], { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  let report;
  try {
    report = JSON.parse(run.stdout);
  } catch {
    console.error(`npm audit gave no JSON (exit ${String(run.status)}):\n${run.stderr}`);
    process.exit(1);
  }
  const today = new Date().toISOString().slice(0, 10);
  const { problems, ignored, unused } = checkAudit(report, parseIgnores(toml), today);
  for (const line of ignored) console.log(`accepted: ${line}`);
  for (const id of unused) console.log(`no longer reported, remove it from osv-scanner.toml: ${id}`);
  if (problems.length > 0) {
    console.error(problems.map((p) => `✗ ${p}`).join('\n'));
    process.exit(1);
  }
  console.log('npm audit: no advisories outside osv-scanner.toml');
}
