// HTTP layer of delete-account (Apple 5.1.1(v) / Google Play: in-app account
// deletion), with its dependencies injected so it can be tested without a
// network or a database.
//
// The caller can only ever delete THEMSELVES: the user id comes from the
// verified JWT, never from the body, and the body is exactly
// `{ "confirm": "delete" }`. A sole owner of a gym that still has members is
// refused (409 last_owner, with the gym names) until they hand the gym over or
// remove its members. Deleting the auth user cascades to everything of that
// person (supabase/migrations/0011_account_deletion.sql).
//
// It never logs an id, a token or a gym name: only a fixed text and the error's
// *code* when the database or Auth call itself fails.
import { MAX_BODY_BYTES, readJsonBody } from "../_shared/read_json_body.ts";

export type Blockers = { blocked: boolean; gyms: { name: string }[] };

export type Caller = {
  userId: string;
  /** account_deletion_blockers(), called with the secret key. */
  blockers(): Promise<{ data: unknown; errorCode: string | null }>;
  /** auth.admin.deleteUser(userId): a hard delete. `notFound` = already gone. */
  deleteUser(): Promise<{ errorCode: string | null; notFound: boolean }>;
};

export type Deps = {
  /** Verifies the JWT; null when the caller is not a signed-in user. */
  authenticate(req: Request): Promise<Caller | null>;
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

/** The body must be exactly `{ confirm: "delete" }`. */
export function isDeleteRequest(body: unknown): boolean {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return false;
  }
  const keys = Object.keys(body);
  return keys.length === 1 && keys[0] === "confirm" &&
    (body as Record<string, unknown>).confirm === "delete";
}

function parseBlockers(data: unknown): Blockers | null {
  if (data === null || typeof data !== "object") return null;
  const row = data as Record<string, unknown>;
  if (typeof row.blocked !== "boolean" || !Array.isArray(row.gyms)) return null;
  const gyms: { name: string }[] = [];
  for (const gym of row.gyms) {
    if (gym === null || typeof gym !== "object") return null;
    const name = (gym as Record<string, unknown>).name;
    if (typeof name !== "string") return null;
    gyms.push({ name: name.slice(0, 60) });
  }
  return { blocked: row.blocked, gyms };
}

export async function handleDelete(
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

  const body = await readJsonBody(req, MAX_BODY_BYTES);
  if (!body.ok) {
    return body.reason === "too_large"
      ? fail("payload_too_large", 413)
      : fail("invalid_request", 400);
  }
  if (!isDeleteRequest(body.value)) return fail("invalid_request", 400);

  let check: Awaited<ReturnType<Caller["blockers"]>>;
  try {
    check = await caller.blockers();
  } catch {
    console.error("delete-account: blockers call threw");
    return fail("server_error", 500);
  }
  const blockers = check.errorCode === null ? parseBlockers(check.data) : null;
  if (blockers === null) {
    console.error(
      "delete-account: blockers failed",
      check.errorCode ?? "shape",
    );
    return fail("server_error", 500);
  }
  if (blockers.blocked) {
    return json({ ok: false, error: "last_owner", gyms: blockers.gyms }, 409);
  }

  let result: Awaited<ReturnType<Caller["deleteUser"]>>;
  try {
    result = await caller.deleteUser();
  } catch {
    console.error("delete-account: delete threw");
    return fail("server_error", 500);
  }
  // A second call with the same (still valid) token: it is already gone.
  if (result.errorCode !== null && !result.notFound) {
    console.error("delete-account: delete failed", result.errorCode);
    return fail("server_error", 500);
  }
  return json({ ok: true }, 200);
}
