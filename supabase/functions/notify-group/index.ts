// POST { "kind": "expense_added" | "settlement_added", "id": "<expense uuid>" } with the user's
// Supabase JWT (verify_jwt is on). Reads the expense with the caller's own rights (RLS keeps it to
// their groups), builds the message from the database rather than from client text, and pushes it
// to the other people in the group who use the app and are part of it.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { type ApnsConfig, type Device, send } from "./apns.ts";
import { compose, type Event } from "./messages.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const KINDS = ["expense_added", "settlement_added"] as const;
type Kind = (typeof KINDS)[number];

interface MemberRow {
  id: string;
  name: string;
  user_id: string | null;
}

function apnsConfig(): ApnsConfig | undefined {
  // One .p8 key can carry both Sign in with Apple and APNs, so the Apple key is the fallback.
  const config = {
    teamId: Deno.env.get("APPLE_TEAM_ID") ?? "",
    keyId: Deno.env.get("APNS_KEY_ID") ?? Deno.env.get("APPLE_KEY_ID") ?? "",
    privateKey: Deno.env.get("APNS_PRIVATE_KEY") ?? Deno.env.get("APPLE_PRIVATE_KEY") ?? "",
    topic: Deno.env.get("APNS_TOPIC") ?? "com.iamginsley.barte",
  };
  return Object.values(config).every(Boolean) ? config : undefined;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let kind: Kind, id: string;
  try {
    const body = await request.json();
    kind = body.kind;
    id = body.id;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!KINDS.includes(kind)) return json({ error: "unknown_kind" }, 400);
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "missing_id" }, 400);

  const url = Deno.env.get("SUPABASE_URL")!;
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: request.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  const { data: expense } = await asUser.from("expenses")
    .select("group_id, title, amount_cents, payer_id, participant_ids, is_settlement, groups(name, currency)")
    .eq("id", id)
    .maybeSingle();
  if (!expense) return json({ error: "not_found" }, 404);
  if (expense.is_settlement !== (kind === "settlement_added")) return json({ error: "wrong_kind" }, 400);

  const { data: members } = await asUser.from("members").select("id, name, user_id").eq("group_id", expense.group_id);
  const people: MemberRow[] = members ?? [];
  const group = expense.groups as unknown as { name: string; currency: string };
  const actor = people.find((m) => m.user_id === user.id);
  if (!actor) return json({ error: "not_member" }, 403);
  const nameOf = (memberId: string) => people.find((m) => m.id === memberId)?.name ?? "?";
  const involved = new Set<string>([expense.payer_id, ...(expense.participant_ids as string[])]);

  // One event per recipient: who paid reads differently for each of them.
  const recipients = people.filter((m) => m.user_id && m.user_id !== user.id && involved.has(m.id));
  if (recipients.length === 0) return json({ sent: 0, skipped: "no_recipients" });

  const eventFor = (recipient: MemberRow): Event => {
    const common = {
      group: group.name,
      groupId: expense.group_id as string,
      actor: actor.name,
      amountCents: expense.amount_cents as number,
      currency: group.currency,
    };
    if (kind === "expense_added") {
      const payer = expense.payer_id === actor.id
        ? { type: "actor" as const }
        : expense.payer_id === recipient.id
        ? { type: "recipient" as const }
        : { type: "other" as const, name: nameOf(expense.payer_id) };
      return { kind, ...common, title: expense.title, payer };
    }
    const to = (expense.participant_ids as string[])[0];
    return {
      kind,
      ...common,
      from: nameOf(expense.payer_id),
      to: nameOf(to),
      actorIsFrom: expense.payer_id === actor.id,
      recipient: recipient.id === to ? "to" : "from",
    };
  };

  const config = apnsConfig();
  if (!config) return json({ sent: 0, skipped: "not_configured" });

  const byUser = new Map(recipients.map((m) => [m.user_id!, m]));
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: devices } = await service.from("device_tokens")
    .select("token, environment, user_id").in("user_id", [...byUser.keys()]);

  let sent = 0;
  const gone: string[] = [];
  await Promise.all((devices ?? []).map(async (device: Device & { user_id: string }) => {
    const message = compose(eventFor(byUser.get(device.user_id)!));
    const outcome = await send(device, message, config).catch((error) => {
      console.error("notify-group: send failed", error);
      return "failed" as const;
    });
    if (outcome === "sent") sent++;
    if (outcome === "gone") gone.push(device.token);
  }));
  if (gone.length) await service.from("device_tokens").delete().in("token", gone);

  return json({ sent, removed: gone.length });
});
