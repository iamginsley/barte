// Wording, APNs requests and who gets which push.
import { decodeProtectedHeader, exportJWK, exportPKCS8, generateKeyPair, SignJWT, createLocalJWKSet } from "jose";
import type { Request } from "express";
import { expect, test } from "vitest";
import { type ApnsConfig, type Device, payload, resetTokenCache, send, type Transport } from "../_lib/apns";
import { compose, languageOf, type Message, money } from "../_lib/messages";
import { apnsConfig, changesMoney, type GroupEventRow, notifyEvent, type Snapshot } from "../_lib/notify";
import { fromHasura } from "../events/group-event";
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

test("new wording: edits, deletions and closing", () => {
  const changed = { kind: "expense_changed" as const, ...group, actor: "Anna", title: "Pizza" };
  expect(compose({ ...changed, change: { type: "amount", from: 4200, to: 2400 } }).body).toBe("Anna hat „Pizza“ geändert: 42,00 € → 24,00 €");
  expect(compose({ ...changed, change: { type: "payer", from: { type: "recipient" }, to: { type: "other", name: "Ben" } } }).body)
    .toBe("Anna hat „Pizza“ geändert: bezahlt von Ben statt dir");
  expect(compose({ ...changed, change: { type: "split" } }).body).toBe("Anna hat „Pizza“ geändert: neue Aufteilung");
  expect(compose({ kind: "expense_deleted", ...group, actor: "Anna", title: "Pizza", amountCents: 4200 }).body).toBe("Anna hat „Pizza“ gelöscht (42,00 €).");
  const settlement = { kind: "settlement_deleted" as const, ...group, actor: "Anna", amountCents: 2000, from: "Ben", to: "Anna", actorIsFrom: false };
  expect(compose({ ...settlement, recipient: "from" }).body).toBe("Anna hat einen Ausgleich gelöscht: 20,00 € von dir an Anna.");
  expect(compose({ ...settlement, recipient: "to" }).body).toBe("Anna hat einen Ausgleich gelöscht: 20,00 € von Ben an dich.");
  const closed = compose({ kind: "group_closed", ...group, actor: "Ben" });
  expect(closed.body).toBe("Ben hat die Gruppe abgeschlossen.");
  expect(closed.passive).toBe(true);
});

// English ---------------------------------------------------------------------------

test("the device's language picks the wording, its region the money format", () => {
  expect(languageOf("en-GB")).toBe("en");
  expect(languageOf("en")).toBe("en");
  expect(languageOf("de-AT")).toBe("de");
  expect(languageOf("fr-FR")).toBe("de"); // the app falls back to German, so do pushes
  expect(languageOf(null)).toBe("de");
  expect(languageOf("eng")).toBe("de");
  expect(money(123456, "EUR", "en-US")).toBe("€1,234.56");
  expect(money(2850, "GBP", "en-GB")).toBe("£28.50");
  expect(money(6400, "EUR", "de")).toBe("64,00 €");
  expect(money(6400, "EUR", "xx-not-a-tag-at-all!")).toBe("64,00 €");
});

