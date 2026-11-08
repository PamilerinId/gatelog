"use client";

import { useState } from "react";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { updateMessageName } from "../actions";

/** The estate's short name, with a live preview of a message that starts with it. */
export function MessageName({ shortName, estateName }: { shortName: string | null; estateName: string }) {
  const [value, setValue] = useState(shortName ?? "");
  const sender = value.trim() || estateName;

  return (
    <ActionForm action={updateMessageName} reset={false} submit="Save message name" className="dash-form dash-settings">
      <div className="dash-field">
        <label htmlFor="short_name">Message name</label>
        <input
          id="short_name"
          name="short_name"
          className="dash-input"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          minLength={2}
          maxLength={40}
          placeholder={estateName}
          autoComplete="off"
        />
        <span className="dash-hint">
          All estates share one Gatelog WhatsApp number, so every WhatsApp and SMS message starts with this name. Keep it short, for example
          your association&rsquo;s initials. Leave it empty to use the full name, {estateName}.
        </span>
      </div>
      <p className="dash-preview" aria-live="polite">
        <span className="dash-preview__label">How a message starts</span>
        <strong>{sender}:</strong> Gate code 482 917 for Tunde, valid today until 6pm.
      </p>
    </ActionForm>
  );
}
