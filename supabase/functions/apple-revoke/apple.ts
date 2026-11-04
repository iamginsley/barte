// Revokes a user's Sign in with Apple link (App Store Review Guideline 5.1.1(v)).
// The app sends a fresh authorization code from a re-authentication right before account deletion,
// so no Apple tokens ever need to be stored.
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

export interface AppleConfig {
  teamId: string;
  keyId: string;
  clientId: string; // the app's bundle ID
  privateKey: string; // contents of the AuthKey_XXXX.p8 file
}

export class AppleError extends Error {
  constructor(readonly code: "token_exchange_failed" | "revoke_failed" | "no_token", readonly status?: number) {
    super(code);
  }
}

const APPLE = "https://appleid.apple.com";

/** ES256 client secret JWT as Apple requires, valid for five minutes. */
export async function clientSecret(config: AppleConfig, now = Date.now()): Promise<string> {
  const key = await importPKCS8(config.privateKey.trim(), "ES256");
  const issuedAt = Math.floor(now / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setSubject(config.clientId)
    .setAudience(APPLE)
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + 300)
    .sign(key);
}

async function post(fetchImpl: typeof fetch, path: string, params: Record<string, string>) {
  return await fetchImpl(`${APPLE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
}

/** Exchanges the authorization code for tokens and revokes them right away. */
export async function revokeWithAuthorizationCode(
  code: string,
  config: AppleConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const secret = await clientSecret(config);

  const tokenResponse = await post(fetchImpl, "/auth/token", {
    client_id: config.clientId,
    client_secret: secret,
    code,
    grant_type: "authorization_code",
  });
  if (!tokenResponse.ok) throw new AppleError("token_exchange_failed", tokenResponse.status);

  const tokens = await tokenResponse.json() as { refresh_token?: string; access_token?: string };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) throw new AppleError("no_token");

  const revokeResponse = await post(fetchImpl, "/auth/revoke", {
    client_id: config.clientId,
    client_secret: secret,
    token,
    token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
  });
  if (!revokeResponse.ok) throw new AppleError("revoke_failed", revokeResponse.status);
}
