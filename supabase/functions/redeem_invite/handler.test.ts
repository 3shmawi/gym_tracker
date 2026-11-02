import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { type Caller, handleRedeem } from "./handler.ts";

const UUID = "123e4567-e89b-42d3-a456-426614174000";
const SECRET_CODE = "QXZ7RT";
const SECRET_TOKEN = "eyJhbGciOiJIUzI1NiJ9.super-secret-token-value.signature";

type Call = { userId: string; code: string; installId: string; ip: string };

function setup(
  redeem: Caller["redeem"] = () =>
    Promise.resolve({
      data: { ok: false, reason: "not_found" },
      errorCode: null,
    }),
  authenticated = true,
) {
  const calls: Call[] = [];
  let authCalls = 0;
  const deps = {
    authenticate: (_req: Request) => {
      authCalls++;
      return Promise.resolve(
        authenticated
          ? {
            userId: "user-1",
            redeem: (input: Call) => {
              calls.push(input);
              return redeem(input);
            },
          }
          : null,
      );
    },
  };
  return { deps, calls, authCalls: () => authCalls };
}

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://example.test/redeem_invite", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${SECRET_TOKEN}`,
      "cf-connecting-ip": "203.0.113.50",
      ...headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const GOOD = { code: SECRET_CODE, install_id: UUID };
const OK_ROW = {
  ok: true,
  gym: {
    id: "g1",
    name: "Gym A",
    logo_path: null,
    history_after_end: "readable",
  },
  membership_id: "m1",
  role: "trainee",
  permissions: { edit_targets: true, edit_plan: false, build_own_plan: false },
  secret_internal: "must not leak",
};

/** Runs [fn] and returns everything written to the console meanwhile. */
async function captureConsole(fn: () => Promise<void>): Promise<string> {
  const lines: string[] = [];
  const original = { ...console };
  for (const level of ["log", "info", "warn", "error", "debug"] as const) {
    console[level] = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };
  }
  try {
    await fn();
  } finally {
    Object.assign(console, original);
  }
  return lines.join("\n");
}

Deno.test("a valid code returns the gym, role and permissions, and nothing else", async () => {
  const { deps, calls } = setup(() =>
    Promise.resolve({ data: OK_ROW, errorCode: null })
  );
  const res = await handleRedeem(
    post({ code: "qxz7rt", install_id: UUID.toUpperCase() }),
    deps,
  );
  assertEquals(res.status, 200);
  const json = await res.json();
  assertEquals(json.ok, true);
  assertEquals(json.role, "trainee");
  assertEquals(json.gym.name, "Gym A");
  assertEquals("secret_internal" in json, false);
  // normalised before it reaches the database, and the verified identity is used
  assertEquals(calls, [{
    userId: "user-1",
    code: SECRET_CODE,
    installId: UUID,
    ip: "203.0.113.50",
  }]);
});

Deno.test("every response is no-store, nosniff and carries no CORS header", async () => {
  const { deps } = setup(() =>
    Promise.resolve({ data: OK_ROW, errorCode: null })
  );
  for (
    const res of [
      await handleRedeem(post(GOOD), deps),
      await handleRedeem(post("nope"), deps),
      await handleRedeem(
        new Request("https://example.test/", { method: "GET" }),
        deps,
      ),
    ]
  ) {
    assertEquals(res.headers.get("cache-control"), "no-store");
    assertEquals(res.headers.get("x-content-type-options"), "nosniff");
    assertEquals(res.headers.get("access-control-allow-origin"), null);
    await res.body?.cancel();
  }
});

Deno.test("each failure reason has its own fixed status", async () => {
  const expected: Record<string, number> = {
    not_found: 404,
    revoked: 410,
    expired: 410,
    used: 409,
    conflict: 409,
    throttled: 429,
    invalid: 400,
  };
  for (const [reason, status] of Object.entries(expected)) {
    const { deps } = setup(() =>
      Promise.resolve({ data: { ok: false, reason }, errorCode: null })
    );
    const res = await handleRedeem(post(GOOD), deps);
    assertEquals(res.status, status, reason);
    assertEquals(await res.json(), { ok: false, error: reason });
    assertEquals(
      res.headers.get("retry-after"),
      reason === "throttled" ? "600" : null,
    );
  }
});

Deno.test("an unknown reason or a malformed database answer is a 500", async () => {
  for (
    const data of [null, "x", 1, [], {}, { ok: false }, {
      ok: false,
      reason: "teapot",
    }, { ok: "true" }]
  ) {
    const { deps } = setup(() => Promise.resolve({ data, errorCode: null }));
    const res = await handleRedeem(post(GOOD), deps);
    assertEquals(res.status, 500, JSON.stringify(data));
    assertEquals((await res.json()).error, "server_error");
  }
});

Deno.test("a database error or exception is a bare 500 with no detail", async () => {
  const { deps } = setup(() =>
    Promise.resolve({ data: null, errorCode: "XX000" })
  );
  const res = await handleRedeem(post(GOOD), deps);
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { ok: false, error: "server_error" });

  const boom = setup(() => Promise.reject(new Error(`boom ${SECRET_CODE}`)));
  const res2 = await handleRedeem(post(GOOD), boom.deps);
  assertEquals(res2.status, 500);
  assertEquals((await res2.text()).includes(SECRET_CODE), false);
});

