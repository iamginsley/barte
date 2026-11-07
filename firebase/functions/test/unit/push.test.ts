import { expect, test } from "vitest";
import { decodeProtectedHeader, exportPKCS8, generateKeyPair } from "jose";
import { type ApnsConfig, payload, resetTokenCache, send } from "../../src/push/apns.js";
import { compose, money } from "../../src/push/messages.js";

const group = { group: "WG Leopoldstraße", groupId: "11111111-2222-3333-4444-555555555555", currency: "EUR" };

test("amounts use German formatting in the group's currency", () => {
  expect(money(6400, "EUR")).toEqual("64,00 €");
  expect(money(123456, "EUR")).toEqual("1.234,56 €");
  expect(money(2850, "GBP")).toEqual("28,50 £");
});

test("expense messages depend on who paid", () => {
  const expense = { kind: "expense_added" as const, ...group, actor: "Anna", title: "Tanken", amountCents: 6400 };
  const paidByActor = compose({ ...expense, payer: { type: "actor" } });
  expect(paidByActor.title).toEqual("WG Leopoldstraße");
  expect(paidByActor.body).toEqual("Anna hat „Tanken“ bezahlt: 64,00 €");
  expect(paidByActor.link).toEqual(`barte://group/${group.groupId}`);
  expect(paidByActor.threadId).toEqual(group.groupId);

  expect(compose({ ...expense, payer: { type: "recipient" } }).body).toEqual("Anna hat „Tanken“ eingetragen, bezahlt von dir: 64,00 €");
  expect(compose({ ...expense, payer: { type: "other", name: "Ben" } }).body).toEqual("Anna hat „Tanken“ eingetragen, bezahlt von Ben: 64,00 €");
});

test("settlement messages for the one who got the money and the one who paid", () => {
  const settlement = { kind: "settlement_added" as const, ...group, amountCents: 2000, from: "Max", to: "Lena" };
  expect(compose({ ...settlement, actor: "Max", actorIsFrom: true, recipient: "to" }).body).toEqual("Max hat dir 20,00 € zurückgezahlt.");
  expect(compose({ ...settlement, actor: "Dominik", actorIsFrom: false, recipient: "to" }).body).toEqual("Dominik hat verbucht: Max hat dir 20,00 € zurückgezahlt.");
  const toPayer = compose({ ...settlement, actor: "Lena", actorIsFrom: false, recipient: "from" });
  expect(toPayer.body).toEqual("Lena hat verbucht: Du hast Lena 20,00 € zurückgezahlt.");
  expect(toPayer.passive).toEqual(true);
});

test("passive messages stay silent", () => {
  const settlement = { kind: "settlement_added" as const, ...group, amountCents: 2000, from: "Max", to: "Lena" };
  const quiet = payload(compose({ ...settlement, actor: "Lena", actorIsFrom: false, recipient: "from" }));
  expect(quiet.aps["interruption-level"]).toEqual("passive");
  expect(quiet.aps.sound).toEqual(undefined);
  const loud = payload(compose({ ...settlement, actor: "Max", actorIsFrom: true, recipient: "to" }));
  expect(loud.aps.sound).toEqual("default");
});

async function testConfig(): Promise<ApnsConfig> {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  return { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: await exportPKCS8(privateKey), topic: "com.iamginsley.barte" };
}

test("APNs request: host, headers and token", async () => {
  resetTokenCache();
  const config = await testConfig();
  let seen: { url: string; headers: Record<string, string>; body: string } | undefined;
  const fakeFetch = (async (url: string, init: RequestInit) => {
    seen = { url, headers: init.headers as Record<string, string>, body: init.body as string };
    return new Response(null, { status: 200 });
  }) as unknown as typeof fetch;

  const message = compose({ kind: "expense_added", ...group, actor: "Anna", title: "Tanken", amountCents: 6400, payer: { type: "actor" } });
  const outcome = await send({ token: "ab".repeat(32), environment: "sandbox" }, message, config, fakeFetch);

  expect(outcome).toEqual("sent");
  expect(seen!.url).toEqual(`https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
  expect(seen!.headers["apns-topic"]).toEqual("com.iamginsley.barte");
  expect(seen!.headers["apns-push-type"]).toEqual("alert");
  expect(seen!.headers.authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  expect(decodeProtectedHeader(seen!.headers.authorization.slice(7))).toEqual({ alg: "ES256", kid: "KEY1234567" });
  expect(JSON.parse(seen!.body).link).toEqual(`barte://group/${group.groupId}`);
});

test("APNs: unregistered devices are reported as gone", async () => {
  resetTokenCache();
  const config = await testConfig();
  const respond = (status: number, reason: string) =>
    (async () => new Response(JSON.stringify({ reason }), { status })) as unknown as typeof fetch;
  const message = compose({ kind: "expense_added", ...group, actor: "Anna", title: "X", amountCents: 100, payer: { type: "actor" } });
  const device = { token: "cd".repeat(32), environment: "production" as const };

  expect(await send(device, message, config, respond(410, "Unregistered"))).toEqual("gone");
  expect(await send(device, message, config, respond(400, "BadDeviceToken"))).toEqual("gone");
  expect(await send(device, message, config, respond(500, "InternalServerError"))).toEqual("failed");
});
