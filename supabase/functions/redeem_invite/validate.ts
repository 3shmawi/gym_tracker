// Pure input checks for redeem_invite. Everything a caller sends is hostile
// until proven otherwise: types, sizes, characters, extra fields.

/** The 6-character code alphabet (no 0 O 1 I L). Keep in sync with the SQL
 * generator and website/assets/join.js. */
export const CODE_PATTERN = /^[A-HJKMNP-Z2-9]{6}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** A request body is a tiny JSON object; anything bigger is refused unread. */
export const MAX_BODY_BYTES = 1024;
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

export type BodyResult =
  | { ok: true; value: unknown }
  | { ok: false; reason: "too_large" | "invalid_json" };

/** Reads at most [maxBytes] of the body, then parses it as JSON. */
export async function readJsonBody(
  req: Request,
  maxBytes: number = MAX_BODY_BYTES,
): Promise<BodyResult> {
  const declared = req.headers.get("content-length");
  if (declared !== null && Number(declared) > maxBytes) {
    return { ok: false, reason: "too_large" };
  }
  if (req.body === null) return { ok: false, reason: "invalid_json" };

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        return { ok: false, reason: "too_large" };
      }
      chunks.push(value);
    }
  } catch {
    return { ok: false, reason: "invalid_json" };
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, reason: "invalid_json" };
  }
}

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
