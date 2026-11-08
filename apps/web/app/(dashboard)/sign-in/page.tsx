import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getToken } from "@/app/(dashboard)/_lib/session";
import { SignInForm } from "./SignInForm";

export const metadata: Metadata = { title: "Sign in" };

export default async function SignInPage({ searchParams }: { searchParams: Promise<{ expired?: string }> }) {
  if (await getToken()) redirect("/dashboard");
  const { expired } = await searchParams;
  return (
    <main id="main" className="dash-center">
      <div className="dash-signin">
        <Link href="/" className="dash-brand dash-brand--dark">
          <span className="dash-brand__mark" aria-hidden="true" />
          <span className="dash-brand__name">Gatelog</span>
        </Link>
        <div className="dash-card">
          <h1 className="dash-h1">Sign in to your estate</h1>
          {expired === "1" && (
            <p className="dash-msg dash-msg--warn" role="status">
              You were signed out. Please sign in again.
            </p>
          )}
          <SignInForm />
        </div>
        <p className="dash-muted dash-small">For estate admins, committee members and security heads.</p>
      </div>
    </main>
  );
}
