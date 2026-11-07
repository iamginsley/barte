// Barte's server: callable functions for every write, a trigger for push notifications and
// account deletion. Everything runs in Frankfurt (europe-west3), next to the Firestore database.
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import * as api from "./api.js";
import { toHttpsError } from "./errors.js";
import { type ExpenseDoc, notifyExpense } from "./push/notify.js";

initializeApp();
setGlobalOptions({ region: "europe-west3", maxInstances: 10 });

const db = () => getFirestore();

type Handler<T> = (db: Firestore, uid: string, data: unknown) => Promise<T>;

/** Signed-in callers only; failures carry a hint the app turns into German text. */
function callable<T>(handler: Handler<T>) {
  return onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "not_signed_in", { hint: "not_signed_in" });
    try {
      // Always an object, so the app can decode every response.
      return (await handler(db(), uid, request.data)) ?? {};
    } catch (error) {
      throw toHttpsError(error);
    }
  });
}

export const createGroup = callable(api.createGroup);
export const updateGroup = callable(api.updateGroup);
export const deleteGroup = callable(api.deleteGroup);
export const leaveGroup = callable(api.leaveGroup);
export const regenerateInviteCode = callable(api.regenerateInviteCode);
export const previewInvite = callable(api.previewInvite);
export const joinGroup = callable(api.joinGroup);
export const claimMember = callable(api.claimMember);
export const addMember = callable(api.addMember);
export const renameMember = callable(api.renameMember);
export const removeMember = callable(api.removeMember);
export const saveExpense = callable(api.saveExpense);
export const deleteExpense = callable(api.deleteExpense);
export const setPaymentDetails = callable(api.setPaymentDetails);
export const paymentDetails = callable((database, uid) => api.paymentDetails(database, uid));
export const registerDevice = callable(api.registerDevice);
export const unregisterDevice = callable(api.unregisterDevice);

/**
 * The app revokes the Sign in with Apple link first (Auth.revokeToken), then calls this.
 * Removes the person's data and the auth user.
 */
export const deleteAccount = callable(async (database, uid) => {
  await api.deleteAccountData(database, uid);
  await getAuth().deleteUser(uid);
});

// Push ------------------------------------------------------------------------

// The contents of an AuthKey_XXXX.p8 with Apple Push Notifications enabled; set with
// `firebase functions:secrets:set APNS_PRIVATE_KEY < AuthKey_XXXX.p8`.
const apnsPrivateKey = defineSecret("APNS_PRIVATE_KEY");
const apnsKeyId = defineString("APNS_KEY_ID", { default: "" });
const appleTeamId = defineString("APPLE_TEAM_ID", { default: "2567P974L9" });
const apnsTopic = defineString("APNS_TOPIC", { default: "com.iamginsley.barte" });

export const notifyOnExpense = onDocumentCreated(
  { document: "groups/{groupId}/expenses/{expenseId}", secrets: [apnsPrivateKey] },
  async (event) => {
    const expense = event.data?.data() as ExpenseDoc | undefined;
    if (!expense) return;
    const config = {
      teamId: appleTeamId.value(),
      keyId: apnsKeyId.value(),
      privateKey: apnsPrivateKey.value(),
      topic: apnsTopic.value(),
    };
    const ready = Object.values(config).every(Boolean);
    if (!ready) console.warn("notify: APNs is not configured, skipping");
    await notifyExpense(db(), event.params.groupId, expense, ready ? config : undefined);
  },
);
