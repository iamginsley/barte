// The whole life of a group, as three people (A, B, C) would go through it in the app.
import { beforeAll, expect, test } from "vitest";
import * as api from "../src/api.js";
import { clearFirestore, db, hint } from "./emulator.js";

const A = "user-a";
const B = "user-b";
const C = "user-c";

beforeAll(clearFirestore);

const group = async (id: string) => (await db.collection("groups").doc(id).get()).data() as api.GroupDoc | undefined;
const expenses = async (id: string) => (await db.collection("groups").doc(id).collection("expenses").get()).docs;
const idOf = (g: api.GroupDoc, name: string) => g.members.find((m) => m.name === name)!.id;
const newId = () => crypto.randomUUID();

test("a group from creation to deletion", async () => {
  // A creates a group
  const { groupId } = await api.createGroup(db, A, {
    name: "Ski", currency: "eur", color: 1, myName: " Anna ", otherNames: ["Ben", "Clara", "  "],
  });
  let g = (await group(groupId))!;
  expect(g.members.map((m) => m.name)).toEqual(["Anna", "Ben", "Clara"]);
  expect(g.members[0].uid).toBe(A);
  expect(g.memberUids).toEqual([A]);
  expect(g.currency).toBe("EUR");
  expect(g.inviteCode).toMatch(/^[A-Z0-9]{8}$/);
  const code = g.inviteCode;
  const [anna, ben, clara] = ["Anna", "Ben", "Clara"].map((n) => idOf(g, n));

  // Outsiders cannot write
  expect(await hint(api.addMember(db, B, { groupId, name: "Eve" }))).toBe("not_member");
  expect(await hint(api.saveExpense(db, B, {
    groupId, id: newId(), title: "Hack", amountCents: 100, spentOn: "2026-11-01", payerId: ben, participantIds: [ben],
  }))).toBe("not_member");
  expect(await hint(api.updateGroup(db, B, { groupId, name: "X", currency: "EUR", color: 0 }))).toBe("not_member");

  // Joining
  expect(await hint(api.previewInvite(db, B, { code: "NOPE2345" }))).toBe("invalid_code");
  const preview = await api.previewInvite(db, B, { code: code.toLowerCase() });
  expect(preview.name).toBe("Ski");
  expect(preview.isMember).toBe(false);
  expect(preview.members.map((m) => [m.name, m.isClaimed])).toEqual([["Anna", true], ["Ben", false], ["Clara", false]]);
  expect(await hint(api.joinGroup(db, B, { code, memberId: anna }))).toBe("member_taken");
  expect((await api.joinGroup(db, B, { code, memberId: ben })).groupId).toBe(groupId);
  expect((await api.joinGroup(db, B, { code, memberId: clara })).groupId).toBe(groupId);
  g = (await group(groupId))!;
  expect(g.memberUids.sort()).toEqual([A, B]);
  expect(g.members.find((m) => m.id === clara)!.uid).toBeNull();

  // Claiming a different name
  await api.claimMember(db, B, { groupId, memberId: clara });
  g = (await group(groupId))!;
  expect(g.members.find((m) => m.id === clara)!.uid).toBe(B);
  expect(g.members.find((m) => m.id === ben)!.uid).toBeNull();
  expect(await hint(api.claimMember(db, B, { groupId, memberId: anna }))).toBe("member_taken");
  await api.claimMember(db, B, { groupId, memberId: ben });

  // Expenses
  const e1 = newId();
  const chalet = { groupId, id: e1, title: "Chalet", amountCents: 90000, spentOn: "2026-11-01", payerId: anna, participantIds: [anna, ben, clara, ben] };
  await api.saveExpense(db, B, chalet);
  let saved = (await expenses(groupId)).find((d) => d.id === e1)!.data();
  expect(saved.participantIds).toEqual([anna, ben, clara]);
  expect(saved.createdBy).toBe(B);
  await api.saveExpense(db, A, { ...chalet, amountCents: 120000 });
  expect(await expenses(groupId)).toHaveLength(1);
  saved = (await expenses(groupId))[0].data();
  expect(saved.amountCents).toBe(120000);
  expect(saved.createdBy).toBe(B);
  expect(await hint(api.saveExpense(db, A, { ...chalet, id: newId(), participantIds: [newId()] }))).toBe("unknown_member");
  await api.saveExpense(db, B, {
    groupId, id: newId(), title: "Ausgleich", amountCents: 40000, spentOn: "2026-11-02", payerId: ben, participantIds: [anna], isSettlement: true,
  });

  // Members
  await api.renameMember(db, B, { groupId, memberId: clara, name: "Clara S." });
  expect((await group(groupId))!.members.find((m) => m.id === clara)!.name).toBe("Clara S.");
  expect(await hint(api.removeMember(db, B, { groupId, memberId: clara }))).toBe("member_involved");
  expect(await hint(api.removeMember(db, B, { groupId, memberId: anna }))).toBe("member_linked");
  const { memberId: david } = await api.addMember(db, B, { groupId, name: "David" });
  await api.removeMember(db, B, { groupId, memberId: david });
  expect((await group(groupId))!.members).toHaveLength(3);
  expect(await hint(api.addMember(db, B, { groupId, name: "   " }))).toBe("empty_name");

  // Deleting and leaving
  expect(await hint(api.deleteGroup(db, B, { groupId }))).toBe("not_creator");
  await api.leaveGroup(db, B, { groupId });
  g = (await group(groupId))!;
  expect(g.memberUids).toEqual([A]);
  expect(g.members.find((m) => m.id === ben)).toMatchObject({ name: "Ben", uid: null });
  expect(await expenses(groupId)).toHaveLength(2);

  // C joins as a new person
  await api.joinGroup(db, C, { code, name: "Chris" });
  expect((await group(groupId))!.members).toHaveLength(4);

  // A regenerates the code: the old one stops working
  const { code: newCode } = await api.regenerateInviteCode(db, A, { groupId });
  expect(newCode).not.toBe(code);
  expect(await hint(api.joinGroup(db, B, { code, memberId: ben }))).toBe("invalid_code");
  expect((await api.previewInvite(db, B, { code: newCode })).groupId).toBe(groupId);

  // The creator deletes for everyone
  await api.deleteGroup(db, A, { groupId });
  expect(await group(groupId)).toBeUndefined();
  expect(await expenses(groupId)).toHaveLength(0);
  expect((await db.collection("invites").doc(newCode).get()).exists).toBe(false);
});

