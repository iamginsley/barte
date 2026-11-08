// What the others in a group see. Pure functions, so the wording is tested without a server or APNs.

/** Who paid, from the recipient's point of view. */
export type Payer = { type: "actor" } | { type: "recipient" } | { type: "other"; name: string };

interface Common {
  group: string;
  groupId: string;
  /** Who made the change. */
  actor: string;
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
      | { type: "payer"; from: string; to: string }
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
}

export function money(cents: number, currency: string): string {
  const format = new Intl.NumberFormat("de-DE", { style: "currency", currency });
  return format.format(cents / 100).replace(/\s/g, " ");
}

export function compose(event: Event): Message {
  const base = { title: event.group, link: `barte://group/${event.groupId}`, threadId: event.groupId };
  const message = (body: string, passive = false): Message => ({ ...base, body, passive });
  switch (event.kind) {
    case "expense_added": {
      const amount = money(event.amountCents, event.currency);
      return message(
        event.payer.type === "actor"
          ? `${event.actor} hat „${event.title}“ bezahlt: ${amount}`
          : event.payer.type === "recipient"
          ? `${event.actor} hat „${event.title}“ eingetragen, bezahlt von dir: ${amount}`
          : `${event.actor} hat „${event.title}“ eingetragen, bezahlt von ${event.payer.name}: ${amount}`,
      );
    }
    case "settlement_added": {
      const amount = money(event.amountCents, event.currency);
      if (event.recipient === "to") {
        return message(
          event.actorIsFrom
            ? `${event.actor} hat dir ${amount} zurückgezahlt.`
            : `${event.actor} hat verbucht: ${event.from} hat dir ${amount} zurückgezahlt.`,
        );
      }
      return message(`${event.actor} hat verbucht: Du hast ${event.to} ${amount} zurückgezahlt.`, true);
    }
    case "settlement_deleted": {
      const amount = money(event.amountCents, event.currency);
      const between = event.recipient === "to" ? `von ${event.from} an dich` : `von dir an ${event.to}`;
      return message(`${event.actor} hat einen Ausgleich gelöscht: ${amount} ${between}.`);
    }
    case "expense_changed": {
      const what = event.change.type === "amount"
        ? `${money(event.change.from, event.currency)} → ${money(event.change.to, event.currency)}`
        : event.change.type === "payer"
        ? `bezahlt von ${event.change.to} statt ${event.change.from}`
        : "neue Aufteilung";
      return message(`${event.actor} hat „${event.title}“ geändert: ${what}`);
    }
    case "expense_deleted":
      return message(`${event.actor} hat „${event.title}“ gelöscht (${money(event.amountCents, event.currency)}).`);
    case "group_closed":
      return message(`${event.actor} hat die Gruppe abgeschlossen.`, true);
  }
}
