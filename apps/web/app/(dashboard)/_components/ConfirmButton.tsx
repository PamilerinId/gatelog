"use client";

import { useId, useRef, useState, useTransition, type ReactNode } from "react";
import type { ActionState } from "@/app/(dashboard)/_lib/types";
import { runAction, type Action } from "./ActionForm";

/** A button that asks first, in a real dialog, then runs a Server Action. */
export function ConfirmButton({
  action,
  hidden,
  label,
  title,
  children,
  confirmLabel,
  danger = true,
  buttonClass = "dash-btn dash-btn--quiet dash-btn--sm",
}: {
  action: Action;
  hidden: Record<string, string>;
  label: ReactNode;
  title: string;
  children?: ReactNode;
  confirmLabel: string;
  danger?: boolean;
  buttonClass?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [state, setState] = useState<ActionState>(null);
  const [pending, start] = useTransition();

  function confirm() {
    const fd = new FormData();
    Object.entries(hidden).forEach(([k, v]) => fd.set(k, v));
    start(async () => {
      const r = await runAction(action, fd);
      setState(r);
      if (r?.ok) ref.current?.close();
    });
  }

  return (
    <>
      <button
        type="button"
        className={buttonClass}
        onClick={() => {
          setState(null);
          ref.current?.showModal();
        }}
      >
        {label}
      </button>
      <dialog ref={ref} className="dash-dialog" aria-labelledby={titleId}>
        <h2 className="dash-dialog__title" id={titleId}>{title}</h2>
        {children && <div className="dash-dialog__body">{children}</div>}
        {state && !state.ok && (
          <p className="dash-msg dash-msg--error" role="alert">
            {state.error}
          </p>
        )}
        <div className="dash-dialog__actions">
          <button type="button" className="dash-btn dash-btn--ghost" onClick={() => ref.current?.close()} disabled={pending}>
            Cancel
          </button>
          <button type="button" className={`dash-btn ${danger ? "dash-btn--danger" : "dash-btn--primary"}`} onClick={confirm} disabled={pending}>
            {pending ? "Working..." : confirmLabel}
          </button>
        </div>
      </dialog>
      {state?.ok && state.message && (
        <span className="dash-msg dash-msg--ok dash-msg--inline" role="status">
          {state.message}
        </span>
      )}
    </>
  );
}
