import { assertEquals } from "@std/assert";
import {
  clientIp,
  MAX_BODY_BYTES,
  normalizeCode,
  normalizeUuid,
  parseRedeemBody,
  readJsonBody,
} from "./validate.ts";

const UUID = "123e4567-e89b-42d3-a456-426614174000";

Deno.test("normalizeCode accepts a well-formed code in any case, trimmed", () => {
  assertEquals(normalizeCode("ABC234"), "ABC234");
  assertEquals(normalizeCode("abc234"), "ABC234");
  assertEquals(normalizeCode("  hjk2mn \n"), "HJK2MN");
});

Deno.test("normalizeCode refuses everything else", () => {
  const hostile: unknown[] = [
    // wrong types
    undefined,
    null,
    123456,
    true,
    {},
    [],
    ["ABC234"],
    { toString: () => "ABC234" },
    12n,
    // wrong length
    "",
    "ABC23",
    "ABC2345",
    " ",
    // letters and digits that are not in the alphabet (0 O 1 I L)
    "ABC230",
    "ABC23O",
    "ABC231",
    "ABC23I",
    "ABC23L",
    // characters that could fold into a valid letter or look like one
    "ſſſſſſ",
    "ßßßßßß",
    "ＡＢＣ２３４",
    "ÄBC234",
    "ABC23٤",
    "ı23456",
    // injection-like and structured text
    "<script>",
    "'; drop table invites; --",
    "ABC234;",
    "ABC-234",
    "ABC 234",
    "https://evil.example",
    "javascript:1",
    "%41%42%43%32%33%34",
    "A\u0000BC234",
    "ABC234\u0000",
    "ABC\n234",
    "../../etc",
    // huge
    "A".repeat(33),
    "A".repeat(1_000_000),
  ];
  for (const value of hostile) {
    assertEquals(
      normalizeCode(value),
      null,
      `should refuse ${String(value).slice(0, 40)}`,
    );
  }
});

Deno.test("normalizeUuid accepts a uuid and lower-cases it", () => {
  assertEquals(normalizeUuid(UUID), UUID);
  assertEquals(normalizeUuid(UUID.toUpperCase()), UUID);
});

Deno.test("normalizeUuid refuses non-uuids", () => {
  for (
    const value of [
      undefined,
      null,
      1,
      {},
      [],
      "",
      "abc",
      UUID + "0",
      UUID.slice(1),
      "x".repeat(10_000),
      "123e4567-e89b-42d3-a456-42661417400g",
      `${UUID}'; --`,
      `{${UUID}}`,
      UUID.replaceAll("-", ""),
    ]
  ) {
    assertEquals(
      normalizeUuid(value),
      null,
      `should refuse ${String(value).slice(0, 40)}`,
    );
  }
});

Deno.test("parseRedeemBody needs exactly code and install_id", () => {
  assertEquals(parseRedeemBody({ code: "abc234", install_id: UUID }), {
    ok: true,
    value: { code: "ABC234", installId: UUID },
  });
  const bad: unknown[] = [
    null,
    undefined,
    "x",
    1,
    [],
    [UUID],
    {},
    { code: "ABC234" },
    { install_id: UUID },
    { code: "ABC234", install_id: UUID, extra: 1 },
    { code: "ABC234", install_id: UUID, is_admin: true },
    { code: 123456, install_id: UUID },
    { code: "ABC234", install_id: 7 },
    { code: ["ABC234"], install_id: UUID },
    { code: "ABC234", install_id: { a: 1 } },
    { code: null, install_id: null },
    { Code: "ABC234", install_id: UUID },
  ];
  for (const body of bad) {
    assertEquals(parseRedeemBody(body), { ok: false }, JSON.stringify(body));
  }
});

Deno.test("a __proto__ key in the JSON cannot smuggle fields in", () => {
  const body = JSON.parse(
    `{"__proto__":{"code":"ABC234"},"install_id":"${UUID}"}`,
  );
  assertEquals(parseRedeemBody(body), { ok: false });
  assertEquals(({} as Record<string, unknown>).code, undefined);
});

function request(body: BodyInit | null, headers: HeadersInit = {}) {
  return new Request("https://example.test/redeem_invite", {
    method: "POST",
    body,
    headers,
  });
}

Deno.test("readJsonBody parses a small JSON body", async () => {
  const res = await readJsonBody(request(`{"a":1}`));
  assertEquals(res, { ok: true, value: { a: 1 } });
});

Deno.test("readJsonBody refuses a declared-too-large body without reading it", async () => {
  const res = await readJsonBody(
    request("{}", { "content-length": String(MAX_BODY_BYTES + 1) }),
  );
  assertEquals(res, { ok: false, reason: "too_large" });
});

Deno.test("readJsonBody stops reading a streamed body that grows past the cap", async () => {
  let pulled = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulled++;
      controller.enqueue(new TextEncoder().encode("x".repeat(512)));
      if (pulled > 1000) controller.close();
    },
  });
  const res = await readJsonBody(request(stream));
  assertEquals(res, { ok: false, reason: "too_large" });
  assertEquals(pulled < 10, true, "must not read the whole stream");
});

Deno.test("readJsonBody refuses malformed bodies", async () => {
  for (
    const body of ["", "{", "not json", `{"a":`, "\u0000", "[1,2", "{'a':1}"]
  ) {
    assertEquals((await readJsonBody(request(body))).ok, false, body);
  }
  assertEquals(
    await readJsonBody(request(new Uint8Array([0xff, 0xfe, 0x7b, 0x7d]))),
    {
      ok: false,
      reason: "invalid_json",
    },
  );
  assertEquals(
    await readJsonBody(
      new Request("https://example.test/", { method: "POST" }),
    ),
    {
      ok: false,
      reason: "invalid_json",
    },
  );
});

Deno.test("clientIp prefers the edge's header and the last forwarded hop", () => {
  assertEquals(
    clientIp(new Headers({ "cf-connecting-ip": "203.0.113.9" })),
    "203.0.113.9",
  );
  assertEquals(
    clientIp(new Headers({ "x-forwarded-for": "6.6.6.6, 203.0.113.7" })),
    "203.0.113.7",
  );
  assertEquals(clientIp(new Headers()), "unknown");
  assertEquals(
    clientIp(new Headers({ "x-forwarded-for": "9".repeat(500) })).length,
    64,
  );
});
