# Gatelog Gate (guard app)

Flutter, Android only. Runs on the gate phone. A guard or the CSO starts a shift with their PIN
and a selfie. The guard view verifies six-digit codes, logs entries and exits (with optional
plates) and runs the Phone call flow, all with no network. The CSO gets the same home with the CSO
extras one tap away: what needs the CSO, who is on duty, people and shifts. Everything recorded goes into a local queue and syncs when
there is data.

The contract with the API is `docs/guard-app-contract.md`. The endpoints are in
`apps/api/app/routers/device.py`.

## Run

```
cd apps/guard
flutter pub get
flutter run                                            # emulator, API on the host at :8000
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000   # a real phone on your LAN
flutter build apk --release --dart-define=API_BASE_URL=https://api.gatelog.ng
```

| dart-define | Default | Meaning |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8000` | API root. `10.0.2.2` is the host machine as seen from the Android emulator. |

Debug builds allow plain HTTP (`android/app/src/debug/AndroidManifest.xml`). Release builds need HTTPS.

To get a pairing code, register the phone in the dashboard (`POST /v1/admin/devices`). Codes look
like `ABCD-2345`; the app accepts any case, with or without the dash.

### Firebase (optional)

Push is optional. With no `android/app/google-services.json`, the google-services Gradle plugin is
not applied, `Firebase.initializeApp` fails at start, and the app falls back to polling
(`NoPushService`). To turn push on, put the estate's `google-services.json` in `android/app/`
(it is gitignored) and rebuild. The app sends its FCM registration token at pairing and with
`PUT /v1/device/fcm-token` when Firebase rotates it. A data message `{"type": "sync"}` triggers a
sync while the app is in the foreground. All of this sits behind `PushService` in `lib/sync/push.dart`.

### Code generation

The drift tables (`lib/data/db.dart`, schema version 4: guard roles, PIN hashes and consent, vehicles, selfies; then home PIN hashes and the rider's position queue; then the clip and photo queue) generate `db.g.dart`, which is checked in. After changing a table:

```
dart run build_runner build --force-jit
```

`--force-jit` is needed: `package:sqlite3` 3.x uses build hooks, and build_runner's default AOT
compile refuses packages with hooks.

## What it does

One app for everyone who opens a shift on the gate phone: guards, the CSO and shuttle riders.
The role decides the view after sign-in. Every screen follows the handoff design
(`docs/gatelog-handoff/design`, `lib/ui/kit.dart`, `lib/ui/parts.dart`) and the guard UX rules in
the root `CLAUDE.md`: one job per screen, big icons and big words, Yes or No instead of lists, no
typing (voice clips for names, the camera for plates), every result and question read aloud
(`flutter_tts`, English), charcoal with a fabric twill from 19:00 to 06:59 estate time and white by
day, Inter for words and JetBrains Mono for data (both bundled in `assets/fonts`, SIL OFL), touch
targets of 56 px and up. Every word shown or said is in `lib/ui/words.dart`, keyed by message id
(`M.*`), so Yoruba and Pidgin are one more table each. A PIN, a phone number, a code or a card id
is never read aloud.

| Screen | |
|---|---|
| Pairing | 8-character code, `POST /v1/device/pair`, token to secure storage. Done once by the admin, so the code is typed (the only text field outside debug builds), in the kit look: charcoal with the twill at night, light by day, the code in JetBrains Mono, Pair phone pinned at the bottom. |
| Start shift (Guard-ShiftStart) | **Tap your face**: a tile with a face placeholder for everyone in `guards[]` (CSO and RIDER marked; no consent dimmed, and "Ask the estate admin to record your consent form first." said). Then the 6-digit PIN keypad: set twice the first time or after a reset, checked offline against `pin_hash`, five wrong tries lock that person out on this phone for 5 minutes. The front camera warms up during the PIN and the selfie is taken by itself when the PIN is right, with no preview; no camera, the shift starts with `selfie_taken: false`. A rider then picks the motorcycle (the photo is taken on that tap). |
| Home (Guard-Home) | The name, the gate in mono caps, the network chip ("No network · still works" in amber when offline, "Check sync" in red when the server refused something, otherwise when it last synced; tap for Sync). The three jobs, always in the same place: **Visitor has code**, **Phone call**, **Visitor leaving** (with the INSIDE count). **Emergency numbers** below. The menu: Shuttle to the home (only with a shuttle), Sync, End shift. The CSO gets the same home plus a CSO button with a red count. |
| Visitor has code (Guard-Gate) | A big keypad for the 6 digits, checked offline. **Code is correct**: the house number huge, the street, the guest's name, "Let them in?" Yes or No. No: fixed reason tiles (wrong person, home said no, bad behaviour, would not wait, other). **Code not valid now** (opens or closed at), **Already inside** ("Leaving now?"), **Already left**, **No match**: each its own clear screen, read aloud. A home with `callback_required` goes straight to the callback. |
| After "Let them in" | The visitor's photo when the estate's rule says so (`estate.visitor_photos`: `all`, `phone_entries` (default: every entry not checked by a code), `off`): the screen says only "Photo of the visitor"; Skip asks "Why no photo?" (No camera / They refused, sent as `photo_skipped`); no camera at all goes on as `no_camera`. Then "Car?" Yes: the back camera, on-device text recognition (ML Kit, Latin, bundled, offline), "Is this the plate?" Yes or No. No retakes; Skip always there. A registered vehicle is announced ("This car is registered to 14B"). The plate photo is kept either way (`plate_photo_id`). Photos are never shown again. Then the result (Let in / Turned away / They are expected / Left), read aloud, with Undo while the record has not left the phone, Shuttle to the home after a let-in where the estate runs one, and Done (it goes home by itself after 20 seconds). |
| Phone call (Guard-Call) | If the last incoming call (within 10 minutes) came from a number registered to a home: "Is it Mrs Adeyemi, 14B?" Yes or No (a hint only). Otherwise the street, then the house tiles. A guest that home confirmed earlier: "Is this them?" (let in with the visit, keeping its trust). Then **Call back** (each registered number, only the last 4 digits shown) opens the dialler; back on the screen: "House called back" with the time, **Say the visitor's name** (a voice clip, 30 s at most), **Did they say yes?** Yes or No, and **No answer**, **Call supervisor**. Yes: "Are they here now?" Yes is a `callback_confirmed` entry; No is the stay as tiles (about an hour, a few hours, overnight, a later day), which makes a visit linked from the callback. A call from a number not on file for that home, confirmed on the callback: "Add this number for Mrs Adeyemi?" Yes sends `number_offers` with the full caller number. **They gave the home PIN** (only when the home has one): a 4-digit keypad checked offline against `house_code_hash`, 3 tries per call, every try a `pin_checks` record with `caller_masked`; right: the name, then here now (`pin_confirmed`) or later (a visit with `trust: pin_verified`). No answer twice, said no, or Call supervisor: the CSO decides. A guard picks the CSO (face tiles, those on shift first); a CSO signed in is preselected and sees "You are deciding alone. The home will get a text." Then the reason as tiles (Known to the CSO, Described the house well, Delivery or service, Other said in a clip), "Let them in?" Yes (`walk_in_admitted` with `decided_by`, `reason`, `caller_masked`, `name_clip_id`) or No (`refused`). The result says "The home will get a text". Every record from a call carries `caller_masked` when the phone saw the number. |
| Visitor leaving | Big tiles of everyone inside, by house, the house number in mono, the name or "Voice clip" with a play button while the clip is still on the phone. Tap, "Leaving now?" Yes (`list_tap`). **Has a code**: the keypad, then an exit by code. |
| End shift | "End your shift?" with what is handed over (inside, not sent, night list), then "Who is taking over?" as faces, or Nobody. Queues the shift's end with `handover` and returns to Start shift. A shift ends by itself after 14 hours (`end_reason: auto`). |
| CSO (one tap from the home) | Tabs at the bottom, kit style, with red counts: **Now** (`GET /v1/device/cso` when it opens and every minute while it shows, and every minute on the CSO's home for the count; "Updated hh:mm", the last copy with no network): **Home said NO** first, in red (`needs.disputed_today`), past their time (Call, Mark left), the night list as "Has Tunde left?" Yes or No (`rollup_checks`), shuttle rides waiting, quiet gate phones, walk-ins today (DECIDED ALONE marked), turned away today, who is on duty. **People** (Add a guest: the phone call flow; Expected and Inside from `/state`, offline). **Shifts** (today's, with handovers and whether a photo is on file, never the photo). **Numbers**. **Shuttle** where the estate runs one. |
| Emergency numbers | The directory from the cache, grouped, tap to call; "Didn't work" asks Yes or No and queues `POST /v1/device/directory/report`. |
| Sync | Last sync, queued count, Sync now, and **Needs attention**: records the server rejected, with the reason. |

Every record carries `shift_id` and `guard_id` of the open shift. Nothing can be recorded
without an open shift.

Stays: about an hour = 60 min, a few hours = 180 min, overnight = 10:00 next day, a later day =
18:00 that day, all in the estate's timezone (`Africa/Lagos`, via the `timezone` package).

### Caller ID (Android call screening)

`android/.../GateCallScreeningService.kt` is a `CallScreeningService`. The home screen asks once
per pairing for `RoleManager.ROLE_CALL_SCREENING` (Android 10+). While the app holds the role,
Android binds the service for incoming calls; it notes the number and time in memory only
(`LastCall`, gone with the process) and answers every call with an empty `CallResponse`: it never
blocks, silences, rejects or changes a call. The app reads it over the `ng.gatelog/caller`
channel (`lib/app/caller.dart`) and uses only a call from the last 10 minutes: the home hint,
`caller_masked` (`0803•••1234`: at most the first 4 and last 4 digits, the API's `CALLER_MASK`),
and the number offer. The full number is never stored, shown, spoken or logged. Refused, or
before Android 10: no hint, and everything else works the same. Android binds a screening app
that is not the dialler only for numbers not in the phone's contacts.

### Voice clips and gate photos

`lib/sync/capture.dart`: `record` (AAC in MP4, mono, 32 kbit/s, 16 kHz, about 120 KB for 30 s)
for names; `camera` for photos, shrunk in an isolate to a JPEG under 400 KB (1024 px on the long
side, so a plate stays readable); `google_mlkit_text_recognition` for the plate text, picked out
by `lib/core/plate_text.dart` (Nigerian plate shapes, common misreads mended in place, a home's
registered car first); `audioplayers` to play a clip back from memory. The files the camera and
the recorder write are deleted at once. Clips and photos wait in the encrypted database
(`media` table, schema 4) with the id of the record that names them, and go up after each sync
(`lib/sync/media.dart`): `PUT /v1/device/clips/{id}` and `PUT /v1/device/photos/{id}?kind=`;
204 deletes the local copy, a refusal deletes it too, no network keeps it. One that never got
there goes after 7 days (clips) or 30 (photos), as on the server. Undo before sending takes them
with the record.

## The estate shuttle (only where `/state.shuttle` is not null)

The contract's "The estate shuttle". Everything here is hidden when the estate runs no shuttle.
Riders start their shift on the same Start shift screen as everyone (tap your face, PIN, then
the motorcycle).

| Screen | |
|---|---|
| Rider shift start | On Start shift: tap your face (marked RIDER), the 6-digit PIN keypad (as for guards: set twice, 5 tries then 5 minutes), then the motorcycle as big tiles (`shuttle_id` on the shift record). The photo is taken when the motorcycle is tapped (the camera warms up during the PIN and is never shown). |
| Rider view | One ride at a time. Waiting: the ride (kind, FROM, TO, how long it has waited, who or what, the note, "1 OF 3") and **Take it?** Yes / No. No shows the next one; "See them again" after the last. Taken: **Tap their card** (NFC, listening while it shows) or **No card** (home PIN), plus Hand back and Nobody came. Under way: **Did they arrive?** Yes / No. A parcel: **Got the parcel?** at the gate, and who took it (card or home PIN) at drop-off. "Taken by Ade" when the sync rejects a Take it: said aloud, shown, the ride gone. **New ride** (flagged down): card or home PIN or "Do you know them?", then "Picking up at ...?" and "Going to ...?" Yes / No. `/state` every 15 s while it shows. |
| Who rode | Card: hash the UID (`lib/core/card.dart`), look it up in `shuttle.cards`, "Card is Mrs Adeyemi, 14B. Is this them?". No card: the home PIN keypad (4 digits, PBKDF2 like a guard PIN, offline, in an isolate); 3 wrong tries on one home: "Ask them to call the gate", with the card or vouching offered; every check is a `pin_checks` record (`context: shuttle`). No PIN: "Did the guard send them?" (gate bookings) and "Do you know them?". |
| Home picker | No typing: the street, then the house numbers as tiles (one street goes straight to the numbers). |
| Shuttle to the home (guard menu; and on the "Let in" result) | The house (from the menu), then Parcel or Guest, then "Book the shuttle?". `source: gate`, pickup the phone's gate. No typing: a parcel has no description; a guest just let in keeps the name already given. |
| CSO: Shuttle tab, and Now | Book a ride and Issue a card, rides waiting over 10 minutes (`needs.rides_waiting`, also on Now), open rides with their rider. Book a ride: the house, "Did Mrs Adeyemi ring?", from, to, when (Now / 30 min / 1 h / 2 h), "Book this ride?" (`source: dispatch`). Issue a card: tap the new card, the house, "Give the card to Mrs Adeyemi?", then the server's answer (a card already someone's comes back rejected with whose it is). |

- **Positions** (`lib/app/positions.dart`, `lib/sync/location.dart`): only during an open rider
  shift, from geolocator's position stream with its Android foreground service and notification
  ("Shuttle shift"), every 15 s (faster fixes are skipped). Points wait in the encrypted database
  (2 hours at most), go to `POST /v1/device/positions` oldest first in batches of 200, and stop
  the moment the shift ends. A sync with points queued sends them after the shift's start and
  before its end, so none is refused as "shift closed". 409 while the shift start is still queued
  keeps them; 403, or 409 for a closed shift, drops them. Location is asked for at the first rider
  shift (fine location; notifications on Android 13+); "Location not allowed" shows with Turn on.
- **NFC** (`lib/sync/card_reader.dart`, `nfc_manager` 4): the tag id as upper-case hex, hashed at
  once, never stored, shown or logged (only its last 4 hex digits, as the server keeps them). The
  emulator has no NFC: debug builds only (`kDebugMode`) show "Test build only: type a card UID".
- Android: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_LOCATION` (Android 14), `POST_NOTIFICATIONS`, `WAKE_LOCK`, `NFC` (not
  required), and the TTS service query. `MainActivity` has a small channel to ask for
  notifications.

