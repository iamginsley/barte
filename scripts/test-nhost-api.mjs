#!/usr/bin/env node
// End-to-end check of the deployed Nhost project: Hasura permissions, the SQL functions as
// mutations, error messages and the shape of the data the app decodes.
//
// Uses the admin secret to create three throwaway users and then acts as each of them with the
// `user` role, exactly like the app. Everything it creates is removed again at the end.
//
//   NHOST_ADMIN_SECRET=… node scripts/test-nhost-api.mjs
//
// The admin secret is in the Nhost dashboard (Settings → Secrets); never commit it.
import { randomUUID } from "node:crypto";

const subdomain = process.env.NHOST_SUBDOMAIN ?? "uenqaayyhyrekjhojdwn";
const region = process.env.NHOST_REGION ?? "eu-central-1";
const secret = process.env.NHOST_ADMIN_SECRET;
if (!secret) {
  console.error("Set NHOST_ADMIN_SECRET.");
  process.exit(2);
}
const graphqlURL = `https://${subdomain}.graphql.${region}.nhost.run/v1`;
const hasuraURL = `https://${subdomain}.hasura.${region}.nhost.run`;

async function sql(statement) {
  const response = await fetch(`${hasuraURL}/v2/query`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-hasura-admin-secret": secret },
    body: JSON.stringify({ type: "run_sql", args: { source: "default", sql: statement } }),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`run_sql: ${JSON.stringify(body)}`);
  return body;
}

async function gql(user, query, variables = {}) {
  const headers = { "content-type": "application/json", "x-hasura-admin-secret": secret };
  if (user) Object.assign(headers, { "x-hasura-role": "user", "x-hasura-user-id": user });
  const response = await fetch(graphqlURL, { method: "POST", headers, body: JSON.stringify({ query, variables }) });
  return response.json();
}

async function call(user, fn, args) {
  const body = await gql(user, `mutation Call($args: ${fn}_args!) { ${fn}(args: $args) { id code preview } }`, { args });
  if (body.errors) throw Object.assign(new Error(body.errors[0].message), { graphql: body.errors[0] });
  return body.data[fn][0];
}

let failures = 0;
function check(ok, label) {
  console.log(`${ok ? "✓" : "✗"} ${label}`);
  if (!ok) failures++;
}
async function fails(promise, message, label) {
  try {
    await promise;
    check(false, `${label} (no error)`);
  } catch (error) {
    check(error.message === message, `${label} → "${error.message}"`);
  }
}

const [a, b, c] = [randomUUID(), randomUUID(), randomUUID()];
const users = [a, b, c];

try {
  await sql(`insert into auth.users (id, locale, display_name) values ${users.map((id, i) => `('${id}', 'de', 'API-Test ${i}')`).join(", ")}`);

  // A creates a group; only A sees it.
  const { id: group } = await call(a, "create_group", {
    p_name: "API-Test", p_currency: "EUR", p_color: 0, p_my_name: "Anna", p_other_names: '{"Ben","Clara \\"C\\""}',
  });
  check(Boolean(group), "create_group returns the id");

  const groupsQuery = `{ groups { id invite_code members(order_by: { created_at: asc }) { id name user_id created_at } expenses { id participant_ids split_values created_at } } }`;
  const seenByA = (await gql(a, groupsQuery)).data.groups;
  check(seenByA.length === 1 && seenByA[0].members.length === 3, "A sees the group with three members");
  check(seenByA[0].members[2].name === 'Clara "C"', "names with quotes survive the array literal");
  check((await gql(b, groupsQuery)).data.groups.length === 0, "B sees no groups before joining");
  check((await gql(b, "{ members { id } expenses { id } }")).data.members.length === 0, "B sees no members before joining");

  const [anna, ben] = seenByA[0].members;
  const code = seenByA[0].invite_code;

  // Errors reach the app with the hint as the message.
  await fails(call(b, "add_member", { p_group_id: group, p_name: "Eve" }), "not_member", "outsider cannot add members");
  await fails(call(b, "preview_invite", { p_code: "NOPE1234" }), "invalid_code", "unknown invite code");

  // Users cannot write tables directly or read devices.
  const direct = await gql(a, `mutation { insert_groups_one(object: { name: "X" }) { id } }`);
  check(Boolean(direct.errors), "no direct inserts");
  const devices = await gql(a, `{ device_tokens { token } }`);
  check(Boolean(devices.errors), "device tokens are not readable");
  const results = await gql(a, `{ api_results { id } }`);
  check(Boolean(results.errors), "api_results is not a query root");

  // B previews and joins as Ben.
  const preview = await call(b, "preview_invite", { p_code: code.toLowerCase() });
  check(preview.preview?.name === "API-Test" && preview.preview.is_member === false, "preview as JSON object");
  await call(b, "join_group", { p_code: code, p_member_id: ben.id, p_name: null });
  check((await gql(b, groupsQuery)).data.groups.length === 1, "B sees the group after joining");

  // Expenses with arrays.
  const expense = randomUUID();
  await call(b, "save_expense", {
    p_id: expense, p_group_id: group, p_title: "Pizza", p_amount_cents: 3000, p_spent_on: "2026-11-07",
    p_payer_id: anna.id, p_participant_ids: `{${anna.id},${ben.id}}`, p_is_settlement: false,
    p_split_kind: "shares", p_split_values: "{2,1}",
  });
  const saved = (await gql(a, groupsQuery)).data.groups[0].expenses[0];
  check(Array.isArray(saved.participant_ids) && saved.participant_ids.length === 2, `participant_ids come back as a JSON array (${JSON.stringify(saved.participant_ids)})`);
  check(JSON.stringify(saved.split_values) === "[2,1]", `split_values come back as numbers (${JSON.stringify(saved.split_values)})`);
  console.log(`  timestamps look like ${saved.created_at}`);
  check((await gql(c, `{ expenses { id } }`)).data.expenses.length === 0, "outsider C sees no expenses");

  // Payment details: visible within shared groups only.
  await call(a, "set_payment_details", { p_paypal: "annah", p_iban: null, p_account_holder: null });
  const paymentsQuery = `{ payment_details { user_id paypal } }`;
  check((await gql(b, paymentsQuery)).data.payment_details.some((p) => p.user_id === a), "B sees A's payment details");
  check((await gql(c, paymentsQuery)).data.payment_details.length === 0, "C sees no payment details");

  // Devices and functions without arguments.
  await call(a, "register_device", { p_token: "ab".repeat(32), p_environment: "sandbox" });
  const deleted = await gql(c, `mutation { delete_my_account { id } }`);
  check(!deleted.errors, "delete_my_account works without arguments");
  const remaining = (await sql(`select count(*) from auth.users where id = '${c}'`)).result[1][0];
  check(remaining === "0", "C's auth user is gone");

  // Leaving and deleting.
  await fails(call(b, "delete_group", { p_group_id: group }), "not_creator", "B cannot delete A's group");
  await call(a, "delete_group", { p_group_id: group });
  check((await gql(b, groupsQuery)).data.groups.length === 0, "deleted for everyone");
} catch (error) {
  console.error("✗ unexpected:", error.message, error.graphql ?? "");
  failures++;
} finally {
  const list = users.map((id) => `'${id}'`).join(", ");
  await sql(`delete from public.groups where id in (select group_id from public.members where user_id in (${list})); delete from auth.users where id in (${list});`)
    .catch((error) => console.error("cleanup failed:", error.message));
}

console.log(failures ? `${failures} check(s) failed.` : "All API checks passed.");
process.exit(failures ? 1 : 0);