test("English wording for every kind of push", () => {
  const en = "en-US";
  const expense = { kind: "expense_added" as const, ...group, actor: "Anna", title: "Gas", amountCents: 6400 };
  expect(compose({ ...expense, payer: { type: "actor" } }, en).body).toBe("Anna paid for “Gas”: €64.00");
  expect(compose({ ...expense, payer: { type: "recipient" } }, en).body).toBe("Anna added “Gas”, paid by you: €64.00");
  expect(compose({ ...expense, payer: { type: "other", name: "Ben" } }, en).body).toBe("Anna added “Gas”, paid by Ben: €64.00");
  expect(compose({ ...expense, actor: null, payer: { type: "actor" } }, en).body).toBe("Someone paid for “Gas”: €64.00");
  expect(compose({ ...expense, actor: null, payer: { type: "actor" } }).body).toBe("Jemand hat „Gas“ bezahlt: 64,00 €");

  const settlement = { kind: "settlement_added" as const, ...group, amountCents: 2000, from: "Max", to: "Lena" };
  expect(compose({ ...settlement, actor: "Max", actorIsFrom: true, recipient: "to" }, en).body).toBe("Max paid you back €20.00.");
  expect(compose({ ...settlement, actor: "Dominik", actorIsFrom: false, recipient: "to" }, en).body)
    .toBe("Dominik recorded: Max paid you back €20.00.");
  expect(compose({ ...settlement, actor: "Lena", actorIsFrom: false, recipient: "from" }, en).body)
    .toBe("Lena recorded: You paid Lena back €20.00.");

  const changed = { kind: "expense_changed" as const, ...group, actor: "Anna", title: "Pizza" };
  expect(compose({ ...changed, change: { type: "amount", from: 4200, to: 2400 } }, en).body).toBe("Anna changed “Pizza”: €42.00 → €24.00");
  expect(compose({ ...changed, change: { type: "payer", from: { type: "recipient" }, to: { type: "other", name: "Ben" } } }, en).body)
    .toBe("Anna changed “Pizza”: paid by Ben instead of you");
  expect(compose({ ...changed, change: { type: "split" } }, en).body).toBe("Anna changed “Pizza”: new split");
  expect(compose({ kind: "expense_deleted", ...group, actor: "Anna", title: "Pizza", amountCents: 4200 }, en).body).toBe("Anna deleted “Pizza” (€42.00).");
  const deleted = { kind: "settlement_deleted" as const, ...group, actor: "Anna", amountCents: 2000, from: "Ben", to: "Anna", actorIsFrom: false };
  expect(compose({ ...deleted, recipient: "from" }, en).body).toBe("Anna deleted a settlement: €20.00 from you to Anna.");
  expect(compose({ ...deleted, recipient: "to" }, en).body).toBe("Anna deleted a settlement: €20.00 from Ben to you.");
  const closed = compose({ kind: "group_closed", ...group, actor: "Ben" }, en);
  expect(closed.body).toBe("Ben closed the group.");
  expect(closed.passive).toBe(true);
  expect(closed.title).toBe("WG Leopoldstraße"); // names are what people typed, never translated
});

