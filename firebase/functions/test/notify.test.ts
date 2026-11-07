// Who gets which push when an expense is created.
import { beforeAll, expect, test } from "vitest";
import * as api from "../src/api.js";
import { type ExpenseDoc, notifyExpense } from "../src/push/notify.js";
import type { Device } from "../src/push/apns.js";
import type { Message } from "../src/push/messages.js";
import { clearFirestore, db } from "./emulator.js";

const config = { teamId: "TEAM", keyId: "KEY", privateKey: "unused", topic: "com.iamginsley.barte" };

let groupId: string;
let ids: Record<string, string>;

beforeAll(async () => {
  await clearFirestore();
  ({ groupId } = await api.createGroup(db, "anna", { name: "WG", currency: "EUR", color: 0, myName: "Anna", otherNames: ["Clara"] }));
  const code = ((await db.collection("groups").doc(groupId).get()).data() as api.GroupDoc).inviteCode;
  await api.joinGroup(db, "ben", { code, name: "Ben" });
  const group = (await db.collection("groups").doc(groupId).get()).data() as api.GroupDoc;
  ids = Object.fromEntries(group.members.map((m) => [m.name, m.id]));
  await api.registerDevice(db, "anna", { token: "aa".repeat(32), environment: "sandbox" });
  await api.registerDevice(db, "ben", { token: "bb".repeat(32), environment: "production" });
  await api.registerDevice(db, "ben", { token: "bc".repeat(32), environment: "sandbox" });
});

function recorder(outcome: (device: Device) => "sent" | "gone" = () => "sent") {
  const sent: { device: Device; message: Message }[] = [];
  const sender = async (device: Device, message: Message) => {
    sent.push({ device, message });
    return outcome(device);
  };
  return { sent, sender };
}

test("the others involved get a push, the one who entered it doesn't", async () => {
  const expense: ExpenseDoc = {
    title: "Pizza", amountCents: 3000, payerId: ids.Anna, participantIds: [ids.Anna, ids.Ben], isSettlement: false, createdBy: "anna",
  };
  const { sent, sender } = recorder();
  expect(await notifyExpense(db, groupId, expense, config, sender)).toEqual({ sent: 2, removed: 0 });
  expect(sent.map((s) => s.device.token).sort()).toEqual(["bb".repeat(32), "bc".repeat(32)]);
  expect(sent[0].message.body).toBe("Anna hat „Pizza“ bezahlt: 30,00 €");
  expect(sent[0].message.title).toBe("WG");
});

test("people not part of the expense get nothing", async () => {
  const expense: ExpenseDoc = {
    title: "Blumen", amountCents: 1000, payerId: ids.Anna, participantIds: [ids.Clara], isSettlement: false, createdBy: "anna",
  };
  const { sent, sender } = recorder();
  expect(await notifyExpense(db, groupId, expense, config, sender)).toEqual({ sent: 0, removed: 0 });
  expect(sent).toHaveLength(0);
});

test("a payback reads from the receiver's side, and dead tokens are removed", async () => {
  const settlement: ExpenseDoc = {
    title: "Ausgleich", amountCents: 2000, payerId: ids.Ben, participantIds: [ids.Anna], isSettlement: true, createdBy: "ben",
  };
  const { sent, sender } = recorder(() => "gone");
  expect(await notifyExpense(db, groupId, settlement, config, sender)).toEqual({ sent: 0, removed: 1 });
  expect(sent[0].message.body).toBe("Ben hat dir 20,00 € zurückgezahlt.");
  expect((await db.collection("devices").doc("aa".repeat(32)).get()).exists).toBe(false);
});

test("without APNs configured nothing is sent", async () => {
  const { sent, sender } = recorder();
  const expense: ExpenseDoc = {
    title: "X", amountCents: 100, payerId: ids.Ben, participantIds: [ids.Anna, ids.Ben], isSettlement: false, createdBy: "ben",
  };
  expect(await notifyExpense(db, groupId, expense, undefined, sender)).toEqual({ sent: 0, removed: 0 });
  expect(sent).toHaveLength(0);
});
