// Turns one row of the group history (public.group_events) into push notifications. Hasura calls
// this for every new row, so a change can't avoid notifying the others: the message comes from the
// database's before/after snapshot, never from text a client sent.
import { type ApnsConfig, type Device, send } from "./apns";
import { compose, type Event, type Payer, type Person } from "./messages";
import type { GraphQL } from "./server";

/** An expense as the history stores it (expense_snapshot in the migration). */
export interface Snapshot {
  title: string;
  amount_cents: number;
  payer_id: string;
  participant_ids: string[];
  is_settlement: boolean;
  split_kind: string;
  split_values: number[] | null;
}

export interface GroupEventRow {
  id: string;
  group_id: string;
  kind: string;
  actor_id: string | null;
  actor_name: string | null;
  subject_id: string | null;
  old: Snapshot | null;
  new: Snapshot | null;
}

interface MemberRow {
  id: string;
  name: string;
  user_id: string | null;
}

export type Result = { status: number; body: Record<string, unknown> };

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

const involved = (s: Snapshot | null) => (s ? [s.payer_id, ...s.participant_ids] : []);

/** Whether an edit changed what anyone owes; title and date changes stay in the history only. */
export function changesMoney(old: Snapshot, next: Snapshot): boolean {
  const key = (s: Snapshot) =>
    JSON.stringify([s.amount_cents, s.payer_id, [...s.participant_ids].sort(), s.split_kind, s.split_values, s.is_settlement]);
  return key(old) !== key(next);
}

/** Who should hear about this event: member ids, before removing the actor and people without the app. */
function audience(row: GroupEventRow, members: MemberRow[]): Set<string> | undefined {
  switch (row.kind) {
    case "expense_added":
    case "settlement_added":
      return new Set(involved(row.new));
    case "expense_deleted":
    case "settlement_deleted":
      return new Set(involved(row.old));
    case "expense_changed":
      if (!row.old || !row.new || !changesMoney(row.old, row.new)) return undefined;
      return new Set([...involved(row.old), ...involved(row.new)]);
    case "group_closed":
      return new Set(members.map((m) => m.id));
    default:
      // Renames, reopening, members: the history shows them, a push would only be noise.
      return undefined;
  }
}

export function eventFor(
  row: GroupEventRow,
  group: { name: string; currency: string },
  members: MemberRow[],
  recipient: MemberRow,
): Event | undefined {
  const plain = (id: string) => members.find((m) => m.id === id)?.name ?? "?";
  const person = (id: string): Person => (id === recipient.id ? { type: "recipient" } : { type: "other", name: plain(id) });
  const actorMember = members.find((m) => m.user_id && m.user_id === row.actor_id);
  const common = { group: group.name, groupId: row.group_id, actor: row.actor_name, currency: group.currency };
  const snapshot = row.new ?? row.old;

  switch (row.kind) {
    case "expense_added": {
      const s = row.new!;
      const payer: Payer = s.payer_id === actorMember?.id
        ? { type: "actor" }
        : s.payer_id === recipient.id
        ? { type: "recipient" }
        : { type: "other", name: plain(s.payer_id) };
      return { kind: "expense_added", ...common, title: s.title, amountCents: s.amount_cents, payer };
    }
    case "settlement_added":
    case "settlement_deleted": {
      const s = snapshot!;
      const to = s.participant_ids[0];
      return {
        kind: row.kind,
        ...common,
        amountCents: s.amount_cents,
        from: plain(s.payer_id),
        to: plain(to),
        actorIsFrom: s.payer_id === actorMember?.id,
        recipient: recipient.id === to ? "to" : "from",
      };
    }
    case "expense_changed": {
      const [old, next] = [row.old!, row.new!];
      const change = old.amount_cents !== next.amount_cents
        ? { type: "amount" as const, from: old.amount_cents, to: next.amount_cents }
        : old.payer_id !== next.payer_id
        ? { type: "payer" as const, from: person(old.payer_id), to: person(next.payer_id) }
        : { type: "split" as const };
      return { kind: "expense_changed", ...common, title: next.title, change };
    }
    case "expense_deleted":
      return { kind: "expense_deleted", ...common, title: row.old!.title, amountCents: row.old!.amount_cents };
    case "group_closed":
      return { kind: "group_closed", ...common };
    default:
      return undefined;
  }
}

export async function notifyEvent(
  gql: GraphQL,
  row: GroupEventRow,
  config: ApnsConfig | undefined,
  sendImpl: typeof send = send,
): Promise<Result> {
  const { groups_by_pk: group } = await gql<{
    groups_by_pk: { name: string; currency: string; members: MemberRow[] } | null;
  }>(
    `query Group($id: uuid!) { groups_by_pk(id: $id) { name currency members { id name user_id } } }`,
    { id: row.group_id },
  );
  if (!group) return { status: 200, body: { sent: 0, skipped: "group_gone" } };

  const wanted = audience(row, group.members);
  if (!wanted) return { status: 200, body: { sent: 0, skipped: "quiet" } };

  // The one who made the change already knows.
  const recipients = group.members.filter((m) => m.user_id && m.user_id !== row.actor_id && wanted.has(m.id));
  if (recipients.length === 0) return { status: 200, body: { sent: 0, skipped: "no_recipients" } };
  if (!config) return { status: 200, body: { sent: 0, skipped: "not_configured" } };

  const byUser = new Map(recipients.map((m) => [m.user_id!, m]));
  const { device_tokens: devices } = await gql<{ device_tokens: (Device & { user_id: string; language: string | null })[] }>(
    `query Devices($users: [uuid!]!) { device_tokens(where: { user_id: { _in: $users } }) { token environment user_id language } }`,
    { users: [...byUser.keys()] },
  );

  let sent = 0;
  const gone: string[] = [];
  await Promise.all(devices.map(async (device) => {
    const event = eventFor(row, group, group.members, byUser.get(device.user_id)!);
    if (!event) return;
    const outcome = await sendImpl(device, compose(event, device.language ?? "de"), config).catch((error) => {
      console.error("group-event: send failed", error);
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
