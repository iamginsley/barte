import { assertEquals, assertMatch } from "jsr:@std/assert@1.0.8";
import { decodeProtectedHeader, exportPKCS8, generateKeyPair } from "npm:jose@5.9.6";
import { type ApnsConfig, payload, resetTokenCache, send } from "./apns.ts";
import { compose, money } from "./messages.ts";

const group = { group: "WG Leopoldstraße", groupId: "11111111-2222-3333-4444-555555555555", currency: "EUR" };

Deno.test("amounts use German formatting in the group's currency", () => {
  assertEquals(money(6400, "EUR"), "64,00 €");
  assertEquals(money(123456, "EUR"), "1.234,56 €");
  assertEquals(money(2850, "GBP"), "28,50 £");
});

Deno.test("expense messages depend on who paid", () => {
  const expense = { kind: "expense_added" as const, ...group, actor: "Anna", title: "Tanken", amountCents: 6400 };
  const paidByActor = compose({ ...expense, payer: { type: "actor" } });
  assertEquals(paidByActor.title, "WG Leopoldstraße");
  assertEquals(paidByActor.body, "Anna hat „Tanken“ bezahlt: 64,00 €");
  assertEquals(paidByActor.link, `barte://group/${group.groupId}`);
  assertEquals(paidByActor.threadId, group.groupId);

  assertEquals(compose({ ...expense, payer: { type: "recipient" } }).body,
    "Anna hat „Tanken“ eingetragen, bezahlt von dir: 64,00 €");
  assertEquals(compose({ ...expense, payer: { type: "other", name: "Ben" } }).body,
    "Anna hat „Tanken“ eingetragen, bezahlt von Ben: 64,00 €");
});

Deno.test("settlement messages for the one who got the money and the one who paid", () => {
  const settlement = { kind: "settlement_added" as const, ...group, amountCents: 2000, from: "Max", to: "Lena" };
  assertEquals(compose({ ...settlement, actor: "Max", actorIsFrom: true, recipient: "to" }).body,
    "Max hat dir 20,00 € zurückgezahlt.");
  assertEquals(compose({ ...settlement, actor: "Dominik", actorIsFrom: false, recipient: "to" }).body,
    "Dominik hat verbucht: Max hat dir 20,00 € zurückgezahlt.");
  const toPayer = compose({ ...settlement, actor: "Lena", actorIsFrom: false, recipient: "from" });
  assertEquals(toPayer.body, "Lena hat verbucht: Du hast Lena 20,00 € zurückgezahlt.");
  assertEquals(toPayer.passive, true);
});

Deno.test("passive messages stay silent", () => {
  const settlement = { kind: "settlement_added" as const, ...group, amountCents: 2000, from: "Max", to: "Lena" };
  const quiet = payload(compose({ ...settlement, actor: "Lena", actorIsFrom: false, recipient: "from" }));
  assertEquals(quiet.aps["interruption-level"], "passive");
  assertEquals(quiet.aps.sound, undefined);
  const loud = payload(compose({ ...settlement, actor: "Max", actorIsFrom: true, recipient: "to" }));
  assertEquals(loud.aps.sound, "default");
});

async function testConfig(): Promise<ApnsConfig> {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  return { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: await exportPKCS8(privateKey), topic: "com.iamginsley.barte" };
}

Deno.test("APNs request: host, headers and token", async () => {
  resetTokenCache();
  const config = await testConfig();
  let seen: { url: string; headers: Record<string, string>; body: string } | undefined;
  const fakeFetch = (async (url: string, init: RequestInit) => {
    seen = { url, headers: init.headers as Record<string, string>, body: init.body as string };
    return new Response(null, { status: 200 });
  }) as unknown as typeof fetch;

  const message = compose({ kind: "expense_added", ...group, actor: "Anna", title: "Tanken", amountCents: 6400, payer: { type: "actor" } });
  const outcome = await send({ token: "ab".repeat(32), environment: "sandbox" }, message, config, fakeFetch);

  assertEquals(outcome, "sent");
  assertEquals(seen!.url, `https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
  assertEquals(seen!.headers["apns-topic"], "com.iamginsley.barte");
  assertEquals(seen!.headers["apns-push-type"], "alert");
  assertMatch(seen!.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assertEquals(decodeProtectedHeader(seen!.headers.authorization.slice(7)), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(JSON.parse(seen!.body).link, `barte://group/${group.groupId}`);
});

Deno.test("APNs: unregistered devices are reported as gone", async () => {
  resetTokenCache();
  const config = await testConfig();
  const respond = (status: number, reason: string) =>
    (async () => new Response(JSON.stringify({ reason }), { status })) as unknown as typeof fetch;
  const message = compose({ kind: "expense_added", ...group, actor: "Anna", title: "X", amountCents: 100, payer: { type: "actor" } });
  const device = { token: "cd".repeat(32), environment: "production" as const };

  assertEquals(await send(device, message, config, respond(410, "Unregistered")), "gone");
  assertEquals(await send(device, message, config, respond(400, "BadDeviceToken")), "gone");
  assertEquals(await send(device, message, config, respond(500, "InternalServerError")), "failed");
});
