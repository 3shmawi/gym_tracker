// Pure input checks for redeem_invite. Everything a caller sends is hostile
// until proven otherwise: types, sizes, characters, extra fields.

/** The 6-character code alphabet (no 0 O 1 I L). Keep in sync with the SQL
 * generator and website/assets/join.js. */
export const CODE_PATTERN = /^[A-HJKMNP-Z2-9]{6}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Longest code-like string we even look at (pasted codes may carry spaces). */
const MAX_CODE_INPUT = 32;
const MAX_UUID_INPUT = 64;

export type RedeemInput = { code: string; installId: string };

export type ParseResult =
  | { ok: true; value: RedeemInput }
  | { ok: false };

/** `ABC123`, ` abc123 ` -> `ABC123`; anything else -> null. ASCII only before
 * upper-casing, so "ſ" or "ß" can never turn into a valid letter. */
export function normalizeCode(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length > MAX_CODE_INPUT) return null;
  const trimmed = raw.trim();
  if (!/^[\x21-\x7e]+$/.test(trimmed)) return null;
  const code = trimmed.toUpperCase();
  return CODE_PATTERN.test(code) ? code : null;
}

export function normalizeUuid(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length > MAX_UUID_INPUT) return null;
  const id = raw.trim().toLowerCase();
  return UUID_PATTERN.test(id) ? id : null;
}

/** The body must be exactly `{ code: string, install_id: uuid-string }`. */
export function parseRedeemBody(body: unknown): ParseResult {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false };
  }
  const keys = Object.keys(body);
  if (
    keys.length !== 2 || !keys.includes("code") || !keys.includes("install_id")
  ) {
    return { ok: false };
  }
  const record = body as Record<string, unknown>;
  const code = normalizeCode(record.code);
  const installId = normalizeUuid(record.install_id);
  if (code === null || installId === null) return { ok: false };
  return { ok: true, value: { code, installId } };
}

export {
  type BodyResult,
  MAX_BODY_BYTES,
  readJsonBody,
} from "../_shared/read_json_body.ts";

/** The caller's address for throttling. Cloudflare's header is set by the
 * edge and cannot be forged by the client; failing that, the last hop of
 * x-forwarded-for (the one our own proxy added). Capped in length. */
export function clientIp(headers: Headers): string {
  const cf = headers.get("cf-connecting-ip");
  if (cf && cf.trim() !== "") return cf.trim().slice(0, 64);
  const forwarded = headers.get("x-forwarded-for");
  if (forwarded) {
    const last = forwarded.split(",").at(-1)?.trim();
    if (last) return last.slice(0, 64);
  }
  return "unknown";
}
