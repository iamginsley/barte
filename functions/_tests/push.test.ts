// Wording, APNs requests and who gets which push.
import { decodeProtectedHeader, exportJWK, exportPKCS8, generateKeyPair, SignJWT, createLocalJWKSet } from "jose";
import type { Request } from "express";
import { expect, test } from "vitest";
import { type ApnsConfig, type Device, payload, resetTokenCache, send, type Transport } from "../_lib/apns";
import { compose, type Message, money } from "../_lib/messages";
import { apnsConfig, notifyGroup, uuidArray } from "../_lib/notify";
import { callerID, type GraphQL } from "../_lib/server";

const group = { group: "WG Leopoldstraße", groupId: "11111111-2222-3333-4444-555555555555", currency: "EUR" };

test("amounts use German formatting in the group's currency", () => {
  expect(money(6400, "EUR")).toBe("64,00 €");
  expect(money(123456, "EUR")).toBe("1.234,56 €");
  expect(money(2850, "GBP")).toBe("28,50 £");
});

test("expense messages depend on who paid", () => {
  const expense = { kind: "expense_added" as const, ...group, actor: "Anna", title: "Tanken", amountCents: 6400 };
  const paidByActor = compose({ ...expense, payer: { type: "actor" } });
  expect(paidByActor.title).toBe("WG Leopoldstraße");
  expect(paidByActor.body).toBe("Anna hat „Tanken“ bezahlt: 64,00 €");
  expect(paidByActor.link).toBe(`barte://group/${group.groupId}`);
  expect(paidByActor.threadId).toBe(group.groupId);
  expect(compose({ ...expense, payer: { type: "recipient" } }).body).toBe("Anna hat „Tanken“ eingetragen, bezahlt von dir: 64,00 €");
  expect(compose({ ...expense, payer: { type: "other", name: "Ben" } }).body).toBe("Anna hat „Tanken“ eingetragen, bezahlt von Ben: 64,00 €");
});

test("settlement messages for the one who got the money and the one who paid", () => {
  const settlement = { kind: "settlement_added" as const, ...group, amountCents: 2000, from: "Max", to: "Lena" };
  expect(compose({ ...settlement, actor: "Max", actorIsFrom: true, recipient: "to" }).body).toBe("Max hat dir 20,00 € zurückgezahlt.");
  expect(compose({ ...settlement, actor: "Dominik", actorIsFrom: false, recipient: "to" }).body)
    .toBe("Dominik hat verbucht: Max hat dir 20,00 € zurückgezahlt.");
  const toPayer = compose({ ...settlement, actor: "Lena", actorIsFrom: false, recipient: "from" });
  expect(toPayer.body).toBe("Lena hat verbucht: Du hast Lena 20,00 € zurückgezahlt.");
  expect(toPayer.passive).toBe(true);
  expect(payload(toPayer).aps["interruption-level"]).toBe("passive");
  expect(payload(toPayer).aps.sound).toBeUndefined();
});

async function testConfig(): Promise<ApnsConfig> {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  return { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: await exportPKCS8(privateKey), topic: "com.iamginsley.barte" };
}

test("APNs request: host, headers and token", async () => {
  resetTokenCache();
  const config = await testConfig();
  let seen: { origin: string; path: string; headers: Record<string, string>; body: string } | undefined;
  const transport: Transport = async (origin, path, headers, body) => {
    seen = { origin, path, headers, body };
    return { status: 200, body: "" };
  };
  const message = compose({ kind: "expense_added", ...group, actor: "Anna", title: "Tanken", amountCents: 6400, payer: { type: "actor" } });
  expect(await send({ token: "ab".repeat(32), environment: "sandbox" }, message, config, transport)).toBe("sent");
  expect(seen!.origin).toBe("https://api.sandbox.push.apple.com");
  expect(seen!.path).toBe(`/3/device/${"ab".repeat(32)}`);
  expect(seen!.headers["apns-topic"]).toBe("com.iamginsley.barte");
  expect(seen!.headers["apns-push-type"]).toBe("alert");
  expect(decodeProtectedHeader(seen!.headers.authorization.slice(7))).toEqual({ alg: "ES256", kid: "KEY1234567" });
  expect(JSON.parse(seen!.body).link).toBe(`barte://group/${group.groupId}`);
});

