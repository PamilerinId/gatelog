import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getMe } from "@/app/(dashboard)/_lib/api";
import { thisMonthLagos } from "@/app/(dashboard)/_lib/format";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import { NotForRole } from "@/app/(dashboard)/_components/ui";
import { MessagingView } from "./MessagingView";

export const metadata: Metadata = { title: "Messages" };

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;

export default async function MessagingPage({ searchParams }: { searchParams: Promise<{ month?: string }> }) {
  const me = await getMe();
  const { month: raw } = await searchParams;
  // The treasurer's messages are their first screen.
  if (me.role === "treasurer") redirect(raw ? `/dashboard?month=${encodeURIComponent(raw)}` : "/dashboard");
  if (!canOpen(me.role, "messaging")) return <NotForRole title="Messages" />;
  const current = thisMonthLagos();
  const month = raw && MONTH.test(raw) && raw <= current ? raw : current;
  return <MessagingView month={month} base="/dashboard/messaging" />;
}
