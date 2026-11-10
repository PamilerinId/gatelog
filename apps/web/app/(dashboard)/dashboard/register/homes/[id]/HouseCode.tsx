"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { runAction } from "@/app/(dashboard)/_components/ActionForm";
import { newHouseCode } from "../../../actions";

/** A new 4-digit home PIN, shown once. It lives only in this dialog's state and
 * is gone when the dialog closes: nothing is written to the browser's storage. */
export function HouseCodeButton({ homeId, address }: { homeId: string; address: string }) {
  const confirmRef = useRef<HTMLDialogElement>(null);
  const showRef = useRef<HTMLDialogElement>(null);
  const [code, setCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  useEffect(() => {
    if (code && !showRef.current?.open) showRef.current?.showModal();
  }, [code]);

  function make() {
    const fd = new FormData();
    fd.set("id", homeId);
    setError(null);
    start(async () => {
      const r = await runAction(newHouseCode, fd);
      if (r?.ok) {
        confirmRef.current?.close();
        setCode((r.data as { code?: string } | undefined)?.code ?? null);
      } else setError(r?.error ?? "That did not work.");
    });
  }

  return (
    <>
      <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={() => confirmRef.current?.showModal()}>
        New home PIN
      </button>
      <dialog ref={confirmRef} className="dash-dialog" aria-labelledby={`hc-title-${homeId}`}>
        <h2 className="dash-dialog__title" id={`hc-title-${homeId}`}>
          Make a new home PIN for {address}?
        </h2>
        <div className="dash-dialog__body">
          <p>The household gives it when they ring the gate about a guest, and to a shuttle rider when they have no estate card.</p>
          <ul>
            <li>The old PIN stops working when each gate phone next syncs.</li>
            <li>The new PIN is shown to you once. Gatelog does not show it again.</li>
          </ul>
        </div>
        {error && (
          <p className="dash-msg dash-msg--error" role="alert">
            {error}
          </p>
        )}
        <div className="dash-dialog__actions">
          <button type="button" className="dash-btn dash-btn--ghost" onClick={() => confirmRef.current?.close()} disabled={pending}>
            Cancel
          </button>
          <button type="button" className="dash-btn dash-btn--primary" onClick={make} disabled={pending}>
            {pending ? "Working..." : "Make a new PIN"}
          </button>
        </div>
      </dialog>
      <dialog ref={showRef} className="dash-dialog dash-dialog--plain" aria-label={`New home PIN for ${address}`} onClose={() => setCode(null)}>
        {code && (
          <div className="dash-pairing" role="status">
            <p className="dash-pairing__label">Home PIN for {address}</p>
            <p className="dash-pairing__code tnum">{code}</p>
            <p className="dash-pairing__note">
              For the resident&rsquo;s printed card: give it to the household in person or by phone. It is shown only once. A resident can also get it by
              sending HOME PIN from a registered number.
            </p>
            <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={() => showRef.current?.close()}>
              Done, hide the PIN
            </button>
          </div>
        )}
      </dialog>
    </>
  );
}
