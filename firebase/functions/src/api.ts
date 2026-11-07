// Every write the app makes, as plain functions of (database, caller, input). index.ts wraps them as
// callable Cloud Functions; the tests call them directly against the Firestore emulator.
//
// Data model (see firestore.rules for who reads what):
//   groups/{groupId}                  name, currency, color, inviteCode, createdBy, createdAt,
//                                     members[{id, name, uid, joinedAt}], memberUids[]
//   groups/{groupId}/expenses/{id}    title, amountCents, spentOn, payerId, participantIds[],
//                                     isSettlement, splitKind, splitValues, createdBy, createdAt
//   invites/{code}                    groupId
//   paymentDetails/{uid}              paypal, iban, accountHolder
//   devices/{token}                   uid, environment
// Members are names. A member can be linked to a signed-in person (uid), which is how that person
// sees the group and which member is "me" for them. Friends without the app stay plain names.
import { randomUUID } from "node:crypto";
import { FieldValue, Timestamp, type DocumentReference, type Firestore, type Transaction } from "firebase-admin/firestore";
import { Failure } from "./errors.js";
import * as check from "./validate.js";

export interface Member {
  id: string;
  name: string;
  uid: string | null;
  /** Milliseconds; keeps the order in which people were added. */
  joinedAt: number;
}

export interface GroupDoc {
  name: string;
  currency: string;
  color: number;
  inviteCode: string;
  createdBy: string | null;
  createdAt: Timestamp;
  members: Member[];
  memberUids: string[];
}

type Input = Record<string, unknown>;

const groups = (db: Firestore) => db.collection("groups");
const invites = (db: Firestore) => db.collection("invites");

function input(data: unknown): Input {
  return data && typeof data === "object" ? (data as Input) : {};
}

function uidsOf(members: Member[]): string[] {
  return [...new Set(members.flatMap((m) => (m.uid ? [m.uid] : [])))];
}

/** Members created in one call get increasing times, so their order survives. */
function stamp(index = 0): number {
  return Date.now() + index;
}

async function memberGroup(tx: Transaction, db: Firestore, uid: string, groupId: unknown) {
  const ref = groups(db).doc(check.uuid(groupId, "not_member"));
  const snapshot = await tx.get(ref);
  const group = snapshot.data() as GroupDoc | undefined;
  if (!group || !group.memberUids.includes(uid)) throw new Failure("not_member");
  return { ref, group };
}

/** Reserves a new invite code; retries on the rare collision. */
async function reserveCode(tx: Transaction, db: Firestore, groupId: string): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = check.newInviteCode();
    const ref = invites(db).doc(code);
    if (!(await tx.get(ref)).exists) {
      tx.create(ref, { groupId });
      return code;
    }
  }
  throw new Error("could not find a free invite code");
}

async function deleteGroupData(db: Firestore, ref: DocumentReference, inviteCode: string) {
  await invites(db).doc(inviteCode).delete();
  await db.recursiveDelete(ref);
}

// Groups ----------------------------------------------------------------------

/** Creates a group with me as the first member (linked) and the others as plain names. */
export async function createGroup(db: Firestore, uid: string, data: unknown): Promise<{ groupId: string }> {
  const raw = input(data);
  const name = check.groupName(raw.name);
  const currency = check.currency(raw.currency);
  const color = check.color(raw.color ?? 0);
  const others = Array.isArray(raw.otherNames)
    ? raw.otherNames.filter((n) => typeof n === "string" && n.trim().length > 0).map(check.memberName)
    : [];
  const members: Member[] = [
    { id: randomUUID(), name: check.memberName(raw.myName), uid, joinedAt: stamp() },
    ...others.map((n, i) => ({ id: randomUUID(), name: n, uid: null, joinedAt: stamp(i + 1) })),
  ];
  const groupId = randomUUID();
  await db.runTransaction(async (tx) => {
    const inviteCode = await reserveCode(tx, db, groupId);
    tx.create(groups(db).doc(groupId), {
      name, currency, color, inviteCode,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      members,
      memberUids: [uid],
    });
  });
  return { groupId };
}

export async function updateGroup(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const update = { name: check.groupName(raw.name), currency: check.currency(raw.currency), color: check.color(raw.color) };
  await db.runTransaction(async (tx) => {
    const { ref } = await memberGroup(tx, db, uid, raw.groupId);
    tx.update(ref, update);
  });
}

/**
 * The creator deletes a group for everyone. Others can only leave, unless nobody else in it
 * uses the app any more.
 */
export async function deleteGroup(db: Firestore, uid: string, data: unknown): Promise<void> {
  const { ref, group } = await db.runTransaction((tx) => memberGroup(tx, db, uid, input(data).groupId));
  const othersUseApp = group.memberUids.some((u) => u !== uid);
  if (group.createdBy !== uid && othersUseApp) throw new Failure("not_creator");
  await deleteGroupData(db, ref, group.inviteCode);
}