Deno.test("only POST with a JSON content type is served", async () => {
  const { deps, calls, authCalls } = setup();
  for (const method of ["GET", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]) {
    const res = await handleRedeem(
      new Request("https://example.test/", { method }),
      deps,
    );
    assertEquals(res.status, 405, method);
    await res.body?.cancel();
  }
  const res = await handleRedeem(
    post(JSON.stringify(GOOD), { "content-type": "text/plain" }),
    deps,
  );
  assertEquals(res.status, 415);
  await res.body?.cancel();
  assertEquals(calls.length, 0);
  assertEquals(
    authCalls(),
    0,
    "not even authentication runs for the wrong method or type",
  );
});

Deno.test("a caller who is not signed in is refused and nothing is read or redeemed", async () => {
  const { deps, calls } = setup(undefined, false);
  const res = await handleRedeem(post(GOOD), deps);
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(calls.length, 0);
});

Deno.test("hostile bodies never reach the database", async () => {
  const hostile: unknown[] = [
    "",
    "{",
    "null",
    "[]",
    "42",
    '"ABC234"',
    "true",
    { code: 123456, install_id: UUID },
    { code: ["ABC234"], install_id: UUID },
    { code: { $ne: "" }, install_id: UUID },
    { code: "ABC234", install_id: 1 },
    { code: "ABC234", install_id: "not-a-uuid" },
    { code: "ABC234" },
    { install_id: UUID },
    { code: "ABC234", install_id: UUID, role: "owner" },
    { code: "'; drop table invites; --", install_id: UUID },
    { code: "<script>alert(1)</script>", install_id: UUID },
    { code: "ABC234", install_id: `${UUID}'; --` },
    { code: "A".repeat(100_000), install_id: UUID },
  ];
  const { deps, calls } = setup();
  for (const body of hostile) {
    const res = await handleRedeem(post(body), deps);
    assert(
      [400, 413].includes(res.status),
      `expected 400/413, got ${res.status} for ${
        String(JSON.stringify(body)).slice(0, 50)
      }`,
    );
    await res.body?.cancel();
  }
  assertEquals(calls.length, 0);
});

Deno.test("a huge body is refused as too large", async () => {
  const { deps, calls } = setup();
  const res = await handleRedeem(
    post(JSON.stringify({ ...GOOD, pad: "x".repeat(5_000_000) })),
    deps,
  );
  assertEquals(res.status, 413);
  await res.body?.cancel();
  assertEquals(calls.length, 0);
});

Deno.test("replay: the second redeem of a code is answered 409", async () => {
  let used = false;
  const { deps } = setup(() => {
    if (used) {
      return Promise.resolve({
        data: { ok: false, reason: "used" },
        errorCode: null,
      });
    }
    used = true;
    return Promise.resolve({ data: OK_ROW, errorCode: null });
  });
  assertEquals((await handleRedeem(post(GOOD), deps)).status, 200);
  const replay = await handleRedeem(post(GOOD), deps);
  assertEquals(replay.status, 409);
  assertEquals((await replay.json()).error, "used");
});

Deno.test("brute force: the database's throttle shows up as 429 with Retry-After", async () => {
  let attempts = 0;
  const { deps } = setup(() => {
    attempts++;
    return Promise.resolve({
      data: { ok: false, reason: attempts > 10 ? "throttled" : "not_found" },
      errorCode: null,
    });
  });
  const statuses: number[] = [];
  for (let i = 0; i < 40; i++) {
    const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    const guess = `Q${alphabet[i % 31]}${alphabet[Math.floor(i / 31)]}AAA`;
    const res = await handleRedeem(
      post({ code: guess, install_id: UUID }),
      deps,
    );
    statuses.push(res.status);
    await res.body?.cancel();
  }
  assertEquals(statuses.filter((s) => s === 404).length, 10);
  assertEquals(statuses.filter((s) => s === 429).length, 30);
});

Deno.test("the address handed to the database comes from the edge, not the body", async () => {
  const { deps, calls } = setup();
  await (await handleRedeem(
    post({ ...GOOD }, { "cf-connecting-ip": "198.51.100.4" }),
    deps,
  )).text();
  await (await handleRedeem(
    post(GOOD, {
      "cf-connecting-ip": "",
      "x-forwarded-for": "1.1.1.1, 198.51.100.8",
    }),
    deps,
  )).text();
  assertEquals(calls.map((c) => c.ip), ["198.51.100.4", "198.51.100.8"]);
});

Deno.test("nothing secret is ever logged: not the code, install id, token or address", async () => {
  const outputs: string[] = [];
  outputs.push(
    await captureConsole(async () => {
      const ok = setup(() =>
        Promise.resolve({ data: OK_ROW, errorCode: null })
      );
      await (await handleRedeem(post(GOOD), ok.deps)).text();
      const bad = setup(() =>
        Promise.resolve({ data: null, errorCode: "XX000" })
      );
      await (await handleRedeem(post(GOOD), bad.deps)).text();
      const boom = setup(() =>
        Promise.reject(new Error(`${SECRET_CODE} ${SECRET_TOKEN}`))
      );
      await (await handleRedeem(post(GOOD), boom.deps)).text();
      const weird = setup(() =>
        Promise.resolve({
          data: { ok: false, reason: SECRET_CODE },
          errorCode: null,
        })
      );
      await (await handleRedeem(post(GOOD), weird.deps)).text();
      await (await handleRedeem(
        post({ code: SECRET_CODE, install_id: "bad" }),
        ok.deps,
      )).text();
    }),
  );
  const log = outputs.join("\n");
  assertNotEquals(log, "", "the error paths do log something");
  for (
    const secret of [SECRET_CODE, SECRET_TOKEN, UUID, "203.0.113.50", "Bearer"]
  ) {
    assertEquals(
      log.includes(secret),
      false,
      `the log must not contain ${secret}`,
    );
  }
});
