// Turns one row of public.reminders into a push for the person who was reminded, and nobody else.
// The amount was checked by remind() in the database; the text comes from here, not from the app.
import { type ApnsConfig, type Device, send } from "./apns";
import { compose } from "./messages";
import type { Result } from "./notify";
import type { GraphQL } from "./server";

export interface ReminderRow {
  id: string;
  group_id: string;
  from_member: string;
  to_member: string;
  amount_cents: number;
}

export async function notifyReminder(
  gql: GraphQL,
  row: ReminderRow,
  config: ApnsConfig | undefined,
  sendImpl: typeof send = send,
): Promise<Result> {
  const { groups_by_pk: group } = await gql<{
    groups_by_pk: { name: string; currency: string; members: { id: string; name: string; user_id: string | null }[] } | null;
  }>(
    `query Group($id: uuid!) { groups_by_pk(id: $id) { name currency members { id name user_id } } }`,
    { id: row.group_id },
  );
  if (!group) return { status: 200, body: { sent: 0, skipped: "group_gone" } };
  const from = group.members.find((m) => m.id === row.from_member);
  const to = group.members.find((m) => m.id === row.to_member);
  if (!to?.user_id) return { status: 200, body: { sent: 0, skipped: "no_recipients" } };
  if (!config) return { status: 200, body: { sent: 0, skipped: "not_configured" } };

  const { device_tokens: devices } = await gql<{ device_tokens: (Device & { language: string | null })[] }>(
    `query Devices($users: [uuid!]!) { device_tokens(where: { user_id: { _in: $users } }) { token environment language } }`,
    { users: [to.user_id] },
  );

  let sent = 0;
  const gone: string[] = [];
  await Promise.all(devices.map(async (device) => {
    const message = compose({
      kind: "reminder",
      group: group.name,
      groupId: row.group_id,
      actor: from?.name ?? null,
      currency: group.currency,
      amountCents: row.amount_cents,
    }, device.language ?? "de");
    const outcome = await sendImpl(device, message, config).catch((error) => {
      console.error("reminder: send failed", error);
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
