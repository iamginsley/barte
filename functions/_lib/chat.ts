// Turns a new chat message (public.chat_messages) into push notifications for everyone else in
// the group who uses the app and hasn't muted the chat. Hasura calls this for every new row.
import { type ApnsConfig, type Device, send } from "./apns";
import { type Message, words } from "./messages";
import type { Result } from "./notify";
import type { GraphQL } from "./server";

export interface ChatMessageRow {
  id: string;
  group_id: string;
  member_id: string | null;
  author_id: string;
  body: string | null;
  expense_id: string | null;
}

/** Long messages are cut at a word, so the banner stays readable; the app shows the rest. */
export function preview(body: string, limit = 180): string {
  const flat = body.replace(/\s+/g, " ").trim();
  if (flat.length <= limit) return flat;
  const cut = flat.slice(0, limit);
  const space = cut.lastIndexOf(" ");
  return `${(space > limit * 0.6 ? cut.slice(0, space) : cut).trimEnd()} …`;
}

/** "Anna" as the title, the group below it, and what was written; `tag` is the device's language. */
export function composeChat(
  row: ChatMessageRow,
  group: { name: string },
  author: string | null,
  expenseTitle?: string,
  tag = "de-DE",
): Message {
  const w = words(tag);
  const about = expenseTitle ? w.about(expenseTitle) : "";
  return {
    title: `${author ?? w.someone} · ${group.name}`,
    body: about + preview(row.body ?? ""),
    link: `barte://group/${row.group_id}/chat`,
    // One thread per chat, apart from the group's expense notifications.
    threadId: `chat-${row.group_id}`,
    passive: false,
    category: "CHAT_MESSAGE",
  };
}

interface GroupData {
  name: string;
  members: { id: string; name: string; user_id: string | null }[];
  chat_states: { user_id: string; muted: boolean }[];
  expenses: { id: string; title: string }[];
}

export async function notifyChat(
  gql: GraphQL,
  row: ChatMessageRow,
  config: ApnsConfig | undefined,
  sendImpl: typeof send = send,
): Promise<Result> {
  if (!row.body) return { status: 200, body: { sent: 0, skipped: "deleted" } };
  const { groups_by_pk: group } = await gql<{ groups_by_pk: GroupData | null }>(
    `query Chat($id: uuid!, $expense: uuid) {
      groups_by_pk(id: $id) {
        name
        members { id name user_id }
        chat_states { user_id muted }
        expenses(where: { id: { _eq: $expense } }) { id title }
      }
    }`,
    { id: row.group_id, expense: row.expense_id ?? "00000000-0000-0000-0000-000000000000" },
  );
  if (!group) return { status: 200, body: { sent: 0, skipped: "group_gone" } };

  const muted = new Set(group.chat_states.filter((s) => s.muted).map((s) => s.user_id));
  const users = group.members
    .map((m) => m.user_id)
    .filter((id): id is string => Boolean(id) && id !== row.author_id && !muted.has(id!));
  if (users.length === 0) return { status: 200, body: { sent: 0, skipped: "no_recipients" } };
  if (!config) return { status: 200, body: { sent: 0, skipped: "not_configured" } };

  const author = group.members.find((m) => m.id === row.member_id)?.name ?? null;
  const { device_tokens: devices } = await gql<{ device_tokens: (Device & { language: string | null })[] }>(
    `query Devices($users: [uuid!]!) { device_tokens(where: { user_id: { _in: $users } }) { token environment language } }`,
    { users },
  );

  let sent = 0;
  const gone: string[] = [];
  await Promise.all(devices.map(async (device) => {
    const message = composeChat(row, group, author, group.expenses[0]?.title, device.language ?? "de");
    const outcome = await sendImpl(device, message, config).catch((error) => {
      console.error("chat-message: send failed", error);
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