test("the last person with the app leaving deletes the group", async () => {
  const { groupId } = await api.createGroup(db, B, { name: "Solo", currency: "EUR", color: 0, myName: "Ben" });
  await api.leaveGroup(db, B, { groupId });
  expect(await group(groupId)).toBeUndefined();
});

test("someone who is the last with the app may delete a group they didn't create", async () => {
  const { groupId } = await api.createGroup(db, A, { name: "Erbe", currency: "EUR", color: 0, myName: "Anna" });
  const { inviteCode } = (await group(groupId))!;
  await api.joinGroup(db, B, { code: inviteCode, name: "Ben" });
  await api.leaveGroup(db, A, { groupId });
  await api.deleteGroup(db, B, { groupId });
  expect(await group(groupId)).toBeUndefined();
});

test("payment details: validated, visible to people I share a group with", async () => {
  expect(await hint(api.setPaymentDetails(db, A, { paypal: "anna maria" }))).toBe("invalid_paypal");
  expect(await hint(api.setPaymentDetails(db, A, { iban: "DE89370400440532013001" }))).toBe("invalid_iban");
  await api.setPaymentDetails(db, A, { paypal: "https://paypal.me/annab", iban: "de89 3704 0044 0532 0130 00", accountHolder: " Anna  B " });
  await api.setPaymentDetails(db, C, { paypal: "chris" });

  expect(await api.paymentDetails(db, A)).toEqual({ [A]: { paypal: "annab", iban: "DE89370400440532013000", accountHolder: "Anna B" } });
  expect(Object.keys(await api.paymentDetails(db, B))).toEqual([]);

  const { groupId } = await api.createGroup(db, A, { name: "Bezahlen", currency: "EUR", color: 0, myName: "Anna" });
  await api.joinGroup(db, B, { code: (await group(groupId))!.inviteCode, name: "Ben" });
  expect(Object.keys(await api.paymentDetails(db, B))).toEqual([A]);
  expect(Object.keys(await api.paymentDetails(db, A))).toEqual([A]);
  expect((await group(groupId)) as unknown as Record<string, unknown>).not.toHaveProperty("paymentsUpdatedAt");

  await api.setPaymentDetails(db, A, { paypal: "annab" });
  expect((await api.paymentDetails(db, B))[A]).toEqual({ paypal: "annab", iban: null, accountHolder: null });
  expect((await group(groupId)) as unknown as Record<string, unknown>).toHaveProperty("paymentsUpdatedAt");

  await api.setPaymentDetails(db, A, {});
  expect(await api.paymentDetails(db, B)).toEqual({});
});

test("devices move to whoever registers them, and only the owner unregisters", async () => {
  const token = "ab".repeat(32);
  expect(await hint(api.registerDevice(db, A, { token: "nope", environment: "sandbox" }))).toBe("invalid_input");
  await api.registerDevice(db, A, { token: token.toUpperCase(), environment: "sandbox" });
  await api.registerDevice(db, B, { token, environment: "production" });
  expect((await db.collection("devices").doc(token).get()).data()).toMatchObject({ uid: B, environment: "production" });
  await api.unregisterDevice(db, A, { token });
  expect((await db.collection("devices").doc(token).get()).exists).toBe(true);
  await api.unregisterDevice(db, B, { token });
  expect((await db.collection("devices").doc(token).get()).exists).toBe(false);
});

test("deleting an account keeps shared history and removes solo groups", async () => {
  const D = "user-d";
  const E = "user-e";
  const { groupId: shared } = await api.createGroup(db, D, { name: "Geteilt", currency: "EUR", color: 0, myName: "Dora" });
  await api.joinGroup(db, E, { code: (await group(shared))!.inviteCode, name: "Emil" });
  const dora = idOf((await group(shared))!, "Dora");
  await api.saveExpense(db, D, { groupId: shared, id: newId(), title: "Pizza", amountCents: 3000, spentOn: "2026-11-03", payerId: dora, participantIds: [dora] });
  const { groupId: solo } = await api.createGroup(db, D, { name: "Allein", currency: "EUR", color: 0, myName: "Dora" });
  await api.setPaymentDetails(db, D, { paypal: "dora" });
  await api.registerDevice(db, D, { token: "cd".repeat(32), environment: "sandbox" });

  await api.deleteAccountData(db, D);

  const g = (await group(shared))!;
  expect(g.memberUids).toEqual([E]);
  expect(g.members.find((m) => m.id === dora)).toMatchObject({ name: "Dora", uid: null });
  expect(await expenses(shared)).toHaveLength(1);
  expect(await group(solo)).toBeUndefined();
  expect((await db.collection("paymentDetails").doc(D).get()).exists).toBe(false);
  expect((await db.collection("devices").doc("cd".repeat(32)).get()).exists).toBe(false);
});
