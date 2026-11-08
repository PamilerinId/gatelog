"use client";

import { useState } from "react";
import { ActionForm, type Action } from "./ActionForm";

/** "Rename" that turns into a one-field form in place. */
export function InlineEdit({
  action,
  hidden,
  name,
  value,
  label,
  buttonLabel = "Rename",
  maxLength = 120,
}: {
  action: Action;
  hidden: Record<string, string>;
  name: string;
  value: string;
  label: string;
  buttonLabel?: string;
  maxLength?: number;
}) {
  const [open, setOpen] = useState(false);
  if (!open)
    return (
      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => setOpen(true)}>
        {buttonLabel}
      </button>
    );
  return (
    <ActionForm action={action} hidden={hidden} className="dash-inline-form" reset={false} showMessage={false} onDone={() => setOpen(false)} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
      <label className="sr-only" htmlFor={`${hidden.id}-${name}`}>
        {label}
      </label>
      <input id={`${hidden.id}-${name}`} className="dash-input dash-input--sm" name={name} defaultValue={value} required maxLength={maxLength} autoFocus />
      <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={() => setOpen(false)}>
        Cancel
      </button>
    </ActionForm>
  );
}
