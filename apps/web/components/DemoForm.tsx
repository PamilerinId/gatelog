"use client";

import { useState } from "react";
import { m } from "motion/react";
import { demo } from "@/content/copy";

type Status = { kind: "idle" } | { kind: "sending" } | { kind: "ok" } | { kind: "error"; message: string };
type Field = "name" | "estate" | "phone";
type Errors = Partial<Record<Field, string>>;

function validate(data: FormData): Errors {
  const errors: Errors = {};
  const name = String(data.get("name") ?? "").trim();
  const estate = String(data.get("estate") ?? "").trim();
  const phone = String(data.get("phone") ?? "").replace(/[\s-]/g, "");
  if (name.length < 2) errors.name = demo.errors.name;
  if (estate.length < 2) errors.estate = demo.errors.estate;
  if (!/^(\+?234|0)\d{10}$/.test(phone)) errors.phone = demo.errors.phone;
  return errors;
}

export function DemoForm() {
  const [status, setStatus] = useState<Status>({ kind: "idle" });
  const [errors, setErrors] = useState<Errors>({});

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const data = new FormData(form);
    const found = validate(data);
    setErrors(found);
    if (Object.keys(found).length) return;

    setStatus({ kind: "sending" });
    try {
      const res = await fetch("/api/demo", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(Object.fromEntries(data)),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => ({}))) as { error?: string };
        throw new Error(body.error ?? demo.errors.generic);
      }
      form.reset();
      setStatus({ kind: "ok" });
    } catch (err) {
      setStatus({ kind: "error", message: err instanceof Error ? err.message : demo.errors.generic });
    }
  }

  if (status.kind === "ok") {
    return (
      <m.div className="form form--done" role="status" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
        <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="square" aria-hidden="true">
          <rect x="3" y="3" width="18" height="18" rx="1" />
          <m.path d="M7.5 12.5l3 3 6-6.5" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.4, delay: 0.2 }} />
        </svg>
        <p className="form__status form__status--ok">{demo.success}</p>
      </m.div>
    );
  }

  const field = (id: Field, props: React.InputHTMLAttributes<HTMLInputElement>) => (
    <div className="field">
      <label htmlFor={`demo-${id}`}>{demo.fields[id].label}</label>
      <input
        id={`demo-${id}`}
        name={id}
        placeholder={demo.fields[id].placeholder}
        aria-invalid={errors[id] ? true : undefined}
        aria-describedby={errors[id] ? `demo-${id}-err` : undefined}
        {...props}
      />
      {errors[id] ? (
        <span className="field__error" id={`demo-${id}-err`}>
          {errors[id]}
        </span>
      ) : null}
    </div>
  );

  return (
    <form className="form" onSubmit={onSubmit} noValidate>
      {field("name", { type: "text", autoComplete: "name" })}
      {field("estate", { type: "text", autoComplete: "organization" })}
      {field("phone", { type: "tel", autoComplete: "tel", inputMode: "tel" })}
      <div className="hp" aria-hidden="true">
        <label htmlFor="demo-website">Website</label>
        <input id="demo-website" name="website" type="text" tabIndex={-1} autoComplete="off" />
      </div>
      {status.kind === "error" ? (
        <p className="form__status form__status--err" role="alert">
          {status.message}
        </p>
      ) : null}
      <button className="btn btn--primary" type="submit" disabled={status.kind === "sending"}>
        {status.kind === "sending" ? `${demo.sending}…` : demo.submit}
      </button>
      <p className="form__note">{demo.note}</p>
    </form>
  );
}
