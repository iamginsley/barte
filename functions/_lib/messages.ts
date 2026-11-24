// What the others in a group see, in each phone's language. Pure functions, so the wording is
// tested without a server or APNs.

/** Who paid, from the recipient's point of view. */
export type Payer = { type: "actor" } | { type: "recipient" } | { type: "other"; name: string };

/** Someone named in a message: the person reading it, or anyone else. */
export type Person = { type: "recipient" } | { type: "other"; name: string };

/** The languages the app speaks. Phones in any other language show the app in German. */
export type Language = "de" | "en";

interface Common {
  group: string;
  groupId: string;
  /** Who made the change; null when the history doesn't know (shown as "Jemand"/"Someone"). */
  actor: string | null;
  currency: string;
}

export type Event =
  | Common & { kind: "expense_added"; title: string; amountCents: number; payer: Payer }
  | Common & {
    kind: "settlement_added" | "settlement_deleted";
    amountCents: number;
    from: string;
    to: string;
    actorIsFrom: boolean;
    /** The recipient got the money, or paid it. */
    recipient: "to" | "from";
  }
  | Common & {
    kind: "expense_changed";
    title: string;
    /** The most telling difference: the amount, else who paid, else how it's split. */
    change:
      | { type: "amount"; from: number; to: number }
      | { type: "payer"; from: Person; to: Person }
      | { type: "split" };
  }
  | Common & { kind: "expense_deleted"; title: string; amountCents: number }
  | Common & { kind: "group_closed" };

export interface Message {
  title: string;
  body: string;
  /** barte:// link the app opens on tap. */
  link: string;
  threadId: string;
  /** Passive: lands in Notification Center without sound or lighting the screen. */
  passive: boolean;
  /** Notification category registered by the app (CHAT_MESSAGE has a reply field). */
  category?: string;
}

/**
 * The app's language for a device's BCP 47 tag ("en-GB" → en). Matches what iOS picks from the
 * app's languages, which the app sends; anything unknown is German, the app's default.
 */
export function languageOf(tag: string | null | undefined): Language {
  return /^en(-|$)/i.test(tag ?? "") ? "en" : "de";
}

/** An amount in the group's currency, formatted like on the phone (region included, e.g. "en-GB"). */
export function money(cents: number, currency: string, tag = "de-DE"): string {
  let format: Intl.NumberFormat;
  try {
    format = new Intl.NumberFormat(tag, { style: "currency", currency });
  } catch {
    format = new Intl.NumberFormat(languageOf(tag) === "en" ? "en" : "de-DE", { style: "currency", currency });
  }
  return format.format(cents / 100).replace(/\s/g, " ");
}

interface Wording {
  someone: string;
  quoted: (title: string) => string;
  paidByActor: (actor: string, title: string, amount: string) => string;
  paidByRecipient: (actor: string, title: string, amount: string) => string;
  paidByOther: (actor: string, title: string, payer: string, amount: string) => string;
  paidYouBack: (actor: string, amount: string) => string;
  recordedPaidYouBack: (actor: string, from: string, amount: string) => string;
  recordedYouPaidBack: (actor: string, to: string, amount: string) => string;
  settlementDeleted: (actor: string, amount: string, between: string) => string;
  fromThemToYou: (from: string) => string;
  fromYouToThem: (to: string) => string;
  changed: (actor: string, title: string, what: string) => string;
  payerChanged: (to: string, from: string) => string;
  you: string;
  newSplit: string;
  deleted: (actor: string, title: string, amount: string) => string;
  closed: (actor: string) => string;
  /** Chat: the line before a message about an expense. */
  about: (title: string) => string;
}

