// Every string on the landing page lives here.
// Claim set (do not extend without the product actually doing it):
//   residents use WhatsApp, codes are six-digit and signed per visit,
//   the guard verifies offline, entries are logged against a
//   four-level estate address.
//
// The page reads as one weekend at one gate. Stamps mark the moments:
// Friday evening at the barrier, Monday morning at the estate office.

export const site = {
  name: "Gatelog",
  tagline: "Visitor access for Nigerian estates.",
  cta: "Book a demo",
  contactEmail: "info@gatelog.ng",
  whatsapp: "0813 399 8868",
  whatsappHref: "https://wa.me/2348133998868",
  privacyHref: "#top",
  privacyLabel: "Privacy",
};

export const nav = [
  { href: "#gate", label: "Before and after" },
  { href: "#try", label: "Try it" },
  { href: "#record", label: "The record" },
];

export const hero = {
  eyebrow: "Visitor access for Nigerian estates",
  title: "Every estate has the same six minutes at the gate.",
  body:
    "One message from the resident, sent on WhatsApp. One code at the barrier, verified with the network down. One record the committee can actually read.",
  primary: "Book a demo",
  secondary: "See the difference",
  chip: {
    gate: "Main Gate",
    net: "No network",
    waiting: "Guard enters the code",
    checking: "Checking the signature on this device",
    label: "Verified on this device",
    name: "Tunde Bakare",
  },
};

export const turn = {
  text: "None of this is a discipline problem. It is a tooling problem, and it has one fix: the resident decides before the guest arrives.",
};

export const record = {
  stamp: "Monday, 09:00",
  title: "What the committee sees on Monday.",
  body:
    "One console for the Secretary and the Executive: what came through the gates, which of it was cleared in advance, and what happened when the network went down.",
  tabs: ["Overview", "Entries", "Residents", "Gates", "Reports"],
  range: "This week",
  sample: "Sample data",
  stats: [
    { label: "Entries logged", value: "412", unit: "this week", kind: "spark" as const },
    { label: "Cleared in advance", value: "87", unit: "%", kind: "bar" as const, pct: 87 },
    { label: "Verified offline", value: "64", unit: "entries", kind: "note" as const, note: "No network at the gate" },
    { label: "Codes refused", value: "9", unit: "attempts", kind: "note" as const, note: "Expired or unrecognised", warn: true },
  ],
  arrivalsTitle: "Arrivals by hour",
  arrivalsDay: "Friday",
  peak: "Evening peak",
  arrivals: [4, 7, 3, 8, 12, 15, 22, 27, 23, 14, 6, 3],
  arrivalsNote: "The evening peak is where the queue forms, and where clearing guests in advance pays for itself.",
  gatesTitle: "Gates",
  online: "Online",
  offline: "Offline",
  gates: [
    { name: "Main Gate", online: true },
    { name: "Back Gate", online: false, sync: "Last sync 18:12" },
  ],
  gatesNote: "Offline gates keep admitting. Their entries appear here when the connection returns.",
  offlinePct: 16,
  offlineWord: "offline",
  offlineNote: "One entry in six was verified with no connection. Those are the ones a cloud-only system would have turned into an argument.",
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
  title: "Watch it work at a gate like yours.",
  body: "Thirty minutes with your committee, at your own gate. We turn the network off on purpose.",
  submit: "Book a demo",
  sending: "Sending",
  success: "Thank you. We’ll message you on WhatsApp to set a time.",
  note: "We reply on WhatsApp as fast as humanly possible.",
  whatsappLabel: "WhatsApp",
  fields: {
    name: { label: "Your name", placeholder: "Full name" },
    estate: { label: "Estate name", placeholder: "Estate and city" },
    phone: { label: "WhatsApp number", placeholder: "+234" },
  },
  errors: {
    name: "Tell us your name.",
    estate: "Which estate is this for?",
    phone: "Use a Nigerian number, for example 0803 123 4567.",
    generic: "Something went wrong. Please try again.",
  },
};

