"use client";

import { useEffect, useId, useRef, useState } from "react";
import { nameEntry } from "@/app/(dashboard)/dashboard/actions";
import { ActionForm } from "./ActionForm";

// Gate log extras for the estate admin and the security head: a visitor's name as the guard said
// it, and the gate's photos of the visitor and the plate. Every play and view is audited by the
// API. Media is fetched only when asked for, from our own no-store routes, and never kept.

/** Play a voice clip, and type the name in once it has been heard. */
export function ClipControls({ entryId, clipId, named }: { entryId: string; clipId: string; named: boolean }) {
  const [playing, setPlaying] = useState(false);
  const [failed, setFailed] = useState(false);
  const [typing, setTyping] = useState(false);
  const inputId = useId();
  const audio = useRef<HTMLAudioElement>(null);

  // The clip is fetched only now, when someone asked to hear it (each play is audited).
  useEffect(() => {
    if (playing) audio.current?.play().catch(() => undefined);
  }, [playing]);

  return (
    <span className="dash-media">
      {!playing ? (
        <button
          type="button"
          className="dash-btn dash-btn--quiet dash-btn--sm"
          onClick={() => {
            setFailed(false);
            setPlaying(true);
          }}
        >
          Play the name
        </button>
      ) : failed ? (
        <span className="dash-problem dash-problem--warn" role="alert">
          The clip could not be played. Clips are deleted after 7 days.
        </span>
      ) : (
        <audio ref={audio} className="dash-audio" controls preload="auto" src={`/dashboard/clips/${clipId}`} onError={() => setFailed(true)}>
          Your browser cannot play this clip.
        </audio>
      )}
      {!typing ? (
        <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => setTyping(true)}>
          {named ? "Correct the name" : "Type the name"}
        </button>
      ) : (
        <ActionForm
          action={nameEntry}
          hidden={{ id: entryId }}
          className="dash-inline-form"
          submit="Save name"
          submitClass="dash-btn dash-btn--primary dash-btn--sm"
          onDone={() => setTyping(false)}
        >
          <label htmlFor={inputId} className="sr-only">
            Visitor&rsquo;s name as heard on the clip
          </label>
          <input id={inputId} name="guest_name" className="dash-input dash-input--sm" required maxLength={120} autoComplete="off" placeholder="Name as heard" />
        </ActionForm>
      )}
      <span className="dash-hint">Each play is recorded in the audit log.</span>
    </span>
  );
}

/** One gate photo in a dialog, loaded only while the dialog is open. */
export function PhotoButton({ photoId, label, alt }: { photoId: string; label: string; alt: string }) {
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
        {label}
      </button>
      <dialog ref={ref} className="dash-dialog" aria-labelledby={titleId} onClose={() => setOpen(false)}>
        <h2 className="dash-dialog__title" id={titleId}>
          {alt}
        </h2>
        <div className="dash-dialog__body">
          <p className="dash-small dash-muted">This viewing is recorded in the audit log.</p>
          {open &&
            (failed ? (
              <p className="dash-msg dash-msg--error" role="alert">
                The photo could not be shown. It may not have reached the server from the gate phone yet.
              </p>
            ) : (
              // A plain img on purpose: next/image would cache it on the server.
              // eslint-disable-next-line @next/next/no-img-element
              <img className="dash-selfie" src={`/dashboard/photos/${photoId}`} alt={alt} referrerPolicy="no-referrer" onError={() => setFailed(true)} />
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
