// Shapes returned by the Gatelog API (apps/api/app/routers). Phone numbers arrive masked.

export type Role = "admin" | "committee" | "security_head" | "treasurer" | "org_admin" | "org_viewer" | "ops";

export type Me = { id: string; name: string; email: string; role: Role; estate: { id: string; name: string } | null };

export type ActionState = { ok: boolean; error?: string; message?: string; data?: unknown } | null;

export type HomeNode = { id: string; label: string; address: string; residents: number };
export type StreetNode = { id: string; name: string; homes: HomeNode[] };
export type ZoneNode = { id: string; name: string; streets: StreetNode[] };

export type PhoneNumber = {
  id: string;
  last4: string;
  masked: string;
  is_primary: boolean;
  verified_at: string | null;
  /** Offered at the gate, waiting for the home's YES. Not usable until then. */
  pending?: boolean;
};
export type ContactPref = "whatsapp" | "sms" | "call";
export type Relation = "landlord" | "occupant";
export type Resident = {
  id: string;
  home_id: string;
  address: string;
  name: string;
  relation: Relation;
  contact_pref: ContactPref;
  callback_required: boolean;
  exit_notices: boolean;
  active: boolean;
  numbers: PhoneNumber[];
};
export type Vehicle = { id: string; plate: string; description: string | null };
export type HomeDetail = { id: string; label: string; address: string; levy_payer: Relation; residents: Resident[]; vehicles: Vehicle[] };

export type GuardRole = "guard" | "cso" | "rider";
export type Guard = {
  id: string;
  name: string;
  role: GuardRole;
  active: boolean;
  consent_at: string | null;
  pin_set: boolean;
  pin_set_at: string | null;
};

export type ShiftEnd = "handover" | "ended" | "auto";
export type SelfieState = "available" | "pending" | "none" | "deleted";
export type Shift = {
  id: string;
  guard: string | null;
  role: GuardRole | null;
  gate: string | null;
  started_at: string;
  ended_at: string | null;
  end_reason: ShiftEnd | null;
  handed_to: string | null;
  /** From the gate phone: guests still inside, records not yet synced, night list items still open. */
  handover: { inside?: number; unsynced?: number; night_list_open?: number } | null;
  selfie: SelfieState;
};
export type Gate = { id: string; name: string };
export type Device = {
  id: string;
  label: string;
  gate_id: string;
  status: "revoked" | "paired" | "awaiting pairing";
  paired_at: string | null;
  last_sync_at: string | null;
  revoked_at: string | null;
  pairing_code?: string;
};

export type DirectoryCategory = "estate" | "crime" | "fire" | "medical" | "utilities";
export type DirectoryEntry = {
  id: string;
  scope: "estate" | "state" | "lga";
  category: DirectoryCategory;
  name: string;
  number: string;
  rank: number;
  verified_at: string | null;
  verified_by: string | null;
  verification_note: string | null;
  reported_not_working: boolean;
  overdue: boolean;
  editable: boolean;
  active: boolean;
};

export type EntryMethod = "code" | "phone_announced" | "callback_confirmed" | "pin_confirmed" | "walk_in_admitted" | "refused";
/** How well an admitted entry was verified. Null for refusals. */
export type EntryTrust = "verified" | "pin_verified" | "unverified";
export type ExitMethod = "code" | "list_tap" | "resident_confirmed" | "rollup_closed";
export type GateEntry = {
  id: string;
  at: string;
  guest_name: string;
  address: string | null;
  method: EntryMethod;
  gate: string | null;
  guard: string | null;
  note: string | null;
  plate: string | null;
  /** Walk-ins and refusals: who on the gate made the call, and the reason they gave. */
  decided_by: string | null;
  reason: string | null;
  shift_id: string | null;
  exit_at: string | null;
  exit_method: ExitMethod | null;
  trust: EntryTrust | null;
  /** The number that rang the gate, masked ("0803•••1234"). */
  caller: string | null;
  /** The home replied NO to "Not you?". */
  disputed_at: string | null;
  /** The guard said the name: guest_name is "Voice clip" until someone types it in. */
  name_clip_id: string | null;
  visitor_photo_id?: string | null;
  plate_photo_id?: string | null;
  /** The CSO admitted the guest on their own decision while also working the gate. */
  decided_alone?: boolean;
};
export type UnmatchedExit = { id: string; at: string; guest_name: string | null; method: ExitMethod; visit_id: string | null };

