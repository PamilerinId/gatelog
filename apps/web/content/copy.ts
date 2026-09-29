// Every string on the landing page lives here.
// Claim set (do not extend without the product actually doing it):
//   residents use WhatsApp, codes are six-digit and signed per visit,
//   the guard verifies offline, entries are logged against a
//   four-level estate address.

export const site = {
  name: "Gatelog",
  tagline: "Visitor access for Nigerian estates.",
  contactEmail: "[CONTACT EMAIL]",
  whatsapp: "[WHATSAPP NUMBER]",
  responseTime: "[RESPONSE TIME]",
  privacyHref: "#top",
  privacyLabel: "Privacy",
};

export const nav = [
  { href: "#gate", label: "The gate today" },
  { href: "#screens", label: "The three screens" },
  { href: "#record", label: "The record" },
];

export const hero = {
  eyebrow: "Visitor access for Nigerian estates",
  titleLead: "Every estate has the same six minutes",
  titleAccent: "at the gate.",
  body:
    "One message from the resident, sent on WhatsApp. One code at the barrier, verified with the network down. One record the committee can actually read.",
  primary: "Book a demo",
  secondary: "See the screens",
  chip: { label: "Verified on this device", name: "Tunde Bakare", meta: "Main Gate · 16:06 · no network" },
  facts: [
    { k: "0", v: "apps for residents to install" },
    { k: "6", v: "digits, signed for one visit" },
    { k: "Offline", v: "verification at the barrier" },
  ],
};

export const gateToday = {
  eyebrow: "The gate today",
  title: "Six minutes, six times a night.",
  beats: [
    {
      time: "18:41",
      title: "A car stops. Who are you here to see?",
      body:
        "The guest gives a house number. It may be the right one. Behind him, two more cars and a keke are waiting, and it has started to rain.",
    },
    {
      time: "18:43 · no answer",
      warn: true,
      title: "So the guard calls the house.",
      body:
        "It rings out. The network is poor on that side of the estate, or the phone is on charge somewhere inside. The decision is now the guard’s alone, in the rain, with a queue.",
    },
    {
      time: "18:46",
      title: "A name goes into the book.",
      body:
        "Written by hand, in the dark, by someone who wants the queue to move. Nobody opens that page again unless something has gone wrong, and by then the handwriting is all there is.",
      book: ["18.41   Tunde   14B", "18.44   delivery   -", "18.52   ______   ___"],
    },
  ],
};

export const turn = {
  lead: "None of this is a discipline problem. It is a",
  accent: "tooling",
  tail: "problem, and it has one fix: the resident decides before the guest arrives.",
};

export const screens = {
  eyebrow: "The product",
  title: "Three screens. One for each person at the gate.",
  body:
    "The resident never leaves WhatsApp. The guard sees one answer. The estate office gets the register. Nothing else to learn.",
  items: [
    {
      src: "/images/screen-resident.jpg",
      label: "Resident",
      body: "Announce a guest in plain words, get told when they arrive. No app, no login.",
      alt: "A phone showing the Gatelog chat on WhatsApp. The resident writes that Tunde Bakare is coming today around 4. Gatelog replies with gate code 482 917, valid until 6pm, and later confirms Tunde is in at the main gate at 16:06.",
    },
    {
      src: "/images/screen-guard.jpg",
      label: "Guard",
      body: "Type the six digits, get one answer, admit or turn away. Works with the data off.",
      alt: "A guard’s phone with no network, showing gate code 482 917 entered, a card reading verified on this device for Tunde Bakare, guest of 14B Adeniyi Close, and buttons to admit and log or turn away.",
    },
    {
      src: "/images/screen-office.jpg",
      label: "Estate office",
      body: "Every entry against the home it was for, exportable for the committee.",
      alt: "The estate entry log for Friday: Tunde Bakare at 14B Adeniyi Close at 16:06, a grocery delivery to 7 Oyelaran Street at 17:22, and a plumber for C4 Ogunlade Court at 18:40, each approved by the resident.",
    },
  ],
};

export const record = {
  eyebrow: "The record",
  title: "What the committee sees on Monday.",
  body:
    "One console for the Secretary and the Executive: what came through the gates, which of it was cleared in advance, and what happened when the network went down.",
  tabs: ["Overview", "Entries", "Residents", "Gates", "Reports"],
  stats: [
    { label: "Entries logged", value: "412", unit: "this week", kind: "spark" as const },
    { label: "Cleared in advance", value: "87", unit: "%", kind: "bar" as const, pct: 87 },
    { label: "Verified offline", value: "64", unit: "entries", kind: "note" as const, note: "No network at the gate" },
    { label: "Codes refused", value: "9", unit: "attempts", kind: "note" as const, note: "Expired or unrecognised", warn: true },
  ],
  arrivals: [4, 7, 3, 8, 12, 15, 22, 27, 23, 14, 6, 3],
  arrivalsNote: "The evening peak is where the queue forms, and where clearing guests in advance pays for itself.",
  gates: [
    { name: "Main Gate", online: true },
    { name: "Back Gate", online: false, sync: "Last sync 18:12" },
  ],
  gatesNote: "Offline gates keep admitting. Their entries appear here when the connection returns.",
  offlinePct: 16,
  offlineNote: "One entry in six was verified with no connection. Those are the ones a cloud-only system would have turned into an argument.",
  feed: [
    { name: "Tunde Bakare", home: "14B Adeniyi Close", time: "16:06" },
    { name: "Grocery delivery", home: "7 Oyelaran Street", time: "17:22" },
    { name: "Plumber, Block C", home: "C4 Ogunlade Court", time: "18:40" },
  ],
  footer: "Every entry carries the home it was for and the resident who approved it",
  export: "Export the month",
};

export const already = {
  title: "All of it runs on three things you already have.",
  items: [
    { k: "WhatsApp", v: "The resident’s side of Gatelog. No app, no login, no training session." },
    { k: "One phone at the gate", v: "The guard checks a code on one screen. No hardware to install on the barrier." },
    { k: "Six digits", v: "Short enough to read out over a bad line, and worthless to anyone else." },
  ],
};

export const demo = {
  eyebrow: "The last six minutes",
  title: "Watch it work at a gate like yours.",
  body: "Thirty minutes with your committee, at your own gate. We turn the network off on purpose.",
  submit: "Book a demo",
  success: "Thank you. We’ll message you on WhatsApp to set a time.",
};