test("only Hasura, with the webhook secret, may trigger pushes", () => {
  expect(fromHasura("s3cret", "s3cret")).toBe(true);
  expect(fromHasura("wrong", "s3cret")).toBe(false);
  expect(fromHasura(undefined, "s3cret")).toBe(false);
  expect(fromHasura("anything", undefined)).toBe(false);
  expect(fromHasura("", "")).toBe(false);
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
// Ben has a German iPhone and an English iPad; Anna's phone predates the language column.
const devices = [
  { token: "aa".repeat(32), environment: "sandbox", user_id: "u-anna", language: null },
  { token: "bb".repeat(32), environment: "production", user_id: "u-ben", language: "de-DE" },
  { token: "bc".repeat(32), environment: "sandbox", user_id: "u-ben", language: "en-GB" },
];

/** A fake Hasura: the group with its members, everyone's devices, and deletions. */
function fakeGraphQL(groupExists = true) {
  const calls: { query: string; variables: Record<string, unknown>; asUser?: string }[] = [];
  const gql = (async (query: string, variables: Record<string, unknown>, asUser?: string) => {
    calls.push({ query, variables, asUser });
    if (query.includes("groups_by_pk")) return { groups_by_pk: groupExists ? { name: "WG", currency: "EUR", members } : null };
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

const snap = (over: Partial<Snapshot> = {}): Snapshot => ({
  title: "Pizza", amount_cents: 3000, payer_id: ids.anna, participant_ids: [ids.anna, ids.ben],
  is_settlement: false, split_kind: "equal", split_values: null, ...over,
});
const row = (kind: string, old: Snapshot | null, next: Snapshot | null, actor = "u-anna", actorName = "Anna"): GroupEventRow => ({
  id: "ev1", group_id: group.groupId, kind, actor_id: actor, actor_name: actorName, subject_id: "e1", old, new: next,
});
const bodies = (sent: { message: Message }[]) => [...new Set(sent.map((s) => s.message.body))];

test("the others involved get a push, the one who made the change doesn't", async () => {
  const { gql, calls } = fakeGraphQL();
  const { sent, sendImpl } = recorder();
  expect(await notifyEvent(gql, row("expense_added", null, snap()), config, sendImpl)).toEqual({ status: 200, body: { sent: 2, removed: 0 } });
  expect(calls.every((c) => c.asUser === undefined)).toBe(true); // Hasura is the caller; everything runs as admin
  expect(sent.map((s) => s.device.token).sort()).toEqual(["bb".repeat(32), "bc".repeat(32)]);
  expect(bodies(sent)).toEqual(["Anna hat „Pizza“ bezahlt: 30,00 €", "Anna paid for “Pizza”: €30.00"]);
  expect(sent.find((s) => s.device.token === "bc".repeat(32))!.message.body).toBe("Anna paid for “Pizza”: €30.00");
  expect(calls.find((c) => c.query.includes("query Devices"))!.query).toContain("language");
});

test("people not part of the expense get nothing", async () => {
  const { sent, sendImpl } = recorder();
  const result = await notifyEvent(fakeGraphQL().gql, row("expense_added", null, snap({ participant_ids: [ids.clara] })), config, sendImpl);
  expect(result.body).toEqual({ sent: 0, skipped: "no_recipients" });
  expect(sent).toHaveLength(0);
});

test("an edit that changes money tells everyone involved before and after", async () => {
  const { sent, sendImpl } = recorder();
  // Ben lowers Anna's pizza and takes himself out of it: Anna was involved before, so she hears about it.
  await notifyEvent(fakeGraphQL().gql, row("expense_changed", snap(), snap({ amount_cents: 1500, participant_ids: [ids.anna] }), "u-ben", "Ben"), config, sendImpl);
  expect(sent.map((s) => s.device.token)).toEqual(["aa".repeat(32)]);
  expect(bodies(sent)).toEqual(["Ben hat „Pizza“ geändert: 30,00 € → 15,00 €"]);
});

test("a new payer reads from the recipient's side", async () => {
  const { sent, sendImpl } = recorder();
  await notifyEvent(fakeGraphQL().gql, row("expense_changed", snap(), snap({ payer_id: ids.ben })), config, sendImpl);
  expect(bodies(sent)).toEqual(["Anna hat „Pizza“ geändert: bezahlt von dir statt Anna", "Anna changed “Pizza”: paid by you instead of Anna"]);
});

test("title or date edits, renames and reopening stay quiet", async () => {
  const { sent, sendImpl } = recorder();
  const gql = fakeGraphQL().gql;
  expect(changesMoney(snap(), snap({ title: "Pasta" }))).toBe(false);
  expect(changesMoney(snap(), snap({ participant_ids: [ids.ben, ids.anna] }))).toBe(false);
  expect(changesMoney(snap(), snap({ split_kind: "shares", split_values: [2, 1] }))).toBe(true);
  expect((await notifyEvent(gql, row("expense_changed", snap(), snap({ title: "Pasta" })), config, sendImpl)).body).toEqual({ sent: 0, skipped: "quiet" });
  for (const kind of ["member_renamed", "group_reopened", "group_updated", "member_added"]) {
    expect((await notifyEvent(gql, row(kind, null, null), config, sendImpl)).body).toEqual({ sent: 0, skipped: "quiet" });
  }
  expect(sent).toHaveLength(0);
});

test("deleting an expense or a payback is announced", async () => {
  const { sent, sendImpl } = recorder();
  await notifyEvent(fakeGraphQL().gql, row("expense_deleted", snap(), null, "u-ben", "Ben"), config, sendImpl);
  expect(bodies(sent)).toEqual(["Ben hat „Pizza“ gelöscht (30,00 €)."]);

  const payback = recorder();
  const settlement = snap({ title: "Ausgleich", amount_cents: 2000, payer_id: ids.ben, participant_ids: [ids.anna], is_settlement: true });
  await notifyEvent(fakeGraphQL().gql, row("settlement_deleted", settlement, null, "u-ben", "Ben"), config, payback.sendImpl);
  expect(bodies(payback.sent)).toEqual(["Ben hat einen Ausgleich gelöscht: 20,00 € von Ben an dich."]);
});

test("joining tells the others, above all who took over a typed-in name", async () => {
  const joined = { kind: "member_joined" as const, ...group, actor: "Benjamin", name: "Benjamin" };
  expect(compose({ ...joined, claimed: "Ben" }).body).toBe("Benjamin ist beigetreten und übernimmt „Ben“ mit allen Ausgaben.");
  expect(compose({ ...joined, claimed: null }).body).toBe("Benjamin ist der Gruppe beigetreten.");
  expect(compose({ ...joined, claimed: "Ben" }, "en-US").body).toBe("Benjamin joined and takes over “Ben” with all its expenses.");
  expect(compose({ ...joined, claimed: null }, "en-US").body).toBe("Benjamin joined the group.");

  const { sent, sendImpl } = recorder();
  const claim = { ...row("member_joined", null, null, "u-ben", "Ben"), old: { name: "Ben" } as Snapshot, new: { name: "Ben" } as Snapshot };
  await notifyEvent(fakeGraphQL().gql, claim, config, sendImpl);
  expect(sent.map((s) => s.device.token)).toEqual(["aa".repeat(32)]); // Anna hears it, Ben doesn't
  expect(bodies(sent)).toEqual(["Ben ist beigetreten und übernimmt „Ben“ mit allen Ausgaben."]);
  expect(sent[0].message.passive).toBe(false);
  for (const kind of ["member_left"]) {
    expect((await notifyEvent(fakeGraphQL().gql, row(kind, null, null), config, sendImpl)).body).toEqual({ sent: 0, skipped: "quiet" });
  }
});

test("closing reaches everyone with the app, quietly", async () => {
  const { sent, sendImpl } = recorder();
  await notifyEvent(fakeGraphQL().gql, row("group_closed", null, null), config, sendImpl);
  expect(sent.map((s) => s.device.token).sort()).toEqual(["bb".repeat(32), "bc".repeat(32)]);
  expect(sent.every((s) => s.message.passive)).toBe(true);
});

test("a payback reads from the receiver's side, and dead tokens are removed", async () => {
  const { gql, calls } = fakeGraphQL();
  const { sent, sendImpl } = recorder(() => "gone");
  const settlement = snap({ amount_cents: 2000, payer_id: ids.ben, participant_ids: [ids.anna], is_settlement: true });
  expect(await notifyEvent(gql, row("settlement_added", null, settlement, "u-ben", "Ben"), config, sendImpl)).toEqual({ status: 200, body: { sent: 0, removed: 1 } });
  expect(sent[0].message.body).toBe("Ben hat dir 20,00 € zurückgezahlt.");
  expect(calls.at(-1)!.variables).toEqual({ tokens: ["aa".repeat(32)] });
});

test("deleted groups and missing APNs keys send nothing", async () => {
  const { sendImpl, sent } = recorder();
  expect((await notifyEvent(fakeGraphQL(false).gql, row("expense_added", null, snap()), config, sendImpl)).body).toEqual({ sent: 0, skipped: "group_gone" });
  expect((await notifyEvent(fakeGraphQL().gql, row("expense_added", null, snap()), undefined, sendImpl)).body).toEqual({ sent: 0, skipped: "not_configured" });
  expect(sent).toHaveLength(0);
});
