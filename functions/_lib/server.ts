// What both functions need from Nhost: who is calling, and GraphQL with the admin secret.
import type { Request } from "express";
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

let jwks: JWTVerifyGetKey | undefined;

/** The project's public signing keys, the same ones Hasura checks tokens against. */
function projectKeys(): JWTVerifyGetKey {
  if (!jwks) {
    const { NHOST_SUBDOMAIN: subdomain, NHOST_REGION: region } = process.env;
    jwks = createRemoteJWKSet(new URL(`https://${subdomain}.auth.${region}.nhost.run/v1/.well-known/jwks.json`));
  }
  return jwks;
}

/** The signed-in person's id from the Nhost access token, or undefined when it is missing or invalid. */
export async function callerID(request: Request, keys: JWTVerifyGetKey = projectKeys()): Promise<string | undefined> {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) return undefined;
  try {
    const { payload } = await jwtVerify(header.slice(7), keys);
    const claims = payload["https://hasura.io/jwt/claims"] as Record<string, string> | undefined;
    return claims?.["x-hasura-user-id"] ?? undefined;
  } catch {
    return undefined;
  }
}

export type GraphQL = <T>(query: string, variables: Record<string, unknown>, asUser?: string) => Promise<T>;

/**
 * GraphQL against this project's Hasura. With `asUser`, the query runs with that person's
 * permissions (role `user`), exactly as if the app had sent it.
 */
export const graphql: GraphQL = async <T>(query: string, variables: Record<string, unknown>, asUser?: string) => {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-hasura-admin-secret": process.env.NHOST_ADMIN_SECRET ?? "",
  };
  if (asUser) {
    headers["x-hasura-role"] = "user";
    headers["x-hasura-user-id"] = asUser;
  }
  const response = await fetch(process.env.NHOST_GRAPHQL_URL!, {
    method: "POST",
    headers,
    body: JSON.stringify({ query, variables }),
  });
  const body = (await response.json()) as { data?: T; errors?: { message: string }[] };
  if (body.errors?.length || !body.data) throw new Error(`graphql: ${body.errors?.[0]?.message ?? response.status}`);
  return body.data;
};
