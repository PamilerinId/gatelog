"use client";

import { useId, useRef, useState } from "react";

/** Shows one shift-start selfie in a dialog. The image comes from our own route handler,
 * which adds the staff token on the server and is served with Cache-Control: no-store. The
 * image is only requested while the dialog is open, and nothing is kept in the browser. */
export function SelfieButton({ shiftId, who, when }: { shiftId: string; who: string; when: string }) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [open, setOpen] = useState(false);
  const [failed, setFailed] = useState(false);

  return (
    <>
      <button
        type="button"
        className="dash-btn dash-btn--quiet dash-btn--sm"
        onClick={() => {
          setFailed(false);
          setOpen(true);
          ref.current?.showModal();
        }}
      >
        View selfie
      </button>
      <dialog ref={ref} className="dash-dialog" aria-labelledby={titleId} onClose={() => setOpen(false)}>
        <h2 className="dash-dialog__title" id={titleId}>
          {who}, shift started {when}
        </h2>
        <div className="dash-dialog__body">
          <p className="dash-small dash-muted">This viewing is recorded in the audit log.</p>
          {open &&
            (failed ? (
              <p className="dash-msg dash-msg--error" role="alert">
                The selfie could not be shown. It may have been deleted after 30 days, or not uploaded from the gate phone yet.
              </p>
            ) : (
              // A plain img on purpose: next/image would cache it on the server.
              // eslint-disable-next-line @next/next/no-img-element
              <img
                className="dash-selfie"
                src={`/dashboard/gate/shifts/${shiftId}/selfie`}
                alt={`Selfie taken by ${who} at the start of the shift`}
                referrerPolicy="no-referrer"
                onError={() => setFailed(true)}
              />
            ))}
        </div>
        <div className="dash-dialog__actions">
          <button type="button" className="dash-btn dash-btn--primary" onClick={() => ref.current?.close()}>
            Close
          </button>
        </div>
      </dialog>
    </>
  );
}