## Shifts, PINs and selfies

- `lib/core/pin.dart`: PBKDF2-HMAC-SHA256, 60,000 iterations, 16-byte salt, 32-byte hash, stored
  as `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>`. Written out (precomputed HMAC pad
  states, two SHA-256 compressions per iteration) rather than built on `package:crypto`'s `Hmac`,
  which allocates per call. Hashing and checking run in an isolate (`compute`).
  `test/pin_test.dart` checks every vector in `docs/pin-hash-vectors.json` and cross-checks
  against `package:crypto`.
- Wrong-PIN counts and lockouts are per person per phone, kept in the encrypted database
  (`meta.pin_tries`), and survive a restart.
- The selfie: `camera`, front lens, `ResolutionPreset.medium`, then `lib/core/selfie_image.dart`
  (in an isolate) applies orientation, scales to 640 px on the long side and encodes a JPEG
  under 400 KB. The full-size file the camera writes to the app cache is deleted at once. The
  JPEG is kept in the SQLCipher database (`selfies` table), so it is encrypted with the same key
  as everything else. `lib/sync/selfies.dart` uploads it after each sync once the shift's record
  has left the queue: 204 deletes it, 404 keeps it for after the next sync, 413 or 415 or a
  rejected shift delete it, and one never uploaded goes after 30 days. Selfies are never shown.
