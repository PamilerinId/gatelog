"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import type { Device, Gate } from "@/app/(dashboard)/_lib/types";
import { ActionForm, runAction } from "@/app/(dashboard)/_components/ActionForm";
import { createDevice, newPairingCode } from "../actions";

function PairingCode({ code, label, onDone }: { code: string; label: string; onDone: () => void }) {
  return (
    <div className="dash-pairing" role="status">
      <p className="dash-pairing__label">Pairing code for {label}</p>
      <p className="dash-pairing__code tnum">{code}</p>
      <p className="dash-pairing__note">
        Enter this code in the Gatelog app on the gate phone. It works for 24 hours and is shown only once, so write it down or pair the phone now.
      </p>
      <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={onDone}>
        Done, hide the code
      </button>
    </div>
  );
}

export function RegisterDevice({ gates, gate }: { gates: Gate[]; gate?: Gate }) {
  const [shown, setShown] = useState<{ code: string; label: string } | null>(null);
  if (shown) return <PairingCode code={shown.code} label={shown.label} onDone={() => setShown(null)} />;
  if (!gate && gates.length === 0) return <p className="dash-muted">Add a gate first, then register its phone.</p>;
  return (
    <ActionForm
      action={createDevice}
      hidden={gate ? { gate_id: gate.id } : undefined}
      submit="Register phone"
      showMessage={false}
      onDone={(s) => {
        const d = s?.data as Device;
        if (d?.pairing_code) setShown({ code: d.pairing_code, label: d.label });
      }}
    >
      <div className="dash-grid2">
        <div className="dash-field">
          <label htmlFor={`dev-label-${gate?.id ?? "any"}`}>Name for this phone</label>
          <input id={`dev-label-${gate?.id ?? "any"}`} name="label" className="dash-input" placeholder="For example, Main gate phone" required maxLength={80} />
        </div>
        {!gate && <div className="dash-field">
          <label htmlFor="dev-gate">Gate</label>
          <select id="dev-gate" name="gate_id" className="dash-input" required>
            {gates.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>
        </div>}
      </div>
    </ActionForm>
  );
}

export function NewCodeButton({ device }: { device: Pick<Device, "id" | "label"> }) {
  const [code, setCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    if (code && !ref.current?.open) ref.current?.showModal();
  }, [code]);

  return (
    <>
      <dialog ref={ref} className="dash-dialog dash-dialog--plain" aria-label={`Pairing code for ${device.label}`} onClose={() => setCode(null)}>
        {code && <PairingCode code={code} label={device.label} onDone={() => ref.current?.close()} />}
      </dialog>
      <button
        type="button"
        className="dash-btn dash-btn--quiet dash-btn--sm"
        disabled={pending}
        onClick={() => {
          const fd = new FormData();
          fd.set("id", device.id);
          setError(null);
          start(async () => {
            const r = await runAction(newPairingCode, fd);
            if (r?.ok) setCode((r.data as Device).pairing_code ?? null);
            else setError(r?.error ?? "That did not work.");
          });
        }}
      >
        {pending ? "Working..." : "New pairing code"}
      </button>
      {error && (
        <span className="dash-msg dash-msg--error dash-msg--inline" role="alert">
          {error}
        </span>
      )}
    </>
  );
}
