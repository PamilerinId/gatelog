import "server-only";

import { cookies } from "next/headers";

// The staff token never reaches client JavaScript: httpOnly, set and cleared only on the server.
export const SESSION_COOKIE = "gatelog_session";
const MAX_AGE = 60 * 60 * 12; // matches the API's 12 hour staff token

export async function getToken(): Promise<string | null> {
  return (await cookies()).get(SESSION_COOKIE)?.value ?? null;
}

/** Only from a Server Action or Route Handler. */
export async function setToken(token: string) {
  (await cookies()).set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: MAX_AGE,
  });
}

/** Only from a Server Action or Route Handler. */
export async function clearToken() {
  (await cookies()).delete(SESSION_COOKIE);
}
