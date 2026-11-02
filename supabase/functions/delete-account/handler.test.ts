import { assert, assertEquals } from "@std/assert";
import { type Caller, handleDelete, isDeleteRequest } from "./handler.ts";

const SECRET_USER = "11111111-2222-4333-8444-555555555555";
const SECRET_TOKEN = "eyJhbGciOiJFUzI1NiJ9.very-secret-token.signature";
const GYM_NAME = "Iron House Secret Gym";

type Fakes = {
  blockers?: Caller["blockers"];
  deleteUser?: Caller["deleteUser"];
  authenticated?: boolean;
};

function setup(f: Fakes = {}) {
  const calls = { blockers: 0, deleteUser: 0 };
  const caller: Caller = {
    userId: SECRET_USER,
    blockers: () => {
      calls.blockers++;
      return (f.blockers ??
        (() =>
          Promise.resolve({
            data: { blocked: false, gyms: [] },
            errorCode: null,
          })))();
    },
    deleteUser: () => {
      calls.deleteUser++;
      return (f.deleteUser ??
        (() => Promise.resolve({ errorCode: null, notFound: false })))();
    },
  };
  let authCalls = 0;
  const deps = {
    authenticate: (_req: Request) => {
      authCalls++;
      return Promise.resolve(f.authenticated === false ? null : caller);
    },
  };
  return { deps, calls, authCalls: () => authCalls };
}

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://example.test/delete-account", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${SECRET_TOKEN}`,
      ...headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const GOOD = { confirm: "delete" };

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

Deno.test("the exact confirmation deletes the caller, once", async () => {
  const { deps, calls } = setup();
  const res = await handleDelete(post(GOOD), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true });
  assertEquals(calls, { blockers: 1, deleteUser: 1 });
});

Deno.test("the body is exactly { confirm: 'delete' }; anything else is a 400", async () => {
  const bad: unknown[] = [
    "",
    "{",
    "null",
    "[]",
    "true",
    '"delete"',
    42,
    {},
    { confirm: "DELETE" },
    { confirm: "Delete" },
    { confirm: " delete" },
    { confirm: "delete " },
    { confirm: true },
    { confirm: 1 },
    { confirm: ["delete"] },
    { confirm: { a: 1 } },
    { confirm: null },
    { confirm: "delete", user_id: "someone-else" },
    { confirm: "delete", userId: SECRET_USER },
    { confirm: "delete", extra: 1 },
    { Confirm: "delete" },
    { user_id: "someone-else" },
  ];
  const { deps, calls } = setup();
  for (const body of bad) {
    const res = await handleDelete(post(body), deps);
    assertEquals(res.status, 400, JSON.stringify(body));
    await res.body?.cancel();
  }
  assertEquals(calls, { blockers: 0, deleteUser: 0 });
  assertEquals(isDeleteRequest({ confirm: "delete" }), true);
});

Deno.test("the user to delete is the verified caller, never anything in the request", async () => {
  const seen: string[] = [];
  const { deps } = setup({
    deleteUser: () => Promise.resolve({ errorCode: null, notFound: false }),
  });
  const original = deps.authenticate;
  deps.authenticate = async (req: Request) => {
    const caller = await original(req);
    if (caller) seen.push(caller.userId);
    return caller;
  };
  await (await handleDelete(post(GOOD), deps)).text();
  assertEquals(seen, [SECRET_USER]);
});

Deno.test("only POST with JSON, and not even authentication runs otherwise", async () => {
  const { deps, calls, authCalls } = setup();
  for (const method of ["GET", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]) {
    const res = await handleDelete(
      new Request("https://example.test/", { method }),
      deps,
    );
    assertEquals(res.status, 405, method);
    await res.body?.cancel();
  }
  const res = await handleDelete(
    post(JSON.stringify(GOOD), { "content-type": "text/plain" }),
    deps,
  );
  assertEquals(res.status, 415);
  await res.body?.cancel();
  assertEquals(authCalls(), 0);
  assertEquals(calls, { blockers: 0, deleteUser: 0 });
});

Deno.test("a caller who is not signed in is refused and nothing happens", async () => {
  const { deps, calls } = setup({ authenticated: false });
  const res = await handleDelete(post(GOOD), deps);
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(calls, { blockers: 0, deleteUser: 0 });
});

Deno.test("a huge body is refused as too large", async () => {
  const { deps, calls } = setup();
  const res = await handleDelete(
    post(JSON.stringify({ ...GOOD, pad: "x".repeat(2_000_000) })),
    deps,
  );
  assertEquals(res.status, 413);
  await res.body?.cancel();
  assertEquals(calls, { blockers: 0, deleteUser: 0 });
});

