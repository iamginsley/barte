// What the others in a group see. Pure functions, so the wording is tested without a server or APNs.

export type Event =
  | {
    kind: "expense_added";
    group: string;
    groupId: string;
    actor: string;
    title: string;
    amountCents: number;
    currency: string;
    /** Who paid, from the recipient's point of view. */
    payer: { type: "actor" } | { type: "recipient" } | { type: "other"; name: string };
  }
  | {
    kind: "settlement_added";
    group: string;
    groupId: string;
    actor: string;
    amountCents: number;
    currency: string;
    from: string;
    to: string;
    actorIsFrom: boolean;
    /** The recipient got the money, or paid it. */
    recipient: "to" | "from";
  };

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
  const amount = money(event.amountCents, event.currency);
  const base = { title: event.group, link: `barte://group/${event.groupId}`, threadId: event.groupId };
  switch (event.kind) {
    case "expense_added": {
      const body = event.payer.type === "actor"
        ? `${event.actor} hat „${event.title}“ bezahlt: ${amount}`
        : event.payer.type === "recipient"
        ? `${event.actor} hat „${event.title}“ eingetragen, bezahlt von dir: ${amount}`
        : `${event.actor} hat „${event.title}“ eingetragen, bezahlt von ${event.payer.name}: ${amount}`;
      return { ...base, body, passive: false };
    }
    case "settlement_added": {
      if (event.recipient === "to") {
        const body = event.actorIsFrom
          ? `${event.actor} hat dir ${amount} zurückgezahlt.`
          : `${event.actor} hat verbucht: ${event.from} hat dir ${amount} zurückgezahlt.`;
        return { ...base, body, passive: false };
      }
      return {
        ...base,
        body: `${event.actor} hat verbucht: Du hast ${event.to} ${amount} zurückgezahlt.`,
        passive: true,
      };
    }
  }
}
