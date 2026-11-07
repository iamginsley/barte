// What a signed-in app may read and write directly. Everything else goes through the functions.
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, where } from "firebase/firestore";
import { afterAll, beforeAll, test } from "vitest";
import { projectId } from "./emulator.js";

let env: RulesTestEnvironment;
const groupId = "11111111-0000-4000-8000-000000000001";

beforeAll(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST!.split(":");
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"), host, port: Number(port) },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "groups", groupId), { name: "Ski", memberUids: ["a"], members: [] });
    await setDoc(doc(db, "groups", groupId, "expenses", "e1"), { title: "Chalet" });
    await setDoc(doc(db, "invites", "ABCD2345"), { groupId });
    await setDoc(doc(db, "paymentDetails", "a"), { paypal: "anna" });
    await setDoc(doc(db, "devices", "token"), { uid: "a" });
  });
});

afterAll(() => env.cleanup());

test("members read their group and its expenses", async () => {
  const db = env.authenticatedContext("a").firestore();
  await assertSucceeds(getDoc(doc(db, "groups", groupId)));
  await assertSucceeds(getDocs(query(collection(db, "groups"), where("memberUids", "array-contains", "a"))));
  await assertSucceeds(getDocs(collection(db, "groups", groupId, "expenses")));
});

test("outsiders and signed-out callers read nothing", async () => {
  for (const db of [env.authenticatedContext("b").firestore(), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(doc(db, "groups", groupId)));
    await assertFails(getDocs(collection(db, "groups")));
    await assertFails(getDocs(collection(db, "groups", groupId, "expenses")));
  }
  // An unfiltered list could leak other groups, even for a member.
  await assertFails(getDocs(collection(env.authenticatedContext("a").firestore(), "groups")));
});

test("nobody writes directly, not even members", async () => {
  const db = env.authenticatedContext("a").firestore();
  await assertFails(setDoc(doc(db, "groups", groupId), { name: "Hack", memberUids: ["a"] }));
  await assertFails(setDoc(doc(db, "groups", "new"), { name: "Neu", memberUids: ["a"] }));
  await assertFails(setDoc(doc(db, "groups", groupId, "expenses", "e2"), { title: "Hack" }));
  await assertFails(deleteDoc(doc(db, "groups", groupId, "expenses", "e1")));
});

test("invites, payment details and devices stay on the server", async () => {
  const db = env.authenticatedContext("a").firestore();
  await assertFails(getDoc(doc(db, "invites", "ABCD2345")));
  await assertFails(getDoc(doc(db, "paymentDetails", "a")));
  await assertFails(setDoc(doc(db, "paymentDetails", "a"), { paypal: "x" }));
  await assertFails(getDoc(doc(db, "devices", "token")));
});
