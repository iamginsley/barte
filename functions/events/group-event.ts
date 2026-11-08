// Called by Hasura for every new row in public.group_events (event trigger in nhost/metadata),
// never by the app. Only Hasura knows the webhook secret, so nobody can send pushes in others' names.
import { createHash, timingSafeEqual } from "node:crypto";
import type { Request, Response } from "express";
import { apnsConfig, type GroupEventRow, notifyEvent } from "../_lib/notify";
import { graphql } from "../_lib/server";

const digest = (value: string) => createHash("sha256").update(value).digest();

export function fromHasura(header: unknown, secret = process.env.NHOST_WEBHOOK_SECRET): boolean {
  return typeof header === "string" && Boolean(secret) && timingSafeEqual(digest(header), digest(secret!));
}

export default async (req: Request, res: Response) => {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  if (!fromHasura(req.headers["nhost-webhook-secret"])) return res.status(401).json({ error: "unauthorized" });

  const row = (req.body as { event?: { data?: { new?: GroupEventRow } } })?.event?.data?.new;
  if (!row?.group_id || !row.kind) return res.status(400).json({ error: "missing_event" });

  try {
    const result = await notifyEvent(graphql, row, apnsConfig());
    return res.status(result.status).json(result.body);
  } catch (error) {
    // Answer 200 anyway: Hasura doesn't retry (num_retries: 0), and a missing push never undoes a change.
    console.error("group-event: unexpected error", error);
    return res.status(200).json({ sent: 0, error: "internal" });
  }
};
