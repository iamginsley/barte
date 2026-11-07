// Sends alerts through Apple Push Notification service with token-based (.p8) authentication.
import { importPKCS8, SignJWT } from "jose";
import type { Message } from "./messages.js";

export interface ApnsConfig {
  teamId: string;
  keyId: string;
  privateKey: string; // contents of an AuthKey_XXXX.p8 with Apple Push Notifications enabled
  topic: string; // the app's bundle ID
}

export interface Device {
  token: string;
  environment: "sandbox" | "production";
}

export type Outcome = "sent" | "gone" | "failed";

const HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

let cached: { jwt: string; issuedAt: number; keyId: string } | undefined;

/** Provider token; Apple accepts it for an hour and rejects refreshing more often than every 20 minutes. */
export async function providerToken(config: ApnsConfig, now = Date.now()): Promise<string> {
  const issuedAt = Math.floor(now / 1000);
  if (cached && cached.keyId === config.keyId && issuedAt - cached.issuedAt < 50 * 60) return cached.jwt;
  const key = await importPKCS8(config.privateKey.trim(), "ES256");
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt(issuedAt)
    .sign(key);
  cached = { jwt, issuedAt, keyId: config.keyId };
  return jwt;
}

export function payload(message: Message) {
  return {
    aps: {
      alert: { title: message.title, body: message.body },
      sound: message.passive ? undefined : "default",
      "thread-id": message.threadId,
      "interruption-level": message.passive ? "passive" : "active",
    },
    link: message.link,
  };
}

export async function send(
  device: Device,
  message: Message,
  config: ApnsConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<Outcome> {
  const headers: Record<string, string> = {
    authorization: `bearer ${await providerToken(config)}`,
    "apns-topic": config.topic,
    "apns-push-type": "alert",
    "apns-priority": message.passive ? "5" : "10",
    "content-type": "application/json",
  };

  const response = await fetchImpl(`${HOSTS[device.environment]}/3/device/${device.token}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload(message)),
  });
  if (response.ok) return "sent";
  const reason = await response.json().then((body) => body?.reason as string | undefined).catch(() => undefined);
  // 410: the app was removed. BadDeviceToken: a sandbox token sent to production or vice versa, or garbage.
  if (response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") return "gone";
  console.error(`notify: APNs ${response.status} ${reason ?? ""}`);
  return "failed";
}

/** Only for tests. */
export function resetTokenCache() {
  cached = undefined;
}
