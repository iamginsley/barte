import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.13";
import { exportPKCS8, generateKeyPair, jwtVerify } from "npm:jose@5.9.6";
import { AppleError, clientSecret, revokeWithAuthorizationCode } from "./apple.ts";

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

Deno.test("client secret is an ES256 JWT with Apple's claims", async () => {
  const { config, publicKey } = await testConfig();
  const now = Date.UTC(2026, 9, 29);
  const jwt = await clientSecret(config, now);
  const { payload, protectedHeader } = await jwtVerify(jwt, publicKey, {
    issuer: "TEAM123456",
    audience: "https://appleid.apple.com",
    currentDate: new Date(now),
  });
  assertEquals(protectedHeader, { alg: "ES256", kid: "KEY1234567" });
  assertEquals(payload.sub, "com.iamginsley.barte");
  assertEquals(payload.exp! - payload.iat!, 300);
});

Deno.test("exchanges the code and revokes the refresh token", async () => {
  const { config } = await testConfig();
  const apple = fakeApple({
    "/auth/token": Response.json({ access_token: "a", refresh_token: "r" }),
    "/auth/revoke": new Response(null, { status: 200 }),
  });
  await revokeWithAuthorizationCode("code-1", config, apple.fetchImpl);

  assertEquals(apple.calls.map((call) => call.path), ["/auth/token", "/auth/revoke"]);
  assertEquals(apple.calls[0].body.get("code"), "code-1");
  assertEquals(apple.calls[0].body.get("grant_type"), "authorization_code");
  assertEquals(apple.calls[1].body.get("token"), "r");
  assertEquals(apple.calls[1].body.get("token_type_hint"), "refresh_token");
  assert(apple.calls.every((call) => call.body.get("client_id") === "com.iamginsley.barte"));
});

Deno.test("falls back to the access token when Apple returns no refresh token", async () => {
  const { config } = await testConfig();
  const apple = fakeApple({
    "/auth/token": Response.json({ access_token: "a" }),
    "/auth/revoke": new Response(null, { status: 200 }),
  });
  await revokeWithAuthorizationCode("code-2", config, apple.fetchImpl);
  assertEquals(apple.calls[1].body.get("token_type_hint"), "access_token");
});

Deno.test("fails loudly when Apple rejects the code or the revocation", async () => {
  const { config } = await testConfig();
  const badCode = fakeApple({ "/auth/token": Response.json({ error: "invalid_grant" }, { status: 400 }) });
  const error = await assertRejects(() => revokeWithAuthorizationCode("expired", config, badCode.fetchImpl), AppleError);
  assertEquals(error.code, "token_exchange_failed");
  assertEquals(badCode.calls.length, 1);

  const badRevoke = fakeApple({
    "/auth/token": Response.json({ refresh_token: "r" }),
    "/auth/revoke": new Response(null, { status: 500 }),
  });
  const revokeError = await assertRejects(() => revokeWithAuthorizationCode("c", config, badRevoke.fetchImpl), AppleError);
  assertEquals(revokeError.code, "revoke_failed");
});
