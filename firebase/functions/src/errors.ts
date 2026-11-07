// Errors the app shows in German. The hint travels in HttpsError.details, the app maps it to a message
// (BarteError in Backend.swift), like the hints the SQL functions raised on Supabase.
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

const CODES: Record<string, FunctionsErrorCode> = {
  not_member: "permission-denied",
  not_creator: "permission-denied",
  not_signed_in: "unauthenticated",
};

export class Failure extends Error {
  constructor(readonly hint: string) {
    super(hint);
  }
}

export function toHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof Failure) {
    return new HttpsError(CODES[error.hint] ?? "failed-precondition", error.hint, { hint: error.hint });
  }
  console.error(error);
  return new HttpsError("internal", "internal");
}
