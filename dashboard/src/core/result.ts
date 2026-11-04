import { toFailure, type Failure } from './failure';

export type Result<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly failure: Failure };

export const ok = <T>(value: T): Result<T> => ({ ok: true, value });
export const failed = <T = never>(failure: Failure): Result<T> => ({ ok: false, failure });

/** Runs a call and never throws: errors become a Failure. */
export async function guard<T>(run: () => Promise<T>): Promise<Result<T>> {
  try {
    return ok(await run());
  } catch (error: unknown) {
    return failed(toFailure(error));
  }
}

/** supabase-js returns `{ data, error }`; this throws the error so guard() classifies it. */
export function unwrap<T>(response: { data: T; error: unknown }): T {
  // Supabase errors are plain objects; toFailure() reads their code/status.
  // eslint-disable-next-line @typescript-eslint/only-throw-error
  if (response.error) throw response.error;
  return response.data;
}