/** Unlinks me from my member; the name and its expenses stay. The last person with the app takes the group with them. */
export async function leaveGroup(db: Firestore, uid: string, data: unknown): Promise<void> {
  const result = await db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, input(data).groupId);
    const members = group.members.map((m) => (m.uid === uid ? { ...m, uid: null } : m));
    const memberUids = uidsOf(members);
    if (memberUids.length === 0) return { ref, group };
    tx.update(ref, { members, memberUids });
    return undefined;
  });
  if (result) await deleteGroupData(db, result.ref, result.group.inviteCode);
}

export async function regenerateInviteCode(db: Firestore, uid: string, data: unknown): Promise<{ code: string }> {
  return db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, input(data).groupId);
    const code = await reserveCode(tx, db, ref.id);
    tx.delete(invites(db).doc(group.inviteCode));
    tx.update(ref, { inviteCode: code });
    return { code };
  });
}

// Joining ---------------------------------------------------------------------

async function groupForCode(tx: Transaction, db: Firestore, value: unknown) {
  const invite = await tx.get(invites(db).doc(check.normalizeCode(value)));
  const groupId = invite.data()?.groupId as string | undefined;
  if (!groupId) throw new Failure("invalid_code");
  const ref = groups(db).doc(groupId);
  const group = (await tx.get(ref)).data() as GroupDoc | undefined;
  if (!group) throw new Failure("invalid_code");
  return { ref, group };
}

/** What someone with an invite code sees before joining: the group and who is still unclaimed. */
export async function previewInvite(db: Firestore, uid: string, data: unknown) {
  return db.runTransaction(async (tx) => {
    const { ref, group } = await groupForCode(tx, db, input(data).code);
    return {
      groupId: ref.id,
      name: group.name,
      currency: group.currency,
      color: group.color,
      isMember: group.memberUids.includes(uid),
      members: [...group.members]
        .sort((a, b) => a.joinedAt - b.joinedAt || a.id.localeCompare(b.id))
        .map((m) => ({ id: m.id, name: m.name, isClaimed: m.uid !== null })),
    };
  });
}

/**
 * Joins with an invite code, either as an existing unclaimed name (memberId) or as a new person (name).
 * Joining a group I'm already in just returns it.
 */
export async function joinGroup(db: Firestore, uid: string, data: unknown): Promise<{ groupId: string }> {
  const raw = input(data);
  return db.runTransaction(async (tx) => {
    const { ref, group } = await groupForCode(tx, db, raw.code);
    if (group.memberUids.includes(uid)) return { groupId: ref.id };
    let members: Member[];
    if (raw.memberId != null) {
      const memberId = check.uuid(raw.memberId, "member_taken");
      if (!group.members.some((m) => m.id === memberId && m.uid === null)) throw new Failure("member_taken");
      members = group.members.map((m) => (m.id === memberId ? { ...m, uid } : m));
    } else {
      members = [...group.members, { id: randomUUID(), name: check.memberName(raw.name), uid, joinedAt: stamp() }];
    }
    tx.update(ref, { members, memberUids: uidsOf(members) });
    return { groupId: ref.id };
  });
}

/** "That's not me": switches which name I am in a group I already belong to. */
export async function claimMember(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const memberId = check.uuid(raw.memberId, "member_not_found");
  await db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, raw.groupId);
    const target = group.members.find((m) => m.id === memberId);
    if (!target) throw new Failure("member_not_found");
    if (target.uid === uid) return;
    if (target.uid !== null) throw new Failure("member_taken");
    const members = group.members.map((m) => (m.id === memberId ? { ...m, uid } : m.uid === uid ? { ...m, uid: null } : m));
    tx.update(ref, { members, memberUids: uidsOf(members) });
  });
}

// Members ---------------------------------------------------------------------

export async function addMember(db: Firestore, uid: string, data: unknown): Promise<{ memberId: string }> {
  const raw = input(data);
  const name = check.memberName(raw.name);
  return db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, raw.groupId);
    const member: Member = { id: randomUUID(), name, uid: null, joinedAt: stamp() };
    tx.update(ref, { members: [...group.members, member] });
    return { memberId: member.id };
  });
}

export async function renameMember(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const memberId = check.uuid(raw.memberId, "member_not_found");
  const name = check.memberName(raw.name);
  await db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, raw.groupId);
    if (!group.members.some((m) => m.id === memberId)) throw new Failure("member_not_found");
    tx.update(ref, { members: group.members.map((m) => (m.id === memberId ? { ...m, name } : m)) });
  });
}

/** Only names that appear in no expense and aren't someone with the app can be removed. */
export async function removeMember(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const memberId = check.uuid(raw.memberId, "member_not_found");
  await db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, raw.groupId);
    const member = group.members.find((m) => m.id === memberId);
    if (!member) return;
    if (member.uid !== null) throw new Failure("member_linked");
    const expenses = ref.collection("expenses");
    const [paid, shared] = await Promise.all([
      tx.get(expenses.where("payerId", "==", memberId).limit(1)),
      tx.get(expenses.where("participantIds", "array-contains", memberId).limit(1)),
    ]);
    if (!paid.empty || !shared.empty) throw new Failure("member_involved");
    tx.update(ref, { members: group.members.filter((m) => m.id !== memberId) });
  });
}

