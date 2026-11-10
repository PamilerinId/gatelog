import type { Metadata } from "next";
import Form from "next/form";
import Link from "next/link";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { ENTRY_METHOD, EXIT_METHOD, MEDIA_ROLES, TRUST, TZ_OFFSET, addDays, fmtDateTime, todayLagos } from "@/app/(dashboard)/_lib/format";
import type { EntryMethod, Gate, GateEntry, UnmatchedExit } from "@/app/(dashboard)/_lib/types";
import { ApiError, Badge, Empty, PageHead } from "@/app/(dashboard)/_components/ui";
import { ClipControls, PhotoButton } from "@/app/(dashboard)/_components/EntryMedia";

export const metadata: Metadata = { title: "Gate log" };

const LIMIT = 500;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const UUID_RE = /^[0-9a-f-]{36}$/i;
const TONE: Record<EntryMethod, "ok" | "info" | "plain" | "warn" | "bad"> = {
  code: "ok",
  phone_announced: "plain",
  callback_confirmed: "info",
  pin_confirmed: "info",
  walk_in_admitted: "warn",
  refused: "bad",
};

type Tab = "entries" | "walkins" | "unmatched";
type Search = { from?: string; to?: string; method?: string; gate?: string; plate?: string; tab?: string };

/** What the committee types ("lnd 123-ab") in the form the log stores ("LND123AB"). */
function cleanPlate(raw: string | undefined) {
  return (raw ?? "").replace(/[^0-9a-z]/gi, "").toUpperCase().slice(0, 16);
}

