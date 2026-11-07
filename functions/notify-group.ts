// POST { "kind": "expense_added" | "settlement_added", "id": "<expense uuid>" } with the user's
// Nhost access token. Fire and forget from the app's side: a missing push never fails a change.
import type { Request, Response } from "express";
import { apnsConfig, KINDS, type Kind, notifyGroup } from "./_lib/notify";
import { callerID, graphql } from "./_lib/server";

export default async (req: Request, res: Response) => {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const userID = await callerID(req);
  if (!userID) return res.status(401).json({ error: "unauthorized" });

  const { kind, id } = (req.body ?? {}) as { kind?: Kind; id?: string };
  if (!kind || !KINDS.includes(kind)) return res.status(400).json({ error: "unknown_kind" });
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) return res.status(400).json({ error: "missing_id" });

  try {
    const result = await notifyGroup(graphql, userID, kind, id.toLowerCase(), apnsConfig());
    return res.status(result.status).json(result.body);
  } catch (error) {
    console.error("notify-group: unexpected error", error);
    return res.status(500).json({ error: "internal" });
  }
};