// Expenses --------------------------------------------------------------------

/** Inserts or updates an expense. The id comes from the app, so a retry never creates a duplicate. */
export async function saveExpense(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  await db.runTransaction(async (tx) => {
    const { ref, group } = await memberGroup(tx, db, uid, raw.groupId);
    const expense = check.expense(raw, new Set(group.members.map((m) => m.id)));
    const expenseRef = ref.collection("expenses").doc(expense.id);
    const existing = await tx.get(expenseRef);
    const { id: _id, ...fields } = expense;
    if (existing.exists) {
      tx.update(expenseRef, { ...fields, updatedAt: FieldValue.serverTimestamp() });
    } else {
      // An expense id from another group would land here as a new document, never touching the other one.
      tx.create(expenseRef, {
        ...fields,
        createdBy: uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

export async function deleteExpense(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const expenseId = check.uuid(raw.expenseId);
  await db.runTransaction(async (tx) => {
    const { ref } = await memberGroup(tx, db, uid, raw.groupId);
    tx.delete(ref.collection("expenses").doc(expenseId));
  });
}

// Payment details -------------------------------------------------------------

export interface PaymentDetails {
  paypal: string | null;
  iban: string | null;
  accountHolder: string | null;
}

async function myGroups(db: Firestore, uid: string) {
  return (await groups(db).where("memberUids", "array-contains", uid).get()).docs;
}

/** Empty details remove them. Touches my groups, so the others' screens refresh live. */
export async function setPaymentDetails(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const paypal = check.paypal(raw.paypal);
  const iban = check.iban(raw.iban);
  const accountHolder = iban ? check.accountHolder(raw.accountHolder) : null;
  const ref = db.collection("paymentDetails").doc(uid);
  if (!paypal && !iban) {
    await ref.delete();
  } else {
    await ref.set({ paypal, iban, accountHolder, updatedAt: FieldValue.serverTimestamp() });
  }
  const batch = db.batch();
  for (const group of await myGroups(db, uid)) batch.update(group.ref, { paymentsUpdatedAt: FieldValue.serverTimestamp() });
  await batch.commit();
}

/** My own details and those of everyone I share a group with, by uid. */
export async function paymentDetails(db: Firestore, uid: string): Promise<Record<string, PaymentDetails>> {
  const uids = new Set<string>([uid]);
  for (const group of await myGroups(db, uid)) for (const u of (group.data() as GroupDoc).memberUids) uids.add(u);
  const refs = [...uids].map((u) => db.collection("paymentDetails").doc(u));
  const result: Record<string, PaymentDetails> = {};
  for (const snapshot of await db.getAll(...refs)) {
    const d = snapshot.data();
    if (d) result[snapshot.id] = { paypal: d.paypal ?? null, iban: d.iban ?? null, accountHolder: d.accountHolder ?? null };
  }
  return result;
}

// Devices ---------------------------------------------------------------------

/** A phone can change hands (sign out, other person signs in), so registering moves the token to the caller. */
export async function registerDevice(db: Firestore, uid: string, data: unknown): Promise<void> {
  const raw = input(data);
  const token = typeof raw.token === "string" ? raw.token.trim().toLowerCase() : "";
  if (!/^[0-9a-f]{64,200}$/.test(token)) throw new Failure("invalid_input");
  if (raw.environment !== "sandbox" && raw.environment !== "production") throw new Failure("invalid_input");
  await db.collection("devices").doc(token).set({ uid, environment: raw.environment, updatedAt: FieldValue.serverTimestamp() });
}

export async function unregisterDevice(db: Firestore, uid: string, data: unknown): Promise<void> {
  const token = typeof input(data).token === "string" ? (input(data).token as string).trim().toLowerCase() : "";
  if (!token) return;
  const ref = db.collection("devices").doc(token);
  await db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).data()?.uid === uid) tx.delete(ref);
  });
}

// Account ---------------------------------------------------------------------

/**
 * In-app account deletion (App Store Review Guideline 5.1.1(v)), before the auth user goes.
 * Unlinks the person from every group, so friends keep the shared history with the name.
 * Groups in which nobody else uses the app are deleted, because nobody could open them afterwards.
 */
export async function deleteAccountData(db: Firestore, uid: string): Promise<void> {
  for (const snapshot of await myGroups(db, uid)) {
    await leaveGroup(db, uid, { groupId: snapshot.id });
  }
  await db.collection("paymentDetails").doc(uid).delete();
  const devices = await db.collection("devices").where("uid", "==", uid).get();
  const batch = db.batch();
  for (const device of devices.docs) batch.delete(device.ref);
  await batch.commit();
}