- A shift's end is queued as a second item (`<shift id>:end`) carrying the same `id`. Outbox
  answers are matched on the server id (`id`, or `guard_id` for pins, `item_id` for rollup
  checks), so one answer settles both.
- Entries with no visit (`callback_confirmed`, `pin_confirmed`, `walk_in_admitted`): the server
  makes a visit for each, which comes back in `/state` with the phone's entry id, so every gate,
  the CSO's People tab and the night list see the guest inside.

## Sync

`lib/app/controller.dart` and `lib/sync/outbox.dart`.

- Pull `GET /v1/device/state` with `If-None-Match` on launch, every 2 minutes while in the
  foreground, when the app returns to the foreground, when connectivity returns
  (`connectivity_plus`), on an FCM `{"type":"sync"}`, and after every record.
- Each sync pushes the outbox first (`POST /v1/device/sync`, up to 100 records a batch), then pulls.
- `accepted` and `duplicates` are marked sent and never pushed again. `rejected` items are parked
  and shown under Needs attention. A network failure leaves everything queued. If the whole batch
  is refused (422), it is split in halves until the bad record is isolated, so one bad record
  cannot block the queue.
- Sent records are deleted after a state pull that started after the server acknowledged them.
  Until then they stay laid over the pulled state, so a guest admitted offline shows as inside at
  once and stays there through the gap between push and pull.