export type Summary = {
  since: string;
  until: string;
  entries: { total: number; admitted: number; by_method: Record<EntryMethod, number> };
  entries_by_day: ({ date: string } & Record<EntryMethod, number>)[];
  entries_by_gate: { gate: string; count: number }[];
  phone_share: number | null;
  exits: {
    measurable_entries: number;
    gate_confirmed: number;
    resident_confirmed: number;
    missed: number;
    capture_rate: number | null;
    unmatched_exits: number;
  };
  overstays_by_night: { date: string; open_at_rollup: number; closed_by_morning: number | null; missed: number | null }[];
  directory: { numbers: number; overdue_verification: number; reported_not_working: number };
  trust?: {
    admitted: TrustSplit;
    phone_entries: TrustSplit;
    phone_by_gate: ({ gate: string } & TrustSplit)[];
    phone_by_guard: ({ guard: string } & TrustSplit)[];
    disputes: { entry_id: string; guest_name: string; gate: string | null; at: string; disputed_at: string }[];
  };
};
export type TrustSplit = Record<EntryTrust, number>;

export type StaffMember = { id: string; email: string; name: string; role: Role; active: boolean; phone: string | null };

export type EstateSettings = {
  default_stay_until: string;
  code_valid_until: string;
  rollup_time: string;
  handover_time: string;
  walk_in_policy: string;
  daily_sms_budget: number;
  max_visits_per_home_per_day: number;
  whatsapp_enabled: boolean;
  /** From the contract, set by Gatelog. Null when the contract has no SMS allowance. */
  sms_allowance_per_home: number | null;
  sms_overage_naira: number | null;
  /** The estate shuttle. Off unless the estate runs one. */
  shuttle_enabled: boolean;
  max_rides_per_home_per_day: number;
};
export type Estate = {
  id: string;
  name: string;
  /** Starts every WhatsApp and SMS message. Null means the full name is used. */
  short_name: string | null;
  sender_name: string;
  state: string;
  lga: string;
  timezone: string;
  settings: EstateSettings;
  role: Role;
};

export type MessagingUsage = {
  month: string;
  by_purpose: { purpose: string; whatsapp: number; sms: number; billed: boolean }[];
  sms_counted: number;
  sms_allowance: number | null;
  sms_projected: number;
  projected_overage_naira: number | null;
  allowance_used: number | null;
  note: string;
};

export type ImportRow = {
  line: number;
  zone: string;
  street: string;
  house: string;
  resident: string;
  phones: string[];
  contact_pref: ContactPref;
  callback_required: boolean;
  errors: string[];
  warnings: string[];
};
export type ImportBatch = {
  id: string;
  filename: string;
  status: "staged" | "committed" | "discarded";
  created_at: string;
  summary: { rows?: number; errors?: number; new_zones?: number; new_streets?: number; new_homes?: number; residents?: number; numbers?: number };
  result: { created: Record<"zones" | "streets" | "homes" | "residents" | "numbers", number>; skipped: { line: number; reason: string }[] } | null;
  rows: ImportRow[];
};

// --- estate map (apps/api/app/routers/estate_map.py) ------------------------------------

