// Tells the others in a group about a new expense or payback. Runs on the server when an expense
// document is created, builds the text from the database (never from client text) and pushes it to
// the people in the group who use the app, are part of the expense and aren't the one who entered it.
import type { Firestore } from "firebase-admin/firestore";
import type { GroupDoc, Member } from "../api.js";
import { type ApnsConfig, type Device, type Outcome, send } from "./apns.js";
import { compose, type Event, type Message } from "./messages.js";

export interface ExpenseDoc {
  title: string;
  amountCents: number;
  payerId: string;
  participantIds: string[];
  isSettlement: boolean;
  createdBy: string;
}

/** One message per recipient uid: who paid reads differently for each of them. */
export function messagesFor(groupId: string, group: GroupDoc, expense: ExpenseDoc): Map<string, Message> {
  const result = new Map<string, Message>();
  const actor = group.members.find((m) => m.uid === expense.createdBy);
  if (!actor) return result;
  const nameOf = (id: string) => group.members.find((m) => m.id === id)?.name ?? "?";
  const involved = new Set([expense.payerId, ...expense.participantIds]);
  const recipients = group.members.filter((m) => m.uid && m.uid !== expense.createdBy && involved.has(m.id));

  const common = {
    group: group.name,
    groupId,
    actor: actor.name,
    amountCents: expense.amountCents,
    currency: group.currency,
  };
  const eventFor = (recipient: Member): Event => {
    if (!expense.isSettlement) {
      const payer = expense.payerId === actor.id
        ? { type: "actor" as const }
        : expense.payerId === recipient.id
        ? { type: "recipient" as const }
        : { type: "other" as const, name: nameOf(expense.payerId) };
      return { kind: "expense_added", ...common, title: expense.title, payer };
    }
    const to = expense.participantIds[0];
    return {
      kind: "settlement_added",
      ...common,
      from: nameOf(expense.payerId),
      to: nameOf(to),
      actorIsFrom: expense.payerId === actor.id,
      recipient: recipient.id === to ? "to" : "from",
    };
  };
  for (const recipient of recipients) result.set(recipient.uid!, compose(eventFor(recipient)));
  return result;
}

export type Sender = (device: Device, message: Message, config: ApnsConfig) => Promise<Outcome>;

export async function notifyExpense(
  db: Firestore,
  groupId: string,
  expense: ExpenseDoc,
  config: ApnsConfig | undefined,
  sender: Sender = send,
): Promise<{ sent: number; removed: number }> {
  const group = (await db.collection("groups").doc(groupId).get()).data() as GroupDoc | undefined;
  if (!group || !config) return { sent: 0, removed: 0 };
  const messages = messagesFor(groupId, group, expense);
  if (messages.size === 0) return { sent: 0, removed: 0 };

  const devices = await db.collection("devices").where("uid", "in", [...messages.keys()].slice(0, 30)).get();
  let sent = 0;
  const gone: string[] = [];
  await Promise.all(devices.docs.map(async (doc) => {
    const { uid, environment } = doc.data() as { uid: string; environment: Device["environment"] };
    const outcome = await sender({ token: doc.id, environment }, messages.get(uid)!, config).catch((error) => {
      console.error("notify: send failed", error);
      return "failed" as const;
    });
    if (outcome === "sent") sent++;
    if (outcome === "gone") gone.push(doc.id);
  }));
  await Promise.all(gone.map((token) => db.collection("devices").doc(token).delete()));
  return { sent, removed: gone.length };
}
