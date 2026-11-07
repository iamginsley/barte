// Input checks and normalization. Pure functions, so the rules are tested without Firestore.
import { Failure } from "./errors.js";

export const LIMITS = {
  groupName: 60,
  memberName: 40,
  title: 80,
  maxAmountCents: 100_000_000_000,
  maxParticipants: 100,
  maxShareWeight: 100,
  maxColor: 31,
} as const;

/** Eight characters without look-alikes (0/O, 1/I/L), so codes can also be typed in by hand. */
export const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function newInviteCode(random: () => number = Math.random): string {
  let code = "";
  for (let i = 0; i < 8; i++) code += INVITE_ALPHABET[Math.floor(random() * INVITE_ALPHABET.length)];
  return code;
}

export function normalizeCode(value: unknown): string {
  if (typeof value !== "string") throw new Failure("invalid_code");
  const code = value.trim().toUpperCase();
  if (!/^[A-Z0-9]{6,12}$/.test(code)) throw new Failure("invalid_code");
  return code;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function uuid(value: unknown, hint = "invalid_input"): string {
  if (typeof value !== "string") throw new Failure(hint);
  const id = value.trim().toLowerCase();
  if (!UUID.test(id)) throw new Failure(hint);
  return id;
}

export function memberName(value: unknown): string {
  const name = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  if (name.length === 0) throw new Failure("empty_name");
  return [...name].slice(0, LIMITS.memberName).join("");
}

export function groupName(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (name.length === 0 || [...name].length > LIMITS.groupName) throw new Failure("invalid_input");
  return name;
}

export function currency(value: unknown): string {
  const code = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (!/^[A-Z]{3}$/.test(code)) throw new Failure("invalid_input");
  return code;
}

export function color(value: unknown): number {
  if (!Number.isInteger(value) || (value as number) < 0 || (value as number) > LIMITS.maxColor) {
    throw new Failure("invalid_input");
  }
  return value as number;
}

/** Wall-clock day on the phone that entered it; "today" comes from the device. */
export function day(value: unknown): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Failure("invalid_input");
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) {
    throw new Failure("invalid_input");
  }
  return value;
}

export type SplitKind = "equal" | "shares" | "exact";

export interface ExpenseInput {
  id: string;
  title: string;
  amountCents: number;
  spentOn: string;
  payerId: string;
  participantIds: string[];
  isSettlement: boolean;
  splitKind: SplitKind;
  splitValues: number[] | null;
}

/**
 * Checks an expense against the group's member ids. Equal splits drop duplicate participants;
 * shares and exact amounts keep the order, because the values line up with the participants.
 */
export function expense(raw: Record<string, unknown>, memberIds: Set<string>): ExpenseInput {
  const title = typeof raw.title === "string" ? raw.title.trim() : "";
  if (title.length === 0 || [...title].length > LIMITS.title) throw new Failure("invalid_input");

  const amountCents = raw.amountCents;
  if (!Number.isInteger(amountCents) || (amountCents as number) <= 0 || (amountCents as number) >= LIMITS.maxAmountCents) {
    throw new Failure("invalid_input");
  }

  if (!Array.isArray(raw.participantIds)) throw new Failure("no_participants");
  const sent = raw.participantIds.map((p) => uuid(p, "unknown_member"));
  const kind = (raw.splitKind ?? "equal") as string;
  const isSettlement = raw.isSettlement === true;

  let participantIds: string[];
  let splitValues: number[] | null = null;
  if (kind === "equal") {
    participantIds = [...new Set(sent)];
  } else if (kind === "shares" || kind === "exact") {
    participantIds = sent;
    const values = raw.splitValues;
    const valid = Array.isArray(values)
      && values.length === sent.length
      && new Set(sent).size === sent.length
      && values.every((v) => Number.isInteger(v) && v > 0)
      && (kind !== "shares" || values.every((v) => v <= LIMITS.maxShareWeight))
      && (kind !== "exact" || values.reduce((sum, v) => sum + v, 0) === amountCents);
    if (!valid) throw new Failure("invalid_split");
    splitValues = values as number[];
  } else {
    throw new Failure("invalid_split");
  }

  if (participantIds.length === 0) throw new Failure("no_participants");
  if (participantIds.length > LIMITS.maxParticipants) throw new Failure("invalid_input");

  const payerId = uuid(raw.payerId, "unknown_member");
  if (!memberIds.has(payerId) || participantIds.some((p) => !memberIds.has(p))) throw new Failure("unknown_member");
  if (isSettlement && (kind !== "equal" || participantIds.length !== 1 || participantIds[0] === payerId)) {
    throw new Failure("invalid_settlement");
  }

  return {
    id: uuid(raw.id),
    title,
    amountCents: amountCents as number,
    spentOn: day(raw.spentOn),
    payerId,
    participantIds,
    isSettlement,
    splitKind: kind as SplitKind,
    splitValues,
  };
}

// Payment details --------------------------------------------------------------

/** A PayPal.me name from a name, "@name" or a pasted paypal.me link. Null when empty. */
export function paypal(value: unknown): string | null {
  let text = typeof value === "string" ? value.trim() : "";
  if (text.length === 0) return null;
  text = text.replace(/^(https?:\/\/)?(www\.)?paypal\.me\//i, "");
  text = text.replace(/^@+/, "").split("/")[0];
  if (!/^[A-Za-z0-9]{1,20}$/.test(text)) throw new Failure("invalid_paypal");
  return text;
}

export function ibanIsValid(iban: string): boolean {
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  const rearranged = iban.slice(4) + iban.slice(0, 4);
  let remainder = 0;
  for (const char of rearranged) {
    remainder = /[0-9]/.test(char)
      ? (remainder * 10 + Number(char)) % 97
      : (remainder * 100 + char.charCodeAt(0) - 55) % 97;
  }
  return remainder === 1;
}

/** Upper-cased without spaces and dashes, checked with mod 97. Null when empty. */
export function iban(value: unknown): string | null {
  const text = typeof value === "string" ? value.replace(/[\s-]/g, "").toUpperCase() : "";
  if (text.length === 0) return null;
  if (!ibanIsValid(text)) throw new Failure("invalid_iban");
  return text;
}

export function accountHolder(value: unknown): string | null {
  const text = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  return text.length === 0 ? null : [...text].slice(0, 70).join("");
}
