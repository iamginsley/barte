// POST { "authorization_code": "..." } with the user's Supabase JWT (verify_jwt is on).
import { AppleError, revokeWithAuthorizationCode } from "./apple.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const config = {
    teamId: Deno.env.get("APPLE_TEAM_ID") ?? "",
    keyId: Deno.env.get("APPLE_KEY_ID") ?? "",
    clientId: Deno.env.get("APPLE_CLIENT_ID") ?? "",
    privateKey: Deno.env.get("APPLE_PRIVATE_KEY") ?? "",
  };
  if (Object.values(config).some((value) => !value)) {
    console.error("apple-revoke: APPLE_* secrets are missing");
    return json({ error: "not_configured" }, 500);
  }

  let code: unknown;
  try {
    ({ authorization_code: code } = await request.json());
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (typeof code !== "string" || code.length === 0) return json({ error: "missing_authorization_code" }, 400);

  try {
    await revokeWithAuthorizationCode(code, config);
    return json({ revoked: true });
  } catch (error) {
    if (error instanceof AppleError) {
      console.error(`apple-revoke: ${error.code} (${error.status ?? "-"})`);
      return json({ error: error.code }, 502);
    }
    console.error("apple-revoke: unexpected error", error);
    return json({ error: "internal" }, 500);
  }
});