- 401 on any call wipes the database, the token and the keys, and shows pairing.
- **Who is on shift** comes from `/state`'s `on_duty` (`{guard_id, gate_id, since}` for every open
  shift in the estate), kept with the rest of the state for offline use and matched to `guards[]`
  by id. A server that leaves it out means nobody listed. A listed shift older than 14 hours does
  not count (it has ended by itself); this phone's own open shift counts before it syncs. It puts
  the CSOs on shift first, tagged ON SHIFT, when a guard picks who decided a walk-in.

## What is stored where

| Where | What |
|---|---|
| Memory only | The last incoming call's number (caller ID), on the Android side and in Dart while a call flow is open. |
| `flutter_secure_storage` (Android Keystore) | Device token, HMAC keys (`keys[]` from state), the database key (32 random bytes made on first launch). |
| SQLite via drift, encrypted with SQLCipher | The last state: homes, residents, full phone numbers, vehicles, visits, gates, guards with their PIN hashes, directory, plus estate, device, rollup, shuttle and `on_duty` as JSON in `meta`. The outbox (with `number_offers`, the only record holding a full number). Selfies, voice clips and visitor and plate photos waiting to upload. The ETag, last sync time, the open shift, PIN lockouts and the last CSO overview. |

SQLCipher comes from `package:sqlite3`'s build hook (`hooks: user_defines: sqlite3: source:
sqlcipher` in `pubspec.yaml`); the APK ships `libsqlcipher.so`. The database opens with
`PRAGMA key` first and then checks `PRAGMA cipher_version`; if that is empty (a plain SQLite
build) the app refuses to open the database rather than write numbers unencrypted. If the key
is lost (Keystore reset), the unreadable file is deleted and the phone has to be paired again.
Backups are off (`android:allowBackup="false"`).

Never logged: phone numbers, keys, PINs, PIN hashes, home PINs, card UIDs, positions, selfies, clips, photos, the token. `PhoneNumber.toString()`
is masked and `Guard.toString()` leaves out the hash. Full numbers
appear only in the `tel:` URI for a callback.

## Tests

```
flutter analyze
flutter test
```

- `test/pin_test.dart`: every vector in `docs/pin-hash-vectors.json`, a cross-check against `package:crypto`, malformed hashes, the isolate path.
- `test/shift_test.dart`: offline PIN check; the five-try lockout, its expiry, and that it survives a restart; setting a PIN; a local PIN winning until it syncs; a rejected PIN; consent; open and end records (`shift_id`, handover, the shared server id); auto-end at 14 hours (also at start-up); role decides the view; the CSO overview (shift header, offline copy); Mark left.
- `test/selfie_test.dart`: the upload queue (held while the shift is queued, 204 deletes, 404 retries after the next sync, 415 and rejected shifts drop it, 30-day cleanup) and the 640 px, under 400 KB JPEG.
- `test/call_flow_test.dart`: the Phone call flow's outcomes and records: callback yes (in now with the clip, the photos and `caller_masked`; later with the visit linked from the call), said no and no answer twice (to the CSO), the home PIN (right: `pin_confirmed` and a `pin_verified` visit; three wrong: stopped, each a `pin_checks` record with the caller), the CSO's decision (`walk_in_admitted` with who, why, caller and clip; refused; "Other" said in a clip), the CSO deciding alone, CSOs on shift first from `/state`'s `on_duty` (by guard id, kept across a restart; none from an older server; a shift over 14 hours old ignored), the number offer (only from a number not on file, after a confirmed callback), a coded guest whose home wants a call, the 10-minute caller hint and the one-time role request.
- `test/caller_test.dart`: `caller_masked` (local and international forms, short and hidden numbers, always within the server's pattern, never the full number), matching a caller to a registered home.
- `test/media_test.dart`: the clip and photo queue (kept with the record that names them, uploaded and deleted, refusals dropped, no network kept, 7 and 30 days, Undo, wiped on 401), the visitor photo rule (`all`, `phone_entries`, `off`, kept across a restart) and the skip reasons.
- `test/plate_test.dart`: picking the plate from recognized text (modern and older shapes, split lines, misreads, inside a longer line, a registered car first) and reading a plate photo with the recognizer mocked.
- `test/codes_test.dart`: every vector in `docs/code-test-vectors.json` (message and code).
- `test/verify_test.dart`: window edges, early and late, key versions, missing keys, uncoded visits, exit matches.
- `test/outbox_test.dart`: accepted and duplicates leave the queue, rejected parked, network failure retried, 422 split, directory reports, 401, purge after a pull, pins and shifts first, one answer for a shift's start and end, walk-ins kept until exited.
- `test/controller_test.dart`: offline admit and exit with plates, queue drain, the server-visit dedupe for callback entries, expect later, Undo, 401 wipe (selfies too), night list, nothing recorded without a shift.
- `test/estate_time_test.dart`: windows and stays in Lagos time.
- `test/shuttle_test.dart`: the card hash vector (`118658b9...`), the home PIN (offline, 3 tries, lockout across restarts, `pin_checks` records), rides laid over the state (take, hand back, card pickup, parcel at drop-off, no-show, flag-down in one batch, "taken by"), gate, dispatch and card bookings, positions (only in a rider shift, 15 s, 2 hours, batches of 200, 409 and 403, sent before the shift end, refused location).
- `test/rider_widget_test.dart`: the rider at 360dp and 320dp (face, PIN, motorcycle, one ride at a time, taken by, card, arrived, flag-down with the home PIN, end), day and night tokens, the guard's Shuttle to the home (menu, and after a let-in), the CSO's Shuttle tab, Book a ride and Issue a card.
- `test/widget_test.dart`, at 360dp and 320dp: shift start (consent block, wrong then right PIN, no camera), the home's three jobs in place, a code let in (house number, name, "Let them in?", "Car?", the result read aloud), no match, Leaving, End shift; the phone call (call back, the name said and played, yes, here now, photo skipped as refused, the number offer, then "Voice clip" with play in Leaving). At 320dp: the caller hint and the home PIN to a PIN-verified visit; no answer twice to the CSO's decision (the CSO tagged ON SHIFT from `on_duty`, "The home will get a text"); the CSO on the gate (same home, red count, Home said NO first in red, decided alone). Day and night on the home. Pairing in the kit look, day and night: a bad code says why, a good one pairs and goes to Start shift.

- `test/screenshots_test.dart`: skipped unless `GATELOG_SHOTS=<folder>`; walks every guard and CSO screen, then pairing, the rider and the shuttle (the CSO's tab, Book a ride, Issue a card, the gate's Shuttle to the home), day and night with the bundled fonts, and writes PNGs for design review.

### Integration check (optional)

`test/integration/api_integration_test.dart` runs against a live API and skips unless
`GATELOG_IT_*` is set. It pairs, sets a PIN with the real 60,000-iteration hash (and
checks the server stored it), opens a shift with a selfie and checks the upload, checks that the
app's offline code equals the server's, admits with a plate (checked in the admin entry log),
exits, runs the No code outcomes including a CSO walk-in decision (trust `unverified`, so the
home is texted "Not you? Reply NO", with the caller masked), then the phone call flow: a callback
confirmed from a new number with the name said and visitor and plate photos (the entry carries
`name_clip_id`, `visitor_photo_id`, `plate_photo_id`; the clip and both photos reached the server
and left the phone), the new number offered (pending on the resident until the home's YES), and
a PIN-confirmed entry on the real home PIN (`pin_verified`), hands over to the CSO, opens
the CSO's shift and reads the CSO overview, has the CSO decide a walk-in alone (`decided_alone`), retries a batch (duplicates), then the shuttle: the
CSO issues a card (and a second issue of it is refused with whose it is) and books a guest at the
gate; the rider opens a shift on S1, takes the ride, picks up with the card, drops off (checked in
`/v1/admin/rides`), checks the home PIN (the real hash, `GATELOG_IT_HOUSE_CODE`) and records a
flag-down, positions go up and `/v1/admin/live` shows the rider where the phone was, and after the
shift ends nothing more is recorded and the server answers 409; and checks that a bad token wipes
the phone. It uses its own database, `gatelog_guard_it`:

```
docker compose up -d                                   # repo root
cd apps/api
.venv/Scripts/python ../guard/tool/it_seed.py --reset  # create and migrate gatelog_guard_it
DATABASE_URL=postgresql+psycopg://gatelog_app:gatelog_app@localhost:54329/gatelog_guard_it \
DATABASE_OWNER_URL=postgresql+psycopg://gatelog_owner:gatelog_owner@localhost:54329/gatelog_guard_it \
SMS_WEBHOOK_SECRET=test-sms-secret MESSAGING_PROVIDER=console KEY_STORE=dev \
  .venv/Scripts/uvicorn app.main:app --port 8799 &
