// Shared setup for the suites that run against the Firestore emulator (npm test starts it).
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { Failure } from "../src/errors.js";

export const projectId = "demo-barte";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Run these tests with `npm test`, which starts the Firestore emulator.");
}

if (getApps().length === 0) initializeApp({ projectId });
export const db = getFirestore();

export async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
}

/** The hint a call fails with, or undefined when it succeeds. */
export async function hint(promise: Promise<unknown>): Promise<string | undefined> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof Failure) return error.hint;
    throw error;
  }
  return undefined;
}