test("APNs: unregistered devices are reported as gone", async () => {
  resetTokenCache();
  const config = await testConfig();
  const respond = (status: number, reason: string): Transport => async () => ({ status, body: JSON.stringify({ reason }) });
  const message = compose({ kind: "expense_added", ...group, actor: "Anna", title: "X", amountCents: 100, payer: { type: "actor" } });
  const device = { token: "cd".repeat(32), environment: "production" as const };
  expect(await send(device, message, config, respond(410, "Unregistered"))).toBe("gone");
  expect(await send(device, message, config, respond(400, "BadDeviceToken"))).toBe("gone");
  expect(await send(device, message, config, respond(500, "InternalServerError"))).toBe("failed");
});

test("APNs config falls back to the Apple key and ignores placeholders", () => {
  const env = { APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_PRIVATE_KEY: "P" };
  expect(apnsConfig(env)).toEqual({ teamId: "T", keyId: "K", privateKey: "P", topic: "com.iamginsley.barte" });
  expect(apnsConfig({ ...env, APNS_KEY_ID: "N", APNS_PRIVATE_KEY: "Q" })?.keyId).toBe("N");
  expect(apnsConfig({ ...env, APPLE_PRIVATE_KEY: "FIXME" })).toBeUndefined();
  expect(apnsConfig({})).toBeUndefined();
});

test("Postgres arrays are read in either form", () => {
  expect(uuidArray(["a", "b"])).toEqual(["a", "b"]);
  expect(uuidArray("{a,b}")).toEqual(["a", "b"]);
  expect(uuidArray("{}")).toEqual([]);
});

// Caller --------------------------------------------------------------------------