export const contrast = {
  stamp: "Friday evening",
  title: "Two ways the evening goes.",
  without: "Without Gatelog",
  with: "With Gatelog",
  // What the phone mockup shows, one screen per row below. Mirrors the product screens.
  phone: {
    labels: ["Resident", "Guard", "Estate office"],
    choose: "Choose a screen",
    chat: {
      name: "Gatelog",
      status: "online",
      out: "Tunde Bakare is coming today, around 4.",
      replyLead: "Noted. Gate code ",
      replyCode: "482 917",
      replyTail: ", valid today until 6pm.",
      sent: "13:12",
      input: "Message",
    },
    guard: {
      net: "No network",
      code: "Gate code",
      digits: "482917",
      verified: "Verified on this device",
      guest: "Tunde Bakare",
      home: "Guest of 14B Adeniyi Close",
      admit: "Admit and log",
      away: "Turn away",
    },
    office: {
      title: "Entry log, Friday",
      name: "Tunde Bakare",
      time: "16:06",
      home: "14B Adeniyi Close, resident approved",
      gate: "Main Gate, verified offline",
      earlier: "Earlier today",
    },
  },
  rows: [
    {
      label: "Arrival",
      time: ["18:41", "16:04"],
      before: { title: "“Who are you here to see?”", body: "The guest gives a house number. It may be the right one. Two cars and a keke are waiting behind him, and it has started to rain." },
      after: { title: "The guest shows six digits.", body: "Tunde’s host cleared him at 13:12 with one WhatsApp message. The code was sent to Tunde, valid for today only." },
    },
    {
      label: "Checking",
      time: ["18:43", "16:05"],
      before: { title: "The guard calls the house. It rings out.", body: "The network is poor on that side of the estate, or the phone is charging somewhere inside. Now it’s the guard’s call, alone, with a queue." },
      after: { title: "Verified on the guard’s phone.", body: "The code carries its own signature, so checking it needs no call and no network. A guessed code fails. Yesterday’s code fails." },
    },
    {
      label: "Record",
      time: ["18:46", "16:06"],
      before: { title: "A name goes into the book.", body: "Written by hand, in the dark. Nobody reads that page again unless something has gone wrong, and then the handwriting is all there is." },
      after: { title: "Logged against 14B Adeniyi Close.", body: "Who came, which home, which resident approved it, which gate, what time. The resident is told on WhatsApp that Tunde is in." },
    },
  ],
};

export const realities = {
  title: "Every objection has already happened at a real gate.",
  cols: ["The objection", "What Gatelog does"],
  items: [
    { problem: "The network drops at the gate.", fix: "Codes verify on the guard’s phone, offline. Entries sync when the signal returns." },
    { problem: "Residents won’t install another app.", fix: "They don’t. The resident’s side of Gatelog is a WhatsApp chat." },
    { problem: "Codes get shared around.", fix: "Each code is signed for one visit. Reuse it tomorrow and it fails." },
    { problem: "“Block C, Phase 2, behind the filling station.”", fix: "A four-level estate address, so every entry lands on the right home." },
    { problem: "The visitors’ book answers nothing.", fix: "A searchable record the committee can export at the end of the month." },
  ],
};

export const tryIt = {
  stamp: "Friday, 16:05",
  title: "Switch the network off. It still works.",
  body: "This is the check a guard runs at the barrier. Enter the code Tunde received and see what the gate sees.",
  code: "482917",
  codeLabel: "Gate code",
  useCode: "Use Tunde’s code, 482 917",
  clear: "Clear",
  network: "Network",
  on: "On",
  off: "Off",
  idleOnline: "Enter the six digits the guest shows you.",
  idleOffline: "The network is off. Enter the code anyway.",
  verified: "Verified on this device",
  guestLine: "Tunde Bakare, guest of 14B Adeniyi Close.",
  noNetwork: "No network used.",
  refused: "Code not recognised",
  refusedBody: "Expired, used, or never issued. Turn the guest away or call the resident.",
  note: "A demo running in your browser. No data leaves this page.",
};

export const sticky = {
  tryLabel: "Try the code check",
};

export const footer = {
  links: [
    { href: "#try", label: "Try it" },
    { href: "#demo", label: "Book a demo" },
  ],
  credit: "Gatelog. Built by PI Technologies.",
};
