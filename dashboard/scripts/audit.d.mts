// Types for scripts/audit.mjs, so the unit tests can import it.
export interface Ignore {
  id: string;
  until: string | null;
  reason: string;
}

export interface Advisory {
  id: string;
  title: string;
  severity: string;
  packages: Set<string>;
}

export interface AuditCheck {
  problems: string[];
  ignored: string[];
  unused: string[];
}

export function parseIgnores(toml: string): Ignore[];
export function advisories(report: unknown): Advisory[];
export function checkAudit(report: unknown, ignores: Ignore[], today: string): AuditCheck;