test("only valid Nhost tokens identify a caller", async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const keys = createLocalJWKSet({ keys: [{ ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" }] });
  const token = await new SignJWT({ "https://hasura.io/jwt/claims": { "x-hasura-user-id": "user-1" } })
    .setProtectedHeader({ alg: "RS256", kid: "k1" })
    .setExpirationTime("5m")
    .sign(privateKey);
  const request = (authorization?: string) => ({ headers: { authorization } }) as unknown as Request;

  expect(await callerID(request(`Bearer ${token}`), keys)).toBe("user-1");
  expect(await callerID(request(), keys)).toBeUndefined();
  expect(await callerID(request(`Bearer ${token}x`), keys)).toBeUndefined();
  const other = await generateKeyPair("RS256");
  const forged = await new SignJWT({ "https://hasura.io/jwt/claims": { "x-hasura-user-id": "user-1" } })
    .setProtectedHeader({ alg: "RS256", kid: "k1" })
    .sign(other.privateKey);
  expect(await callerID(request(`Bearer ${forged}`), keys)).toBeUndefined();
});

// Who gets a push --------------------------------------------------------------------

const ids = { anna: "m-anna", ben: "m-ben", clara: "m-clara" };
const members = [
  { id: ids.anna, name: "Anna", user_id: "u-anna" },
  { id: ids.ben, name: "Ben", user_id: "u-ben" },
  { id: ids.clara, name: "Clara", user_id: null },
];
const devices = [
  { token: "aa".repeat(32), environment: "sandbox", user_id: "u-anna" },
  { token: "bb".repeat(32), environment: "production", user_id: "u-ben" },
  { token: "bc".repeat(32), environment: "sandbox", user_id: "u-ben" },
];

/** A fake Hasura: the expense as the caller sees it, everyone's devices, and deletions. */
function fakeGraphQL(expense: Record<string, unknown> | null) {
  const calls: { query: string; variables: Record<string, unknown>; asUser?: string }[] = [];
  const gql = (async (query: string, variables: Record<string, unknown>, asUser?: string) => {
    calls.push({ query, variables, asUser });
    if (query.includes("expenses_by_pk")) {
      return { expenses_by_pk: expense && { group_id: group.groupId, group: { name: "WG", currency: "EUR", members }, ...expense } };
    }
    if (query.includes("query Devices")) {
      const users = variables.users as string[];
      return { device_tokens: devices.filter((d) => users.includes(d.user_id)) };
    }
    return { delete_device_tokens: { affected_rows: (variables.tokens as string[]).length } };
  }) as GraphQL;
  return { gql, calls };
}

function recorder(outcome: (device: Device) => "sent" | "gone" = () => "sent") {
  const sent: { device: Device; message: Message }[] = [];
  const sendImpl = (async (device: Device, message: Message) => {
    sent.push({ device, message });
    return outcome(device);
  }) as typeof send;
  return { sent, sendImpl };
}

const config = { teamId: "T", keyId: "K", privateKey: "unused", topic: "com.iamginsley.barte" };

test("the others involved get a push, the one who entered it doesn't", async () => {
  const { gql, calls } = fakeGraphQL({ title: "Pizza", amount_cents: 3000, payer_id: ids.anna, participant_ids: [ids.anna, ids.ben], is_settlement: false });
  const { sent, sendImpl } = recorder();
  const result = await notifyGroup(gql, "u-anna", "expense_added", "e1", config, sendImpl);
  expect(result).toEqual({ status: 200, body: { sent: 2, removed: 0 } });
  expect(calls[0].asUser).toBe("u-anna"); // the expense is read with the caller's permissions
  expect(calls[1].asUser).toBeUndefined(); // devices only as admin
  expect(sent.map((s) => s.device.token).sort()).toEqual(["bb".repeat(32), "bc".repeat(32)]);
  expect(sent[0].message.body).toBe("Anna hat „Pizza“ bezahlt: 30,00 €");
});

test("people not part of the expense get nothing", async () => {
  const { gql } = fakeGraphQL({ title: "Blumen", amount_cents: 1000, payer_id: ids.anna, participant_ids: "{m-clara}", is_settlement: false });
  const { sent, sendImpl } = recorder();
  expect(await notifyGroup(gql, "u-anna", "expense_added", "e2", config, sendImpl)).toEqual({ status: 200, body: { sent: 0, skipped: "no_recipients" } });
  expect(sent).toHaveLength(0);
});

test("a payback reads from the receiver's side, and dead tokens are removed", async () => {
  const { gql, calls } = fakeGraphQL({ title: "Ausgleich", amount_cents: 2000, payer_id: ids.ben, participant_ids: [ids.anna], is_settlement: true });
  const { sent, sendImpl } = recorder(() => "gone");
  expect(await notifyGroup(gql, "u-ben", "settlement_added", "e3", config, sendImpl)).toEqual({ status: 200, body: { sent: 0, removed: 1 } });
  expect(sent[0].message.body).toBe("Ben hat dir 20,00 € zurückgezahlt.");
  expect(calls.at(-1)!.variables).toEqual({ tokens: ["aa".repeat(32)] });
});

test("unknown expenses, wrong kinds, outsiders and missing APNs keys send nothing", async () => {
  const { sendImpl, sent } = recorder();
  expect((await notifyGroup(fakeGraphQL(null).gql, "u-anna", "expense_added", "x", config, sendImpl)).status).toBe(404);
  const expense = { title: "X", amount_cents: 100, payer_id: ids.ben, participant_ids: [ids.anna, ids.ben], is_settlement: false };
  expect((await notifyGroup(fakeGraphQL(expense).gql, "u-ben", "settlement_added", "x", config, sendImpl)).body).toEqual({ error: "wrong_kind" });
  expect((await notifyGroup(fakeGraphQL(expense).gql, "u-eve", "expense_added", "x", config, sendImpl)).status).toBe(403);
  expect((await notifyGroup(fakeGraphQL(expense).gql, "u-ben", "expense_added", "x", undefined, sendImpl)).body)
    .toEqual({ sent: 0, skipped: "not_configured" });
  expect(sent).toHaveLength(0);
});
