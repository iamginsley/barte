// POST { "authorization_code": "..." } with the user's Nhost access token, right before the app
// deletes the account (App Store Review Guideline 5.1.1(v)). Revokes the Sign in with Apple link.
import type { Request, Response } from "express";
import { AppleError, revokeWithAuthorizationCode } from "./_lib/apple";
import { callerID } from "./_lib/server";

export default async (req: Request, res: Response) => {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  if (!(await callerID(req))) return res.status(401).json({ error: "unauthorized" });

  const config = {
    teamId: process.env.APPLE_TEAM_ID ?? "",
    keyId: process.env.APPLE_KEY_ID ?? "",
    clientId: process.env.APPLE_CLIENT_ID ?? "",
    privateKey: process.env.APPLE_PRIVATE_KEY ?? "",
  };
  if (Object.values(config).some((value) => !value || value === "FIXME")) {
    console.error("apple-revoke: APPLE_* secrets are missing");
    return res.status(500).json({ error: "not_configured" });
  }

  const code = (req.body ?? {}).authorization_code;
  if (typeof code !== "string" || code.length === 0) return res.status(400).json({ error: "missing_authorization_code" });

  try {
    await revokeWithAuthorizationCode(code, config);
    return res.json({ revoked: true });
  } catch (error) {
    if (error instanceof AppleError) {
      console.error(`apple-revoke: ${error.code} (${error.status ?? "-"})`);
      return res.status(502).json({ error: error.code });
    }
    console.error("apple-revoke: unexpected error", error);
    return res.status(500).json({ error: "internal" });
  }
};
