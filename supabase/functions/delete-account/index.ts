// Edge Function `delete-account` — see handler.ts. Deployed with
// verify_jwt = true (supabase/config.toml); the secret key is provided by the
// platform, our code reads no secret.
import { createSupabaseContext } from "@supabase/server";
import { type Caller, handleDelete } from "./handler.ts";

async function authenticate(req: Request): Promise<Caller | null> {
  const { data: ctx, error } = await createSupabaseContext(req, {
    auth: "user",
  });
  if (error || ctx === null || !ctx.userClaims) return null;
  const admin = ctx.supabaseAdmin;
  const userId = ctx.userClaims.id;
  return {
    userId,
    async blockers() {
      const { data, error: rpcError } = await admin.rpc(
        "account_deletion_blockers",
        {
          p_auth_user_id: userId,
        },
      );
      return {
        data,
        errorCode: rpcError ? (rpcError.code || "unknown") : null,
      };
    },
    async deleteUser() {
      // Hard delete (shouldSoftDelete = false): auth.users goes, and with it
      // everything that hangs off it by cascade.
      const { error: deleteError } = await admin.auth.admin.deleteUser(
        userId,
        false,
      );
      if (!deleteError) return { errorCode: null, notFound: false };
      const code = deleteError.code ?? "unknown";
      return {
        errorCode: code,
        notFound: code === "user_not_found" || deleteError.status === 404,
      };
    },
  };
}

export default {
  fetch: (req: Request) => handleDelete(req, { authenticate }),
};
