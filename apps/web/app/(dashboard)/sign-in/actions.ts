"use server";

import { redirect } from "next/navigation";
import { apiRequest } from "@/app/(dashboard)/_lib/api";
import { setToken } from "@/app/(dashboard)/_lib/session";
import type { ActionState, Me } from "@/app/(dashboard)/_lib/types";

function email(fd: FormData) {
  const v = fd.get("email");
  return typeof v === "string" ? v.trim().toLowerCase() : "";
}

export async function requestCode(fd: FormData): Promise<ActionState> {
  const to = email(fd);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) return { ok: false, error: "Enter the email address your estate registered for you." };
  const r = await apiRequest("/v1/auth/email-code", { method: "POST", json: { email: to } });
  if (!r.ok) return { ok: false, error: r.error };
  return { ok: true, data: { email: to } };
}

export async function verifyCode(fd: FormData): Promise<ActionState> {
  const to = email(fd);
  const code = String(fd.get("code") ?? "").replace(/\D/g, "");
  if (code.length !== 6) return { ok: false, error: "The code is six digits." };
  const r = await apiRequest<{ token: string; staff: Pick<Me, "role"> }>("/v1/auth/verify", { method: "POST", json: { email: to, code } });
  if (!r.ok) return { ok: false, error: r.error };
  if (r.data.staff.role === "ops") return { ok: false, error: "This dashboard is for estate staff. Gatelog ops accounts are not supported here." };
  await setToken(r.data.token);
  redirect("/dashboard");
}
