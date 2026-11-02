// Shared by the Edge Functions: read a small JSON body without trusting its
// size. (`_shared` is not deployed as a function of its own.)

/** A request body is a tiny JSON object; anything bigger is refused unread. */
export const MAX_BODY_BYTES = 1024;

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