const wording: Record<Language, Wording> = {
  de: {
    someone: "Jemand",
    quoted: (title) => `„${title}“`,
    paidByActor: (actor, title, amount) => `${actor} hat ${title} bezahlt: ${amount}`,
    paidByRecipient: (actor, title, amount) => `${actor} hat ${title} eingetragen, bezahlt von dir: ${amount}`,
    paidByOther: (actor, title, payer, amount) => `${actor} hat ${title} eingetragen, bezahlt von ${payer}: ${amount}`,
    paidYouBack: (actor, amount) => `${actor} hat dir ${amount} zurückgezahlt.`,
    recordedPaidYouBack: (actor, from, amount) => `${actor} hat verbucht: ${from} hat dir ${amount} zurückgezahlt.`,
    recordedYouPaidBack: (actor, to, amount) => `${actor} hat verbucht: Du hast ${to} ${amount} zurückgezahlt.`,
    settlementDeleted: (actor, amount, between) => `${actor} hat einen Ausgleich gelöscht: ${amount} ${between}.`,
    fromThemToYou: (from) => `von ${from} an dich`,
    fromYouToThem: (to) => `von dir an ${to}`,
    changed: (actor, title, what) => `${actor} hat ${title} geändert: ${what}`,
    payerChanged: (to, from) => `bezahlt von ${to} statt ${from}`,
    you: "dir",
    newSplit: "neue Aufteilung",
    deleted: (actor, title, amount) => `${actor} hat ${title} gelöscht (${amount}).`,
    closed: (actor) => `${actor} hat die Gruppe abgeschlossen.`,
    about: (title) => `Zu „${title}“: `,
  },
  en: {
    someone: "Someone",
    quoted: (title) => `“${title}”`,
    paidByActor: (actor, title, amount) => `${actor} paid for ${title}: ${amount}`,
    paidByRecipient: (actor, title, amount) => `${actor} added ${title}, paid by you: ${amount}`,
    paidByOther: (actor, title, payer, amount) => `${actor} added ${title}, paid by ${payer}: ${amount}`,
    paidYouBack: (actor, amount) => `${actor} paid you back ${amount}.`,
    recordedPaidYouBack: (actor, from, amount) => `${actor} recorded: ${from} paid you back ${amount}.`,
    recordedYouPaidBack: (actor, to, amount) => `${actor} recorded: You paid ${to} back ${amount}.`,
    settlementDeleted: (actor, amount, between) => `${actor} deleted a settlement: ${amount} ${between}.`,
    fromThemToYou: (from) => `from ${from} to you`,
    fromYouToThem: (to) => `from you to ${to}`,
    changed: (actor, title, what) => `${actor} changed ${title}: ${what}`,
    payerChanged: (to, from) => `paid by ${to} instead of ${from}`,
    you: "you",
    newSplit: "new split",
    deleted: (actor, title, amount) => `${actor} deleted ${title} (${amount}).`,
    closed: (actor) => `${actor} closed the group.`,
    about: (title) => `About “${title}”: `,
  },
};

export function words(tag: string | null | undefined): Wording {
  return wording[languageOf(tag)];
}

/** The push for one device; `tag` is the device's language as stored with its token. */
export function compose(event: Event, tag = "de-DE"): Message {
  const w = words(tag);
  const base = { title: event.group, link: `barte://group/${event.groupId}`, threadId: event.groupId };
  const message = (body: string, passive = false): Message => ({ ...base, body, passive });
  const actor = event.actor ?? w.someone;
  const amountOf = (cents: number) => money(cents, event.currency, tag);
  switch (event.kind) {
    case "expense_added": {
      const amount = amountOf(event.amountCents);
      const title = w.quoted(event.title);
      return message(
        event.payer.type === "actor"
          ? w.paidByActor(actor, title, amount)
          : event.payer.type === "recipient"
          ? w.paidByRecipient(actor, title, amount)
          : w.paidByOther(actor, title, event.payer.name, amount),
      );
    }
    case "settlement_added": {
      const amount = amountOf(event.amountCents);
      if (event.recipient === "to") {
        return message(event.actorIsFrom ? w.paidYouBack(actor, amount) : w.recordedPaidYouBack(actor, event.from, amount));
      }
      return message(w.recordedYouPaidBack(actor, event.to, amount), true);
    }
    case "settlement_deleted": {
      const between = event.recipient === "to" ? w.fromThemToYou(event.from) : w.fromYouToThem(event.to);
      return message(w.settlementDeleted(actor, amountOf(event.amountCents), between));
    }
    case "expense_changed": {
      const name = (person: Person) => (person.type === "recipient" ? w.you : person.name);
      const what = event.change.type === "amount"
        ? `${amountOf(event.change.from)} → ${amountOf(event.change.to)}`
        : event.change.type === "payer"
        ? w.payerChanged(name(event.change.to), name(event.change.from))
        : w.newSplit;
      return message(w.changed(actor, w.quoted(event.title), what));
    }
    case "expense_deleted":
      return message(w.deleted(actor, w.quoted(event.title), amountOf(event.amountCents)));
    case "group_closed":
      return message(w.closed(actor), true);
  }
}
