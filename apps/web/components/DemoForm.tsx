"use client";

import { useState } from "react";
import { m } from "motion/react";
import { demo, site } from "@/content/copy";

type Status = { kind: "idle" } | { kind: "sending" } | { kind: "ok" } | { kind: "error"; message: string };
type Errors = Partial<Record<"name" | "estate" | "phone", string>>;

function validate(data: FormData): Errors {
  const errors: Errors = {};
  const name = String(data.get("name") ?? "").trim();
  const estate = String(data.get("estate") ?? "").trim();
  const phone = String(data.get("phone") ?? "").replace(/[\s-]/g, "");
  if (name.length < 2) errors.name = "Tell us your name.";
  if (estate.length < 2) errors.estate = "Which estate is this for?";
  if (!/^(\+?234|0)\d{10}$/.test(phone)) errors.phone = "Use a Nigerian number, for example 0803 123 4567.";
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
        throw new Error(body.error ?? "Something went wrong. Please try again.");
      }
      form.reset();
      setStatus({ kind: "ok" });
    } catch (err) {
      setStatus({ kind: "error", message: err instanceof Error ? err.message : "Something went wrong." });
    }
  }

  if (status.kind === "ok") {
    return (
      <m.div className="form glass-lite form--done" role="status" initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }}>
        <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <m.circle cx="12" cy="12" r="9" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.6 }} />
          <m.path d="M8 12.5l2.8 2.8L16 9.8" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.4, delay: 0.5 }} />
        </svg>
        <p className="form__status form__status--ok">{demo.success}</p>
      </m.div>
    );
  }

  const field = (id: "name" | "estate" | "phone", label: string, props: React.InputHTMLAttributes<HTMLInputElement>) => (
    <div className="field">
      <label htmlFor={`demo-${id}`}>{label}</label>
      <input
        id={`demo-${id}`}
        name={id}
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
    <form className="form glass-lite" onSubmit={onSubmit} noValidate>
      {field("name", "Your name", { type: "text", autoComplete: "name", placeholder: "Full name" })}
      {field("estate", "Estate name", { type: "text", autoComplete: "organization", placeholder: "Estate and city" })}
      {field("phone", "WhatsApp number", { type: "tel", autoComplete: "tel", inputMode: "tel", placeholder: "+234" })}
      <div className="hp" aria-hidden="true">
        <label htmlFor="demo-website">Website</label>
        <input id="demo-website" name="website" type="text" tabIndex={-1} autoComplete="off" />
      </div>
      {status.kind === "error" ? (
        <p className="form__status form__status--err" role="alert">
          {status.message}
        </p>
      ) : null}
      <m.button className="btn btn--primary" type="submit" disabled={status.kind === "sending"} whileTap={{ scale: 0.98 }}>
        {status.kind === "sending" ? "Sending…" : demo.submit}
      </m.button>
      <p className="form__note">We reply on WhatsApp within {site.responseTime}.</p>
    </form>
  );
}
