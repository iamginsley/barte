import { expect, test } from "vitest";
import { Failure } from "../../src/errors.js";
import * as check from "../../src/validate.js";

const anna = "aaaaaaaa-0000-4000-8000-000000000001";
const ben = "aaaaaaaa-0000-4000-8000-000000000002";
const clara = "aaaaaaaa-0000-4000-8000-000000000003";
const members = new Set([anna, ben, clara]);
const expenseId = "eeeeeeee-0000-4000-8000-000000000001";

function hint(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (error) {
    return error instanceof Failure ? error.hint : "unexpected";
  }
  return undefined;
}

const base = { id: expenseId, title: " Chalet ", amountCents: 9000, spentOn: "2026-11-01", payerId: anna };

test("invite codes avoid look-alike characters", () => {
  for (let i = 0; i < 200; i++) expect(check.newInviteCode()).toMatch(/^[A-HJKMNP-Z2-9]{8}$/);
  expect(check.normalizeCode(" abcd2345 ")).toBe("ABCD2345");
  expect(hint(() => check.normalizeCode("x"))).toBe("invalid_code");
});

test("names are trimmed, blank names rejected", () => {
  expect(check.memberName("  Anna   Maria ")).toBe("Anna Maria");
  expect(check.memberName("x".repeat(50))).toHaveLength(40);
  expect(hint(() => check.memberName("   "))).toBe("empty_name");
  expect(check.currency("eur")).toBe("EUR");
  expect(hint(() => check.currency("EURO"))).toBe("invalid_input");
  expect(hint(() => check.color(32))).toBe("invalid_input");
});

test("days must be real calendar days", () => {
  expect(check.day("2026-02-28")).toBe("2026-02-28");
  expect(hint(() => check.day("2026-02-30"))).toBe("invalid_input");
  expect(hint(() => check.day("1.11.2026"))).toBe("invalid_input");
});

test("equal splits drop duplicate participants", () => {
  const expense = check.expense({ ...base, participantIds: [anna, ben, ben.toUpperCase()] }, members);
  expect(expense.title).toBe("Chalet");
  expect(expense.participantIds).toEqual([anna, ben]);
  expect(expense.splitKind).toBe("equal");
  expect(expense.splitValues).toBeNull();
});

test("expense checks", () => {
  expect(hint(() => check.expense({ ...base, participantIds: [] }, members))).toBe("no_participants");
  expect(hint(() => check.expense({ ...base, amountCents: 0, participantIds: [anna] }, members))).toBe("invalid_input");
  expect(hint(() => check.expense({ ...base, amountCents: 1.5, participantIds: [anna] }, members))).toBe("invalid_input");
  expect(hint(() => check.expense({ ...base, participantIds: ["aaaaaaaa-0000-4000-8000-000000000099"] }, members))).toBe("unknown_member");
  expect(hint(() => check.expense({ ...base, isSettlement: true, payerId: ben, participantIds: [anna, clara] }, members))).toBe("invalid_settlement");
  expect(hint(() => check.expense({ ...base, isSettlement: true, participantIds: [anna] }, members))).toBe("invalid_settlement");
  expect(check.expense({ ...base, isSettlement: true, payerId: ben, participantIds: [anna] }, members).isSettlement).toBe(true);
});

test("shares and exact amounts keep their order and must add up", () => {
  const shares = check.expense({ ...base, participantIds: [clara, anna], splitKind: "shares", splitValues: [2, 1] }, members);
  expect(shares.participantIds).toEqual([clara, anna]);
  expect(shares.splitValues).toEqual([2, 1]);

  const exact = { ...base, amountCents: 36000, payerId: ben, participantIds: [ben, clara], splitKind: "exact" };
  expect(check.expense({ ...exact, splitValues: [24000, 12000] }, members).splitValues).toEqual([24000, 12000]);
  expect(hint(() => check.expense({ ...exact, splitValues: [20000, 12000] }, members))).toBe("invalid_split");
  expect(hint(() => check.expense({ ...exact, splitValues: [36000] }, members))).toBe("invalid_split");
  expect(hint(() => check.expense({ ...base, participantIds: [ben, clara], splitKind: "shares", splitValues: [1, 0] }, members))).toBe("invalid_split");
  expect(hint(() => check.expense({ ...base, participantIds: [ben, ben], splitKind: "shares", splitValues: [1, 1] }, members))).toBe("invalid_split");
  expect(hint(() => check.expense({ ...base, participantIds: [ben], splitKind: "thirds", splitValues: [1] }, members))).toBe("invalid_split");
  expect(hint(() => check.expense({ ...base, isSettlement: true, payerId: ben, participantIds: [clara], splitKind: "exact", splitValues: [9000] }, members)))
    .toBe("invalid_settlement");
});

test("PayPal.me names from names, handles and links", () => {
  expect(check.paypal("anna")).toBe("anna");
  expect(check.paypal("@Anna92")).toBe("Anna92");
  expect(check.paypal("https://www.paypal.me/anna/12EUR")).toBe("anna");
  expect(check.paypal("  ")).toBeNull();
  expect(hint(() => check.paypal("anna maria"))).toBe("invalid_paypal");
});

test("IBANs are normalized and checked with mod 97", () => {
  expect(check.iban("de89 3704 0044 0532 0130 00")).toBe("DE89370400440532013000");
  expect(check.iban("")).toBeNull();
  expect(hint(() => check.iban("DE89370400440532013001"))).toBe("invalid_iban");
  expect(check.ibanIsValid("AT611904300234573201")).toBe(true);
  expect(check.accountHolder("  Anna   Beispiel ")).toBe("Anna Beispiel");
});
