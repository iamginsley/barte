import { expect, test } from "vitest";
import { exportPKCS8, generateKeyPair, jwtVerify } from "jose";
import { AppleError, clientSecret, revokeWithAuthorizationCode } from "../_lib/apple";

async function testConfig() {
  const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
  return {
    publicKey,
    config: { teamId: "TEAM123456", keyId: "KEY1234567", clientId: "com.iamginsley.barte", privateKey: await exportPKCS8(privateKey) },
  };
}

function fakeApple(responses: Record<string, Response>) {
  const calls: { path: string; body: URLSearchParams }[] = [];
  const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
    const path = new URL(String(input)).pathname;
    calls.push({ path, body: new URLSearchParams(String(init?.body)) });
    return responses[path] ?? new Response("not found", { status: 404 });
  }) as typeof fetch;
  return { calls, fetchImpl };
}

test("client secret is an ES256 JWT with Apple's claims", async () => {
  const { config, publicKey } = await testConfig();
  const now = Date.UTC(2026, 9, 29);
  const jwt = await clientSecret(config, now);
  const { payload, protectedHeader } = await jwtVerify(jwt, publicKey, {
    issuer: "TEAM123456",
    audience: "https://appleid.apple.com",
    currentDate: new Date(now),
  });
  expect(protectedHeader).toEqual({ alg: "ES256", kid: "KEY1234567" });
  expect(payload.sub).toEqual("com.iamginsley.barte");
  expect(payload.exp! - payload.iat!).toEqual(300);
});

test("exchanges the code and revokes the refresh token", async () => {
  const { config } = await testConfig();
  const apple = fakeApple({
    "/auth/token": Response.json({ access_token: "a", refresh_token: "r" }),
    "/auth/revoke": new Response(null, { status: 200 }),
  });
  await revokeWithAuthorizationCode("code-1", config, apple.fetchImpl);

  expect(apple.calls.map((call) => call.path)).toEqual(["/auth/token", "/auth/revoke"]);
  expect(apple.calls[0].body.get("code")).toEqual("code-1");
  expect(apple.calls[0].body.get("grant_type")).toEqual("authorization_code");
  expect(apple.calls[1].body.get("token")).toEqual("r");
  expect(apple.calls[1].body.get("token_type_hint")).toEqual("refresh_token");
  expect(apple.calls.every((call) => call.body.get("client_id") === "com.iamginsley.barte")).toBe(true);
});

test("falls back to the access token when Apple returns no refresh token", async () => {
  const { config } = await testConfig();
  const apple = fakeApple({
    "/auth/token": Response.json({ access_token: "a" }),
    "/auth/revoke": new Response(null, { status: 200 }),
  });
  await revokeWithAuthorizationCode("code-2", config, apple.fetchImpl);
  expect(apple.calls[1].body.get("token_type_hint")).toEqual("access_token");
});

test("fails loudly when Apple rejects the code or the revocation", async () => {
  const { config } = await testConfig();
  const badCode = fakeApple({ "/auth/token": Response.json({ error: "invalid_grant" }, { status: 400 }) });
  await expect(revokeWithAuthorizationCode("expired", config, badCode.fetchImpl)).rejects.toMatchObject({ code: "token_exchange_failed" });
  expect(badCode.calls.length).toEqual(1);

  const badRevoke = fakeApple({
    "/auth/token": Response.json({ refresh_token: "r" }),
    "/auth/revoke": new Response(null, { status: 500 }),
  });
  await expect(revokeWithAuthorizationCode("c", config, badRevoke.fetchImpl)).rejects.toEqual(new AppleError("revoke_failed", 500));
});
