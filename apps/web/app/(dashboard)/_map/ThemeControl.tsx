"use client";

import { useEffect, useState } from "react";
import { fmtTime } from "@/app/(dashboard)/_lib/format";
import { useEstateMap } from "./context";
import { nextSwitch, type ThemePref } from "./theme";

const OPTIONS: { value: ThemePref; label: string }[] = [
  { value: "auto", label: "Auto" },
  { value: "day", label: "Day" },
  { value: "night", label: "Night" },
];

/** Auto follows sunrise and sunset at the estate. The choice is kept on this device only. */
export function ThemeControl() {
  const { pref, setPref, theme, data, live } = useEstateMap();
  const sun = live?.sun ?? data?.sun ?? null;
  // The next switch time depends on the clock, so it is only worked out in the browser.
  const [next, setNext] = useState<number | null>(null);
  useEffect(() => setNext(nextSwitch(sun, Date.now())), [sun, theme]);

  let note: string;
  if (pref !== "auto") note = `Always ${pref} on this device until you choose Auto.`;
  else if (!sun) note = "Follows sunrise and sunset once the estate boundary is drawn.";
  else if (next) note = `${theme === "night" ? "Night" : "Day"} now. ${theme === "night" ? "Day" : "Night"} from ${fmtTime(new Date(next).toISOString())}.`;
  else note = "Follows sunrise and sunset at the estate.";

  return (
    <fieldset className="dash-theme">
      <legend className="dash-theme__legend">Day and night</legend>
      <div className="dash-seg">
        {OPTIONS.map((o) => (
          <label key={o.value} className="dash-seg__opt">
            <input type="radio" name="dash-theme" value={o.value} checked={pref === o.value} onChange={() => setPref(o.value)} />
            <span>{o.label}</span>
          </label>
        ))}
      </div>
      <p className="dash-theme__note" aria-live="polite">
        {note}
      </p>
    </fieldset>
  );
}
