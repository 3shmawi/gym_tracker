// HTTP layer of redeem_invite, with its dependencies injected so it can be
// tested without a network or a database.
//
// What it does, in order: POST + JSON only -> the caller must be a signed-in
// user (anonymous users count; the app signs in anonymously first, see
// docs/decisions/gym_accounts.md §6) -> the body is size-capped and validated
// -> the database function redeem_invite_core does the single transaction
// (throttle, hash lookup, single use, expiry, revoke, create or link the
// person) -> the answer is mapped to a small, fixed set of responses.
//
// It never logs a code, an install id, a token or an address: the only
// thing written to the log is the database error *code* when the database
// call itself fails.
import { clientIp, parseRedeemBody, readJsonBody } from "./validate.ts";

export type Caller = {
  userId: string;
  /** Calls the secret-key-only SQL function with the verified identity. */
  redeem(input: {
    userId: string;
    code: string;
    installId: string;
    ip: string;
  }): Promise<{ data: unknown; errorCode: string | null }>;
};

export type Deps = {
  /** Verifies the JWT; null when the caller is not a signed-in user. */
  authenticate(req: Request): Promise<Caller | null>;
};

const FAILURES: Record<string, number> = {
  invalid: 400,
  not_found: 404,
  revoked: 410,
  expired: 410,
  used: 409,
  conflict: 409,
  throttled: 429,
};

const HEADERS = {
  "content-type": "application/json",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

function json(
  body: unknown,
  status: number,
  extra: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...HEADERS, ...extra },
  });
}

function fail(
  error: string,
  status: number,
  extra: Record<string, string> = {},
) {
  return json({ ok: false, error }, status, extra);
}

export async function handleRedeem(
  req: Request,
  deps: Deps,
): Promise<Response> {
  if (req.method !== "POST") {
    return fail("method_not_allowed", 405, { allow: "POST" });
  }
  if (
    !(req.headers.get("content-type") ?? "").toLowerCase().startsWith(
      "application/json",
    )
  ) {
    return fail("unsupported_media_type", 415);
  }

  const caller = await deps.authenticate(req);
  if (caller === null) return fail("unauthorized", 401);

  const body = await readJsonBody(req);
  if (!body.ok) {
    return body.reason === "too_large"
      ? fail("payload_too_large", 413)
      : fail("invalid_request", 400);
  }
  const parsed = parseRedeemBody(body.value);
  if (!parsed.ok) return fail("invalid_request", 400);

  let result: Awaited<ReturnType<Caller["redeem"]>>;
  try {
    result = await caller.redeem({
      userId: caller.userId,
      code: parsed.value.code,
      installId: parsed.value.installId,
      ip: clientIp(req.headers),
    });
  } catch {
    console.error("redeem_invite: database call threw");
    return fail("server_error", 500);
  }
  if (result.errorCode !== null) {
    console.error("redeem_invite: database error", result.errorCode);
    return fail("server_error", 500);
  }

  const data = result.data;
  if (data === null || typeof data !== "object") {
    return fail("server_error", 500);
  }
  const row = data as Record<string, unknown>;

  if (row.ok === true) {
    // Pass on only the fields the app needs, nothing the database may add later.
    return json({
      ok: true,
      gym: row.gym,
      membership_id: row.membership_id,
      role: row.role,
      permissions: row.permissions,
    }, 200);
  }

  const reason = typeof row.reason === "string" ? row.reason : "";
  const status = FAILURES[reason];
  if (status === undefined) return fail("server_error", 500);
  return fail(
    reason,
    status,
    reason === "throttled" ? { "retry-after": "600" } : {},
  );
}
