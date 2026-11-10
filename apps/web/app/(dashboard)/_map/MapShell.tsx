"use client";

import dynamic from "next/dynamic";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Map as MapLibre } from "maplibre-gl";
import type { EstateMapData, Live } from "@/app/(dashboard)/_lib/types";
import { MapContext, type MapContextValue, type MapLib, type MapMode } from "./context";
import { IMAGERY, imageryCredit } from "./provider";
import { nextSwitch, readPref, themeAt, writePref, type Theme, type ThemePref } from "./theme";

// MapLibre only ever runs in the browser, in its own chunk.
const EstateMap = dynamic(() => import("./EstateMap"), { ssr: false });

export const EDITOR_PATH = "/dashboard/settings/map";
const POLL_MS = 10_000;

/**
 * The dashboard's background: one map for every page, created once and kept as the user moves
 * between pages. It also owns the day and night colours and, on the overview, the live data.
 */
export function MapShell({
  data,
  initialTheme,
  canSeePositions,
  admin,
  liveHome,
  children,
}: {
  data: EstateMapData | null;
  initialTheme: Theme;
  canSeePositions: boolean;
  admin: boolean;
  /** The first screen is the live map (security head, Exco); otherwise the map is a still background. */
  liveHome: boolean;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const mode: MapMode = !data
    ? "none"
    : pathname === EDITOR_PATH && admin
      ? "edit"
      : !data.bbox
        ? "none"
        : pathname === "/dashboard" && liveHome
          ? "live"
          : "still";

  // --- live data, on the overview only --------------------------------------------------------
  const [live, setLive] = useState<Live | null>(null);
  const [liveError, setLiveError] = useState<string | null>(null);
  const [liveAt, setLiveAt] = useState<number | null>(null);

  useEffect(() => {
    if (mode !== "live") return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let inFlight = false;
    const tick = async () => {
      clearTimeout(timer);
      if (stopped || inFlight) return;
      if (document.hidden) {
        timer = setTimeout(tick, POLL_MS);
        return;
      }
      inFlight = true;
      try {
        const res = await fetch("/dashboard/live", { cache: "no-store", headers: { Accept: "application/json" } });
        if (res.status === 401) {
          window.location.assign("/sign-out?expired=1");
          return;
        }
        const body = await res.json().catch(() => null);
        if (!stopped) {
          if (res.ok && body) {
            setLive(body as Live);
            setLiveError(null);
            setLiveAt(Date.now());
          } else {
            setLiveError((body as { error?: string } | null)?.error ?? "The live map could not be updated.");
          }
        }
      } catch {
        if (!stopped) setLiveError("We could not reach the Gatelog server. Trying again.");
      } finally {
        inFlight = false;
      }
      if (!stopped) timer = setTimeout(tick, POLL_MS);
    };
    tick();
    const onVisible = () => {
      if (!document.hidden) tick();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      stopped = true;
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [mode]);

  // --- day and night ------------------------------------------------------------------------------
  const [pref, setPrefState] = useState<ThemePref>("auto");
  const [theme, setTheme] = useState<Theme>(initialTheme);
  const sun = live?.sun ?? data?.sun ?? null;
  const sunKey = sun ? `${sun.sunrise}|${sun.sunset}|${sun.is_night}` : "";

  useEffect(() => setPrefState(readPref()), []);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const apply = () => {
      clearTimeout(timer);
      const now = Date.now();
      setTheme(pref === "auto" ? themeAt(sun, now) : pref);
      const next = pref === "auto" ? nextSwitch(sun, now) : null;
      // Switch on the minute the sun rises or sets, not at the next poll.
      if (next) timer = setTimeout(apply, Math.min(Math.max(next - now + 1000, 1000), 6 * 3_600_000));
    };
    apply();
    // Timers stall while a laptop sleeps: check again when the page comes back and once a minute.
    const every = setInterval(apply, 60_000);
    const onVisible = () => !document.hidden && apply();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearTimeout(timer);
      clearInterval(every);
      document.removeEventListener("visibilitychange", onVisible);
    };
    // sunKey stands for sun.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pref, sunKey]);

  const setPref = useCallback((p: ThemePref) => {
    writePref(p);
    setPrefState(p);
  }, []);

  // --- the map engine ---------------------------------------------------------------------------
  const [engine, setEngineState] = useState<{ map: MapLibre | null; lib: MapLib | null }>({ map: null, lib: null });
  const setEngine = useCallback((map: MapLibre | null, lib: MapLib | null) => setEngineState({ map, lib }), []);
  const reduced = useRef(false);
  useEffect(() => {
    reduced.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }, []);

  const [credit, setCredit] = useState<string | null>(null);
  const [logoOk, setLogoOk] = useState(true);

  const flyTo = useCallback(
    (lng: number, lat: number) => {
      const m = engine.map;
      if (!m) return;
      const zoom = Math.max(m.getZoom(), 16.5);
      if (reduced.current) m.jumpTo({ center: [lng, lat], zoom });
      else m.easeTo({ center: [lng, lat], zoom, duration: 600 });
    },
    [engine.map],
  );

  // Once the map has been needed, keep it: leaving the editor before a boundary exists hides it.
  const [mounted, setMounted] = useState(mode !== "none");
  useEffect(() => {
    if (mode !== "none") setMounted(true);
  }, [mode]);

  const value = useMemo<MapContextValue>(
    () => ({
      mode,
      data,
      live: mode === "live" ? live : null,
      liveError: mode === "live" ? liveError : null,
      liveAt: mode === "live" ? liveAt : null,
      theme,
      pref,
      setPref,
      map: engine.map,
      lib: engine.lib,
      setEngine,
      credit,
      setCredit,
      canSeePositions,
      admin,
      flyTo,
    }),
    [mode, data, live, liveError, liveAt, theme, pref, setPref, engine, setEngine, credit, canSeePositions, admin, flyTo],
  );

  return (
    <MapContext.Provider value={value}>
      <div className="dash-themed" data-theme={theme} data-map={mode}>
        {children}
        {mounted && <EstateMap />}
        {mode !== "none" && (
          <p className="dash-credit">
            {IMAGERY.logo &&
              (logoOk ? (
                // Google requires its logo with its imagery. The files come from Google's brand
                // resources (docs/map-tiles.md); the word stands in until they are added.
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  className="dash-credit__logo"
                  src={theme === "night" ? "/map/google_on_non_white.png" : "/map/google_on_white.png"}
                  alt="Google"
                  height={16}
                  onError={() => setLogoOk(false)}
                />
              ) : (
                <strong>Google</strong>
              ))}
            {imageryCredit(credit ?? undefined)}
          </p>
        )}
      </div>
    </MapContext.Provider>
  );
}
