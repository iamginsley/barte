// Chat pushes: wording, who gets them, muting.
import { expect, test } from "vitest";
import type { Device, send } from "../_lib/apns";
import { type ChatMessageRow, composeChat, notifyChat, preview } from "../_lib/chat";
import type { Message } from "../_lib/messages";
import { payload } from "../_lib/apns";
import type { GraphQL } from "../_lib/server";

const groupId = "11111111-2222-3333-4444-555555555555";
const members = [
  { id: "m-anna", name: "Anna", user_id: "u-anna" },
  { id: "m-ben", name: "Ben", user_id: "u-ben" },
  { id: "m-clara", name: "Clara", user_id: "u-clara" },
  { id: "m-david", name: "David", user_id: null },
];
const devices = [
  { token: "aa".repeat(32), environment: "sandbox", user_id: "u-anna" },
  { token: "bb".repeat(32), environment: "production", user_id: "u-ben" },
  { token: "cc".repeat(32), environment: "sandbox", user_id: "u-clara", language: "en-US" },
];
const config = { teamId: "T", keyId: "K", privateKey: "unused", topic: "com.iamginsley.barte" };

const message = (over: Partial<ChatMessageRow> = {}): ChatMessageRow => ({
  id: "msg1", group_id: groupId, member_id: "m-anna", author_id: "u-anna", body: "Wer hat Bargeld?", expense_id: null, ...over,
});

function fakeGraphQL(muted: string[] = [], expenses: { id: string; title: string }[] = []) {
  const calls: { query: string; variables: Record<string, unknown>; asUser?: string }[] = [];
  const gql = (async (query: string, variables: Record<string, unknown>, asUser?: string) => {
    calls.push({ query, variables, asUser });
    if (query.includes("groups_by_pk")) {
      return {
        groups_by_pk: {
          name: "Skiurlaub", members,
          chat_states: muted.map((user_id) => ({ user_id, muted: true })),
          expenses: expenses.filter((e) => e.id === variables.expense),
        },
      };
    }
    if (query.includes("query Devices")) {
      const users = variables.users as string[];
      return { device_tokens: devices.filter((d) => users.includes(d.user_id)) };
    }
    return { delete_device_tokens: { affected_rows: 0 } };
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

test("chat push: author and group as title, reply category, own thread", () => {
  const push = composeChat(message(), { name: "Skiurlaub" }, "Anna");
  expect(push.title).toBe("Anna · Skiurlaub");
  expect(push.body).toBe("Wer hat Bargeld?");
  expect(push.link).toBe(`barte://group/${groupId}/chat`);
  expect(push.threadId).toBe(`chat-${groupId}`);
  expect(payload(push).aps.category).toBe("CHAT_MESSAGE");
  expect(composeChat(message(), { name: "Skiurlaub" }, "Anna", "Pizza").body).toBe("Zu „Pizza“: Wer hat Bargeld?");
});

test("chat push in English", () => {
  expect(composeChat(message(), { name: "Ski Trip" }, "Anna", "Pizza", "en-GB").body).toBe("About “Pizza”: Wer hat Bargeld?");
  expect(composeChat(message(), { name: "Ski Trip" }, null, undefined, "en-GB").title).toBe("Someone · Ski Trip");
  expect(composeChat(message(), { name: "Skiurlaub" }, null).title).toBe("Jemand · Skiurlaub");
});

test("long messages are cut at a word", () => {
  expect(preview("kurz")).toBe("kurz");
  expect(preview("eins\n\nzwei")).toBe("eins zwei");
  const long = preview("wort ".repeat(60));
  expect(long.length).toBeLessThanOrEqual(182);
  expect(long.endsWith("wort …")).toBe(true);
});

test("everyone else with the app gets it, the author doesn't", async () => {
  const { gql, calls } = fakeGraphQL();
  const { sent, sendImpl } = recorder();
  expect(await notifyChat(gql, message(), config, sendImpl)).toEqual({ status: 200, body: { sent: 2, removed: 0 } });
  expect(calls.every((c) => c.asUser === undefined)).toBe(true);
  expect(sent.map((s) => s.device.token).sort()).toEqual(["bb".repeat(32), "cc".repeat(32)]);
});

test("muted chats stay quiet", async () => {
  const { sent, sendImpl } = recorder();
  await notifyChat(fakeGraphQL(["u-ben"]).gql, message(), config, sendImpl);
  expect(sent.map((s) => s.device.token)).toEqual(["cc".repeat(32)]);
  const allMuted = await notifyChat(fakeGraphQL(["u-ben", "u-clara"]).gql, message(), config, recorder().sendImpl);
  expect(allMuted.body).toEqual({ sent: 0, skipped: "no_recipients" });
});

test("a message about an expense names it", async () => {
  const { sent, sendImpl } = recorder();
  await notifyChat(fakeGraphQL([], [{ id: "e1", title: "Pizza" }]).gql, message({ expense_id: "e1", member_id: "m-ben", author_id: "u-ben" }), config, sendImpl);
  expect(sent.find((s) => s.device.token === "aa".repeat(32))!.message.body).toBe("Zu „Pizza“: Wer hat Bargeld?");
  expect(sent.find((s) => s.device.token === "cc".repeat(32))!.message.body).toBe("About “Pizza”: Wer hat Bargeld?");
  expect([...new Set(sent.map((s) => s.message.title))]).toEqual(["Ben · Skiurlaub"]);
});

test("deleted messages and missing configuration send nothing", async () => {
  expect((await notifyChat(fakeGraphQL().gql, message({ body: null }), config, recorder().sendImpl)).body).toEqual({ sent: 0, skipped: "deleted" });
  expect((await notifyChat(fakeGraphQL().gql, message(), undefined, recorder().sendImpl)).body).toEqual({ sent: 0, skipped: "not_configured" });
});

test("gone devices are forgotten", async () => {
  const { gql, calls } = fakeGraphQL();
  const result = await notifyChat(gql, message(), config, recorder((d) => (d.token === "bb".repeat(32) ? "gone" : "sent")).sendImpl);
  expect(result.body).toEqual({ sent: 1, removed: 1 });
  expect(calls.at(-1)!.variables.tokens).toEqual(["bb".repeat(32)]);
});