Deno.test("the only owner of a gym with members is told, and nothing is deleted", async () => {
  const { deps, calls } = setup({
    blockers: () =>
      Promise.resolve({
        data: { blocked: true, gyms: [{ id: "g1", name: GYM_NAME }] },
        errorCode: null,
      }),
  });
  const res = await handleDelete(post(GOOD), deps);
  assertEquals(res.status, 409);
  assertEquals(await res.json(), {
    ok: false,
    error: "last_owner",
    gyms: [{ name: GYM_NAME }],
  });
  assertEquals(calls, { blockers: 1, deleteUser: 0 });
});

Deno.test("a gym name is cut to 60 characters and ids are not passed on", async () => {
  const { deps } = setup({
    blockers: () =>
      Promise.resolve({
        data: {
          blocked: true,
          gyms: [{ id: "internal-id", name: "x".repeat(500) }],
        },
        errorCode: null,
      }),
  });
  const json = await (await handleDelete(post(GOOD), deps)).json();
  assertEquals(json.gyms[0].name.length, 60);
  assertEquals("id" in json.gyms[0], false);
});

Deno.test("a malformed or failed blockers answer stops everything (500, no deletion)", async () => {
  const answers: Array<{ data: unknown; errorCode: string | null }> = [
    { data: null, errorCode: "XX000" },
    { data: null, errorCode: null },
    { data: "x", errorCode: null },
    { data: {}, errorCode: null },
    { data: { blocked: "false", gyms: [] }, errorCode: null },
    { data: { blocked: false }, errorCode: null },
    { data: { blocked: false, gyms: [1] }, errorCode: null },
    { data: { blocked: false, gyms: [{ name: 5 }] }, errorCode: null },
  ];
  for (const answer of answers) {
    const { deps, calls } = setup({ blockers: () => Promise.resolve(answer) });
    const res = await handleDelete(post(GOOD), deps);
    assertEquals(res.status, 500, JSON.stringify(answer));
    assertEquals((await res.json()).error, "server_error");
    assertEquals(
      calls.deleteUser,
      0,
      "must not delete when the check did not pass",
    );
  }
  const thrown = setup({
    blockers: () => Promise.reject(new Error(SECRET_USER)),
  });
  const res = await handleDelete(post(GOOD), thrown.deps);
  assertEquals(res.status, 500);
  assertEquals((await res.text()).includes(SECRET_USER), false);
  assertEquals(thrown.calls.deleteUser, 0);
});

Deno.test("a failed deletion is a bare 500; 'already gone' is a success", async () => {
  const failed = setup({
    deleteUser: () =>
      Promise.resolve({ errorCode: "unexpected_failure", notFound: false }),
  });
  const res = await handleDelete(post(GOOD), failed.deps);
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { ok: false, error: "server_error" });

  const thrown = setup({
    deleteUser: () => Promise.reject(new Error(SECRET_TOKEN)),
  });
  const res2 = await handleDelete(post(GOOD), thrown.deps);
  assertEquals(res2.status, 500);
  assertEquals((await res2.text()).includes(SECRET_TOKEN), false);

  const gone = setup({
    deleteUser: () =>
      Promise.resolve({ errorCode: "user_not_found", notFound: true }),
  });
  const res3 = await handleDelete(post(GOOD), gone.deps);
  assertEquals(res3.status, 200, "a retry after a lost answer must succeed");
});

Deno.test("every response is no-store, nosniff and has no CORS header", async () => {
  const { deps } = setup();
  for (
    const res of [
      await handleDelete(post(GOOD), deps),
      await handleDelete(post("nope"), deps),
      await handleDelete(
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

Deno.test("nothing secret is ever logged: not the user id, token or gym name", async () => {
  const log = await captureConsole(async () => {
    const blocked = setup({
      blockers: () =>
        Promise.resolve({
          data: { blocked: true, gyms: [{ name: GYM_NAME }] },
          errorCode: null,
        }),
    });
    await (await handleDelete(post(GOOD), blocked.deps)).text();
    const bad = setup({
      blockers: () => Promise.resolve({ data: null, errorCode: "XX000" }),
    });
    await (await handleDelete(post(GOOD), bad.deps)).text();
    const boom = setup({
      deleteUser: () =>
        Promise.reject(new Error(`${SECRET_USER} ${SECRET_TOKEN}`)),
    });
    await (await handleDelete(post(GOOD), boom.deps)).text();
    const failed = setup({
      deleteUser: () =>
        Promise.resolve({ errorCode: "unexpected_failure", notFound: false }),
    });
    await (await handleDelete(post(GOOD), failed.deps)).text();
  });
  assert(log !== "", "the error paths log a fixed text");
  for (const secret of [SECRET_USER, SECRET_TOKEN, GYM_NAME, "Bearer"]) {
    assertEquals(
      log.includes(secret),
      false,
      `the log must not contain ${secret}`,
    );
  }
});
