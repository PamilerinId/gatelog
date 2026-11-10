"use client";

import { useState } from "react";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { requestCode, verifyCode } from "./actions";

export function SignInForm() {
  const [email, setEmail] = useState<string | null>(null);

  if (!email)
    return (
      // Keyed per step: without it React reuses the same <input> for the code and the email stays in it.
      <ActionForm key="email-step" action={requestCode} reset={false} showMessage={false} submit="Email me a code" submitClass="dash-btn dash-btn--primary dash-btn--block" onDone={(s) => setEmail((s?.data as { email: string }).email)}>
        <p className="dash-muted">We will email you a six-digit code. No password needed.</p>
        <div className="dash-field">
          <label htmlFor="email">Work email</label>
          <input id="email" name="email" type="email" className="dash-input" autoComplete="email" inputMode="email" required autoFocus />
        </div>
      </ActionForm>
    );

  return (
    <>
    <ActionForm key="code-step" action={verifyCode} reset={false} showMessage={false} submit="Sign in" submitClass="dash-btn dash-btn--primary dash-btn--block" hidden={{ email }}>
      <p className="dash-muted">
        If <strong>{email}</strong> is registered with an estate, a code is on its way. It works for 10 minutes.
      </p>
      <div className="dash-field">
        <label htmlFor="code">Six-digit code</label>
        <input
          id="code"
          name="code"
          className="dash-input dash-input--code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9 ]{6,7}"
          maxLength={7}
          defaultValue=""
          required
          autoFocus
        />
      </div>
    </ActionForm>
    <button type="button" className="dash-link-btn" onClick={() => setEmail(null)}>
      Use a different email or send a new code
    </button>
    </>
  );
}
