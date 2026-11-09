// Called by Hasura for every new row in public.chat_messages (event trigger in nhost/metadata),
// never by the app. Same webhook secret as group-event.
import type { Request, Response } from "express";
import { type ChatMessageRow, notifyChat } from "../_lib/chat";
import { apnsConfig } from "../_lib/notify";
import { graphql } from "../_lib/server";
import { fromHasura } from "./group-event";

export default async (req: Request, res: Response) => {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  if (!fromHasura(req.headers["nhost-webhook-secret"])) return res.status(401).json({ error: "unauthorized" });

  const row = (req.body as { event?: { data?: { new?: ChatMessageRow } } })?.event?.data?.new;
  if (!row?.group_id || !row.author_id) return res.status(400).json({ error: "missing_message" });

  try {
    const result = await notifyChat(graphql, row, apnsConfig());
    return res.status(result.status).json(result.body);
  } catch (error) {
    console.error("chat-message: unexpected error", error);
    return res.status(200).json({ sent: 0, error: "internal" });
  }
};