export default async function GateLogPage({ searchParams }: { searchParams: Promise<Search> }) {
  const sp = await searchParams;
  const tab: Tab = sp.tab === "unmatched" ? "unmatched" : sp.tab === "walkins" ? "walkins" : "entries";
  const today = todayLagos();
  const to = sp.to && DAY.test(sp.to) ? sp.to : today;
  const from = sp.from && DAY.test(sp.from) ? sp.from : addDays(to, -6);
  const method = tab === "entries" && sp.method && sp.method in ENTRY_METHOD ? sp.method : "";
  const gate = sp.gate && UUID_RE.test(sp.gate) ? sp.gate : "";
  const plate = cleanPlate(sp.plate);

  const base = new URLSearchParams({ since: `${from}T00:00:00${TZ_OFFSET}`, until: `${addDays(to, 1)}T00:00:00${TZ_OFFSET}`, limit: String(LIMIT) });
  if (gate) base.set("gate_id", gate);
  if (plate) base.set("plate", plate);
  const withMethod = (m: string) => {
    const q = new URLSearchParams(base);
    if (m) q.set("method", m);
    return `/v1/admin/entries?${q}`;
  };

  const [me, gates, entries, walkIns, unmatched] = await Promise.all([
    getMe(),
    load<Gate[]>("/v1/admin/gates"),
    tab === "entries" ? load<GateEntry[]>(withMethod(method)) : Promise.resolve(null),
    // The API returns both kinds of decision, newest first, in one call.
    tab === "walkins" ? load<GateEntry[]>(withMethod("walk_in_admitted,refused")) : Promise.resolve(null),
    tab === "unmatched" ? load<UnmatchedExit[]>("/v1/admin/exits/unmatched") : Promise.resolve(null),
  ]);

  // Voice clips and gate photos are personal data: the estate admin and the security head only.
  const media = MEDIA_ROLES.includes(me.role);

  // Walk-in decisions: everyone let in or turned away by the guard or CSO on duty, newest first.
  const decisionsError = walkIns && !walkIns.ok ? walkIns.error : null;
  const decisions = walkIns?.ok ? walkIns.data : null;

  return (
    <>
      <PageHead title="Gate log">Every entry recorded by the gate phones, newest first. Times are Lagos time.</PageHead>

      <nav className="dash-tabs" aria-label="Gate log views">
        <Link href="/dashboard/gate-log" aria-current={tab === "entries" ? "page" : undefined} className="dash-tab">
          Entries
        </Link>
        <Link href="/dashboard/gate-log?tab=walkins" aria-current={tab === "walkins" ? "page" : undefined} className="dash-tab">
          Walk-in decisions
        </Link>
        <Link href="/dashboard/gate-log?tab=unmatched" aria-current={tab === "unmatched" ? "page" : undefined} className="dash-tab">
          Exits with no entry
        </Link>
      </nav>

      {tab !== "unmatched" && (
        <Form action="/dashboard/gate-log" className="dash-filters">
          {tab === "walkins" && <input type="hidden" name="tab" value="walkins" />}
          <div className="dash-field">
            <label htmlFor="from">From</label>
            <input id="from" name="from" type="date" className="dash-input dash-input--sm" defaultValue={from} max={today} />
          </div>
          <div className="dash-field">
            <label htmlFor="to">To</label>
            <input id="to" name="to" type="date" className="dash-input dash-input--sm" defaultValue={to} max={today} />
          </div>
          {tab === "entries" && (
            <div className="dash-field">
              <label htmlFor="method">How they got in</label>
              <select id="method" name="method" className="dash-input dash-input--sm" defaultValue={method}>
                <option value="">Any way</option>
                {Object.entries(ENTRY_METHOD).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>
            </div>
          )}
          <div className="dash-field">
            <label htmlFor="gate">Gate</label>
            <select id="gate" name="gate" className="dash-input dash-input--sm" defaultValue={gate}>
              <option value="">All gates</option>
              {(gates.ok ? gates.data : []).map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          </div>
          <div className="dash-field">
            <label htmlFor="plate">Plate</label>
            <input
              id="plate"
              name="plate"
              type="search"
              className="dash-input dash-input--sm"
              defaultValue={plate}
              placeholder="For example, LND 123"
              maxLength={20}
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
            />
          </div>
          <button type="submit" className="dash-btn dash-btn--primary dash-btn--sm">
            Show
          </button>
        </Form>
      )}

      {tab === "entries" && entries && (
        <>
          {!entries.ok && <ApiError error={entries.error} />}
          {entries.ok && entries.data.length === 0 && (
            <Empty title={plate ? `No entries with a plate like ${plate}` : "No entries for these dates"}>Try a wider date range or clear the filters.</Empty>
          )}
          {entries.ok && entries.data.length > 0 && (
            <>
              <p className="dash-muted dash-small">
                {entries.data.length === LIMIT ? `Showing the latest ${LIMIT} entries. Narrow the dates to see the rest.` : `${entries.data.length} entries.`}
              </p>
              <div className="dash-table-wrap">
                <table className="dash-table dash-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Arrived</th>
                      <th scope="col">Guest</th>
                      <th scope="col">Visiting</th>
                      <th scope="col">Plate</th>
                      <th scope="col">How they got in</th>
                      <th scope="col">Trust</th>
                      <th scope="col">Gate and guard</th>
                      <th scope="col">Left</th>
                    </tr>
                  </thead>
                  <tbody>
                    {entries.data.map((e) => (
                      <tr key={e.id} className={e.disputed_at ? "dash-row--bad" : undefined}>
                        <td data-label="Arrived" className="tnum dash-nowrap">
                          {fmtDateTime(e.at)}
                        </td>
                        <td data-label="Guest">
                          <Guest e={e} media={media} />
                          {e.note && <span className="dash-hint">{e.note}</span>}
                        </td>
                        <td data-label="Visiting">{e.address ?? <span className="dash-muted">Unknown</span>}</td>
                        {/* Empty on phones when there is no plate, so the stacked card stays short. */}
                        <td data-label="Plate" className="dash-plate-cell">
                          {e.plate && <span className="dash-plate">{e.plate}</span>}
                        </td>
                        <td data-label="How they got in">
                          <Badge tone={TONE[e.method]}>{ENTRY_METHOD[e.method]}</Badge>
                          {(e.method === "walk_in_admitted" || e.method === "refused") && (e.decided_by || e.reason) && (
                            <span className="dash-hint">
                              {e.decided_by && `By ${e.decided_by}`}
                              {e.decided_by && e.reason && ": "}
                              {e.reason}
                            </span>
                          )}
                          {e.decided_alone && (
                            <span className="dash-hint">
                              <Badge tone="warn">Decided alone</Badge>
                            </span>
                          )}
                        </td>
                        <td data-label="Trust">
                          <Trust e={e} />
                        </td>
                        <td data-label="Gate and guard">
                          {e.gate ?? "Unknown gate"}
                          {e.guard && <span className="dash-hint">{e.guard}</span>}
                        </td>
                        <td data-label="Left">
                          {e.method === "refused" ? (
                            <span className="dash-muted">Not let in</span>
                          ) : e.exit_at ? (
                            <>
                              <span className="tnum">{fmtDateTime(e.exit_at)}</span>
                              {e.exit_method && <span className="dash-hint">{EXIT_METHOD[e.exit_method]}</span>}
                            </>
                          ) : (
                            <span className="dash-muted">No exit yet</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </>
      )}

      {tab === "walkins" && (
        <>
          <p className="dash-muted">
            When a guest has no code and no resident can be reached, the guard on duty asks the CSO, who decides. Each decision is recorded with who made
            it and the reason they gave. Gatelog never decides.
          </p>
          {decisionsError && <ApiError error={decisionsError} />}
          {decisions && decisions.length === 0 && <Empty title="No walk-in decisions for these dates">Try a wider date range or clear the filters.</Empty>}
          {decisions && decisions.length > 0 && (
            <>
              <p className="dash-muted dash-small">
                {decisions.filter((d) => d.method === "walk_in_admitted").length} let in, {decisions.filter((d) => d.method === "refused").length} turned
                away.
              </p>
              <div className="dash-table-wrap">
                <table className="dash-table dash-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">When</th>
                      <th scope="col">Guest</th>
                      <th scope="col">Visiting</th>
                      <th scope="col">Decision</th>
                      <th scope="col">Who decided</th>
                      <th scope="col">Reason given</th>
                      <th scope="col">Gate</th>
                    </tr>
                  </thead>
                  <tbody>
                    {decisions.map((e) => (
                      <tr key={e.id} className={e.method === "refused" || e.disputed_at ? "dash-row--bad" : undefined}>
                        <td data-label="When" className="tnum dash-nowrap">
                          {fmtDateTime(e.at)}
                        </td>
                        <td data-label="Guest">
                          <Guest e={e} media={media} />
                          {e.plate && <span className="dash-hint dash-plate">{e.plate}</span>}
                        </td>
                        <td data-label="Visiting">{e.address ?? <span className="dash-muted">Unknown</span>}</td>
                        <td data-label="Decision">
                          <span className="dash-badges">
                            {e.method === "refused" ? <Badge tone="bad">Refused</Badge> : <Badge tone="warn">{ENTRY_METHOD.walk_in_admitted}</Badge>}
                            {e.decided_alone && <Badge tone="warn">Decided alone</Badge>}
                            {e.disputed_at && <Badge tone="bad">Home said NO</Badge>}
                          </span>
                          {e.decided_alone && (
                            <span className="dash-hint">
                              The person who decided was also the one on the gate: no second person saw it.{e.method !== "refused" && " The home was texted."}
                            </span>
                          )}
                        </td>
                        <td data-label="Who decided">{e.decided_by ?? e.guard ?? <span className="dash-muted">Not recorded</span>}</td>
                        <td data-label="Reason given">{e.reason ?? e.note ?? <span className="dash-muted">None given</span>}</td>
                        <td data-label="Gate">{e.gate ?? "Unknown gate"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </>
      )}

      {tab === "unmatched" && unmatched && (
        <>
          <p className="dash-muted">
            Guests recorded leaving with no matching entry. Usually they came in before Gatelog was in use, or their entry was missed at the gate.
          </p>
          {!unmatched.ok && <ApiError error={unmatched.error} />}
          {unmatched.ok && unmatched.data.length === 0 && <Empty title="Nothing to check">Every recorded exit has a matching entry.</Empty>}
          {unmatched.ok && unmatched.data.length > 0 && (
            <div className="dash-table-wrap">
              <table className="dash-table dash-table--stack">
                <thead>
                  <tr>
                    <th scope="col">Left</th>
                    <th scope="col">Guest</th>
                    <th scope="col">How the exit was recorded</th>
                  </tr>
                </thead>
                <tbody>
                  {unmatched.data.map((x) => (
                    <tr key={x.id}>
                      <td data-label="Left" className="tnum dash-nowrap">
                        {fmtDateTime(x.at)}
                      </td>
                      <td data-label="Guest">{x.guest_name ?? <span className="dash-muted">No name recorded</span>}</td>
                      <td data-label="Recorded by">{EXIT_METHOD[x.method]}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </>
  );
}

/** The guest's name, or the voice clip it was said into, with the gate's photos. */
function Guest({ e, media }: { e: GateEntry; media: boolean }) {
  const clip = e.name_clip_id;
  const unnamed = !!clip && e.guest_name === "Voice clip";
  return (
    <>
      {unnamed ? <span className="dash-muted">Name said into a voice clip</span> : e.guest_name}
      {clip &&
        (media ? (
          <ClipControls entryId={e.id} clipId={clip} named={!unnamed} />
        ) : unnamed ? (
          <span className="dash-hint">The estate admin or the security head can play it and type the name in.</span>
        ) : null)}
      {media && (e.visitor_photo_id || e.plate_photo_id) && (
        <span className="dash-row-actions">
          {e.visitor_photo_id && <PhotoButton photoId={e.visitor_photo_id} label="Visitor photo" alt={`Photo of ${unnamed ? "the visitor" : e.guest_name} at the gate`} />}
          {e.plate_photo_id && <PhotoButton photoId={e.plate_photo_id} label="Plate photo" alt={`Plate photo for ${unnamed ? "the visitor" : e.guest_name}`} />}
        </span>
      )}
    </>
  );
}

/** How far the estate can trust the entry, who rang, and whether the home said it was not them. */
function Trust({ e }: { e: GateEntry }) {
  return (
    <>
      {e.trust ? <Badge tone={TRUST[e.trust].tone}>{TRUST[e.trust].label}</Badge> : <span className="dash-muted">Not let in</span>}
      {e.disputed_at && (
        <span className="dash-hint">
          <Badge tone="bad">Home said NO</Badge> {fmtDateTime(e.disputed_at)}
        </span>
      )}
      {e.caller && <span className="dash-hint tnum">Caller {e.caller}</span>}
    </>
  );
}
