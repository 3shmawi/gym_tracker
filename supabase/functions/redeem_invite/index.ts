// Edge Function `redeem_invite` — see handler.ts for what it does and
// supabase/functions/redeem_invite/README.md for how it is deployed.
//
// The caller's session is the anonymous (or permanent) Supabase Auth session
// the app already has; this function does not mint sessions. It verifies the
// JWT, then calls redeem_invite_core with the secret key supplied by the
// platform (never by us), passing the verified user id.
import { createSupabaseContext } from "@supabase/server";
import { type Caller, handleRedeem } from "./handler.ts";

async function authenticate(req: Request): Promise<Caller | null> {
  const { data: ctx, error } = await createSupabaseContext(req, {
    auth: "user",
  });
  if (error || ctx === null || !ctx.userClaims) return null;
  const admin = ctx.supabaseAdmin;
  return {
    userId: ctx.userClaims.id,
    async redeem({ userId, code, installId, ip }) {
      const { data, error: rpcError } = await admin.rpc("redeem_invite_core", {
        p_auth_user_id: userId,
        p_code: code,
        p_install_id: installId,
        p_ip: ip,
      });
      return {
        data,
        errorCode: rpcError ? (rpcError.code || "unknown") : null,
      };
    },
  };
}

export default {
  fetch: (req: Request) => handleRedeem(req, { authenticate }),
};