.venv/Scripts/python ../guard/tool/it_seed.py          # prints pairing_code, code, admin_token
cd ../guard
GATELOG_IT_BASE_URL=http://127.0.0.1:8799 GATELOG_IT_PAIRING_CODE=<pairing_code> GATELOG_IT_CODE=<code> \
  GATELOG_IT_ADMIN_TOKEN=<admin_token> GATELOG_IT_HOUSE_CODE=<house_code> flutter test test/integration
```

Each seed run makes a new estate. A pairing code works once.

## Known gaps and TODOs

- **No background sync.** The contract asks for a pull every 15 minutes in the background. The app
  syncs only while open, plus at once on resume. Needs `workmanager` with the database opened from
  the background isolate.
- **FCM while backgrounded.** Data messages are handled only in the foreground (`onMessage`).
  A background handler would need the same background-isolate work as above.
- **FCM token API.** `getToken` and `onTokenRefresh` are deprecated in firebase_messaging 17 in
  favour of Firebase Installation IDs, but the API sends to `message.token`, so the app still uses them.
- **Release signing** is the Flutter debug key. The application id is `ng.gatelog.gatelog_guard`.
- **Not built (Phase 2):** SOS alarm, full-screen lock-screen alert, IVR, iOS.
- **`shift_id` on visits and rollup checks** is sent but the API's `VisitIn` and `RollupCheckIn`
  do not have the field yet, so it is dropped.
- **Lines built in the controller.** Every screen's words are in `lib/ui/words.dart`, the shuttle,
  rider and pairing screens included. The controller still builds a few English lines itself: the
  Needs attention descriptions (`describe`) and the sync and CSO error messages. Move them before
  adding Yoruba or Pidgin.
- **The arrow on the keypad's go key.** The bundled Inter and JetBrains Mono have no `→` glyph, so
  the screenshot test draws it as an empty box; on a phone Android's fallback font draws it.
- **The "Other" reason clip** has no field on the entry: its id goes in `note` ("Reason clip: <id>")
  and the clip uploads like a name clip, playable by the admin by that id.
- **No exit for someone not on the list**: it needed a typed name, and exits have no clip field.
- **Run on the Pixel 9a emulator** against a local API, day and night (screenshots in the step 3
  report). Not yet on a real gate phone; caller ID needs a SIM and the role granted.
