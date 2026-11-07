// Tells the others in a group about a new expense or payback. Reads the expense with the caller's
// own permissions (so only their groups), builds the message from the database rather than from
// client text, and pushes it to the people in the group who use the app and are part of it.
import { type ApnsConfig, type Device, send } from "./apns";
import { compose, type Event } from "./messages";
import type { GraphQL } from "./server";

export const KINDS = ["expense_added", "settlement_added"] as const;
export type Kind = (typeof KINDS)[number];

interface MemberRow {
  id: string;
  name: string;
  user_id: string | null;
}

interface ExpenseRow {
  group_id: string;
  title: string;
  amount_cents: number;
  payer_id: string;
  participant_ids: string[] | string;
  is_settlement: boolean;
  group: { name: string; currency: string; members: MemberRow[] };
}

export type Result = { status: number; body: Record<string, unknown> };

/** Hasura returns Postgres arrays as JSON arrays; accept the literal form too. */
export function uuidArray(value: string[] | string): string[] {
  if (Array.isArray(value)) return value;
  return value.replace(/^\{|\}$/g, "").split(",").filter(Boolean);
}

export function apnsConfig(env: NodeJS.ProcessEnv = process.env): ApnsConfig | undefined {
  // One .p8 key can carry both Sign in with Apple and APNs, so the Apple key is the fallback.
  const config = {
    teamId: env.APPLE_TEAM_ID ?? "",
    keyId: env.APNS_KEY_ID || env.APPLE_KEY_ID || "",
    privateKey: env.APNS_PRIVATE_KEY || env.APPLE_PRIVATE_KEY || "",
    topic: env.APNS_TOPIC ?? "com.iamginsley.barte",
  };
  return Object.values(config).every((value) => value && value !== "FIXME") ? config : undefined;
}

export async function notifyGroup(
  gql: GraphQL,
  userID: string,
  kind: Kind,
  expenseID: string,
  config: ApnsConfig | undefined,
  sendImpl: typeof send = send,
): Promise<Result> {
  const { expenses_by_pk: expense } = await gql<{ expenses_by_pk: ExpenseRow | null }>(
    `query Expense($id: uuid!) {
      expenses_by_pk(id: $id) {
        group_id title amount_cents payer_id participant_ids is_settlement
        group { name currency members { id name user_id } }
      }
    }`,
    { id: expenseID },
    userID,
  );
  if (!expense) return { status: 404, body: { error: "not_found" } };
  if (expense.is_settlement !== (kind === "settlement_added")) return { status: 400, body: { error: "wrong_kind" } };

  const people = expense.group.members;
  const participants = uuidArray(expense.participant_ids);
  const actor = people.find((m) => m.user_id === userID);
  if (!actor) return { status: 403, body: { error: "not_member" } };
  const nameOf = (memberID: string) => people.find((m) => m.id === memberID)?.name ?? "?";
  const involved = new Set<string>([expense.payer_id, ...participants]);

  // One event per recipient: who paid reads differently for each of them.
  const recipients = people.filter((m) => m.user_id && m.user_id !== userID && involved.has(m.id));
  if (recipients.length === 0) return { status: 200, body: { sent: 0, skipped: "no_recipients" } };

  const eventFor = (recipient: MemberRow): Event => {
    const common = {
      group: expense.group.name,
      groupId: expense.group_id,
      actor: actor.name,
      amountCents: expense.amount_cents,
      currency: expense.group.currency,
    };
    if (kind === "expense_added") {
      const payer = expense.payer_id === actor.id
        ? { type: "actor" as const }
        : expense.payer_id === recipient.id
        ? { type: "recipient" as const }
        : { type: "other" as const, name: nameOf(expense.payer_id) };
      return { kind, ...common, title: expense.title, payer };
    }
    const to = participants[0];
    return {
      kind,
      ...common,
      from: nameOf(expense.payer_id),
      to: nameOf(to),
      actorIsFrom: expense.payer_id === actor.id,
      recipient: recipient.id === to ? "to" : "from",
    };
  };

  if (!config) return { status: 200, body: { sent: 0, skipped: "not_configured" } };

  const byUser = new Map(recipients.map((m) => [m.user_id!, m]));
  const { device_tokens: devices } = await gql<{ device_tokens: (Device & { user_id: string })[] }>(
    `query Devices($users: [uuid!]!) { device_tokens(where: { user_id: { _in: $users } }) { token environment user_id } }`,
    { users: [...byUser.keys()] },
  );

  let sent = 0;
  const gone: string[] = [];
  await Promise.all(devices.map(async (device) => {
    const message = compose(eventFor(byUser.get(device.user_id)!));
    const outcome = await sendImpl(device, message, config).catch((error) => {
      console.error("notify-group: send failed", error);
      return "failed" as const;
    });
    if (outcome === "sent") sent++;
    if (outcome === "gone") gone.push(device.token);
  }));
  if (gone.length) {
    await gql(
      `mutation Forget($tokens: [String!]!) { delete_device_tokens(where: { token: { _in: $tokens } }) { affected_rows } }`,
      { tokens: gone },
    );
  }
  return { status: 200, body: { sent, removed: gone.length } };
}
