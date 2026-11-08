"use client";

import { useState, useTransition, type FormEvent, type ReactNode } from "react";
import type { ActionState } from "@/app/(dashboard)/_lib/types";

export type Action = (fd: FormData) => Promise<ActionState>;

export function runAction(action: Action, fd: FormData): Promise<ActionState> {
  return action(fd).catch((err: unknown) => {
    // redirect() from a Server Action is handled by the router; anything else is a real failure.
    if (err && typeof err === "object" && "digest" in err && String((err as { digest: unknown }).digest).startsWith("NEXT_REDIRECT")) throw err;
    return { ok: false, error: "That did not work. Reload the page and try again." };
  });
}

/** A form that calls a Server Action, shows the API's message inline, and keeps the
 * user's input when something goes wrong. */
export function ActionForm({
  action,
  children,
  submit,
  submitClass = "dash-btn dash-btn--primary",
  className = "dash-form",
  reset = true,
  showMessage = true,
  onDone,
  hidden,
}: {
  action: Action;
  children?: ReactNode;
  submit?: ReactNode;
  submitClass?: string;
  className?: string;
  reset?: boolean;
  showMessage?: boolean;
  onDone?: (s: ActionState) => void;
  hidden?: Record<string, string>;
}) {
  const [state, setState] = useState<ActionState>(null);
  const [pending, start] = useTransition();

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const fd = new FormData(form);
    start(async () => {
      const r = await runAction(action, fd);
      setState(r);
      if (r?.ok) {
        if (reset) form.reset();
        onDone?.(r);
      }
    });
  }

  return (
    <form className={className} onSubmit={onSubmit} onInput={() => state && setState(null)} aria-busy={pending}>
      {hidden && Object.entries(hidden).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
      {children}
      {submit != null && (
        <button type="submit" className={submitClass} disabled={pending}>
          {pending ? "Saving..." : submit}
        </button>
      )}
      {state && !state.ok && state.error && (
        <p className="dash-msg dash-msg--error" role="alert">
          {state.error}
        </p>
      )}
      {showMessage && state?.ok && state.message && (
        <p className="dash-msg dash-msg--ok" role="status">
          {state.message}
        </p>
      )}
    </form>
  );
}