/** [lng, lat], GeoJSON order. */
export type LngLat = [number, number];
/** [west, south, east, north]. */
export type BBox = [number, number, number, number];
export type Sun = { sunrise: string | null; sunset: string | null; is_night: boolean };
export type PlaceKind = "amenity" | "pickup" | "post";
export type MapPlace = { id: string; name: string; kind: PlaceKind; lat: number; lng: number };
export type MapGate = { id: string; name: string; lat: number | null; lng: number | null };
export type MapHome = { id: string; address: string; lat: number; lng: number };
export type EstateMapData = {
  boundary: LngLat[] | null;
  bbox: BBox | null;
  center: { lat: number; lng: number } | null;
  sun: Sun | null;
  gates: MapGate[];
  places: MapPlace[];
  homes: MapHome[];
};

export type RideKind = "resident" | "delivery" | "guest";
export type RideSource = "whatsapp" | "sms" | "gate" | "flag" | "dispatch";
export type RideState = "requested" | "accepted" | "picked_up" | "done" | "cancelled" | "no_show";
export type RideConfirm = "card" | "house_code" | "guard" | "rider";

export type RideBrief = {
  id: string;
  kind: RideKind;
  state: RideState;
  from: string;
  to: string;
  lat: number | null;
  lng: number | null;
  wanted_at: string;
  waiting_minutes: number;
};
export type LiveGate = MapGate & {
  on_duty: { guard: string; role: GuardRole; since: string }[];
  phone_last_sync_at: string | null;
  phones: number;
  quiet: boolean;
};
export type LiveShuttle = {
  shift_id: string;
  rider: string;
  shuttle: string | null;
  since: string;
  lat: number | null;
  lng: number | null;
  heading: number | null;
  speed: number | null;
  at: string | null;
  stale: boolean;
  trail: LngLat[];
  ride: RideBrief | null;
};
export type Live = {
  server_time: string;
  bbox: BBox | null;
  sun: Sun | null;
  gates: LiveGate[];
  places: MapPlace[];
  /** Null: this role does not see rider positions. */
  shuttles: LiveShuttle[] | null;
  rides_waiting: RideBrief[];
  counts: { inside: number; overdue: number; rides_open: number; on_duty: number };
  /** Added by the dashboard's /dashboard/live route: today's entries (newest first) for the live
   * log, and today's summary. Null when that part could not be loaded. */
  log?: GateEntry[] | null;
  today?: Summary | null;
};

// --- shuttle (apps/api/app/routers/shuttle_admin.py) ------------------------------------

export type Motorcycle = { id: string; label: string; plate: string | null; active: boolean };
export type Ride = {
  id: string;
  kind: RideKind;
  source: RideSource;
  state: RideState;
  home_id: string;
  address: string | null;
  passenger: string | null;
  resident: string | null;
  from: string;
  to: string;
  wanted_at: string;
  booked_by: string | null;
  rider: string | null;
  shuttle: string | null;
  confirmed_by: RideConfirm | null;
  confirmed_resident: string | null;
  accepted_at: string | null;
  picked_up_at: string | null;
  done_at: string | null;
  closed_at: string | null;
  created_at: string;
};
export type RideEventName = "accept" | "release" | "pick_up" | "drop_off" | "cancel" | "no_show";
export type RideDetail = Ride & { events: { event: RideEventName; by: string | null; applied: boolean; at: string }[] };
export type ResidentCard = {
  id: string;
  resident_id: string;
  resident: string | null;
  home_id: string;
  uid_last4: string;
  issued_at: string;
  issued_by: string | null;
  revoked_at: string | null;
};
export type ShuttleReport = {
  month: string;
  rides: number;
  done: number;
  by_kind: Partial<Record<RideKind, number>>;
  by_source: Partial<Record<RideSource, number>>;
  by_state: Partial<Record<RideState, number>>;
  by_zone: ({ zone: string; rides: number } & Partial<Record<RideKind, number>>)[];
  by_rider: { rider: string; rides: number }[];
  homes_served: number;
  median_wait_minutes: number | null;
  confirmed_by: Partial<Record<RideConfirm | "not recorded", number>>;
};
