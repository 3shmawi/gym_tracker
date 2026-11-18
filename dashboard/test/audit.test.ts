import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { checkAudit, parseIgnores } from '../scripts/audit.mjs';

const via = (id: string, name: string, severity = 'high') => ({
  source: 1,
  name,
  title: `${name} problem`,
  url: `https://github.com/advisories/${id}`,
  severity,
});
const report = (...vias: object[]) => ({
  vulnerabilities: Object.fromEntries(vias.map((v, i) => [`pkg${String(i)}`, { name: `pkg${String(i)}`, via: [v, 'other-package'] }])),
});
const ignore = { id: 'GHSA-aaaa-bbbb-cccc', until: '2026-12-18', reason: 'dev only' };

describe('audit exceptions', () => {
  it('reads the real osv-scanner.toml: every entry has a reason and a date', () => {
    const ignores = parseIgnores(readFileSync('osv-scanner.toml', 'utf8'));
    expect(ignores.length).toBeGreaterThan(0);
    for (const entry of ignores) {
      expect(entry.id).toMatch(/^GHSA-/);
      expect(entry.reason).not.toBe('');
      expect(entry.until).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    }
  });

  it('passes a clean report', () => {
    expect(checkAudit({ vulnerabilities: {} }, [], '2026-11-18').problems).toEqual([]);
  });

  it('accepts a listed advisory before its date', () => {
    const result = checkAudit(report(via(ignore.id, 'picomatch')), [ignore], '2026-11-18');
    expect(result.problems).toEqual([]);
    expect(result.ignored).toHaveLength(1);
  });

  it('fails an advisory that is not listed, at any severity from low', () => {
    const result = checkAudit(report(via(ignore.id, 'picomatch'), via('GHSA-dddd-eeee-ffff', 'other', 'low')), [ignore], '2026-11-18');
    expect(result.problems).toHaveLength(1);
    expect(result.problems[0]).toContain('GHSA-dddd-eeee-ffff');
  });

  it('ignores info-level notes, like npm audit --audit-level=low', () => {
    expect(checkAudit(report(via('GHSA-dddd-eeee-ffff', 'x', 'info')), [], '2026-11-18').problems).toEqual([]);
  });

  it('fails on and after the ignoreUntil date', () => {
    for (const today of ['2026-12-18', '2027-01-01']) {
      const { problems } = checkAudit(report(via(ignore.id, 'picomatch')), [ignore], today);
      expect(problems.some((p) => p.includes('expired'))).toBe(true);
      expect(problems.some((p) => p.includes(`high: ${ignore.id}`))).toBe(true);
    }
  });

  it('refuses an entry without a reason or without a date', () => {
    const { problems } = checkAudit(
      report(via(ignore.id, 'picomatch')),
      [{ ...ignore, reason: '' }, { id: 'GHSA-1111-2222-3333', until: null, reason: 'x' }],
      '2026-11-18',
    );
    expect(problems).toContain(`osv-scanner.toml: ${ignore.id} has no reason`);
    expect(problems).toContain('osv-scanner.toml: GHSA-1111-2222-3333 has no ignoreUntil date');
  });

  it('reports an entry nothing matches any more', () => {
    expect(checkAudit({ vulnerabilities: {} }, [ignore], '2026-11-18').unused).toEqual([ignore.id]);
  });

  it('fails when npm audit itself errors', () => {
    expect(checkAudit({ error: { summary: 'network' } }, [], '2026-11-18').problems).toEqual(['npm audit failed: network']);
  });
});
