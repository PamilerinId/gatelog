# Gatelog Gate (guard app)

Flutter, Android only. Runs on the gate phone. A guard or the CSO starts a shift with their PIN
and a selfie. The guard view verifies six-digit codes, logs entries and exits (with optional
plates) and runs the No code callback flow, all with no network. The CSO view adds what needs the
CSO, who is on duty, people and shifts. Everything recorded goes into a local queue and syncs when
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

The drift tables (`lib/data/db.dart`, schema version 3: guard roles, PIN hashes and consent, vehicles, selfies; then home PIN hashes and the rider's position queue) generate `db.g.dart`, which is checked in. After changing a table:

```
dart run build_runner build --force-jit
```

`--force-jit` is needed: `package:sqlite3` 3.x uses build hooks, and build_runner's default AOT
compile refuses packages with hooks.

## What it does

One app for the guard and the CSO. Whoever opens the shift decides the view: role `guard` gets
the guard view, role `cso` the CSO view. Behaviour follows `docs/guard-app-contract.md` and the
spec's "The gate phone: guard and CSO".

| Screen | |
|---|---|
| Pairing | 8-character code, `POST /v1/device/pair`, token to secure storage. |
| Start your shift | Tap your name (`guards[]`). No consent recorded: "Ask the estate admin to record your consent form first." No PIN yet (first shift, or reset by the admin): choose 6 digits, twice; only the hash is queued, as a `pins` record. Otherwise enter the PIN, checked offline against `pin_hash` (a PIN set on this phone and not yet synced wins). Five wrong tries lock that person out on this phone for 5 minutes. Then one front-camera photo; if the camera fails the shift starts with `selfie_taken: false`. |
| Guard view | The keypad is the screen, with two dock buttons, **No code** and **Leaving**, and a menu (Emergency numbers, Sync, End my shift). Six digits check at once, offline: **Code OK** (Let them in, Turn away), **Code OK: call first** for homes that want a callback, **Code not valid now**, **Already inside** (They are leaving), **No match**. What was just recorded shows above the keypad for 8 seconds with Undo, so no toast covers the dock. |
| No code | Find the home by house number or surname. Its **Already confirmed** guests have Let in. Each resident has **Call** (native dialler; only the last 4 digits are ever on screen). After the call: Confirmed / Said no / No answer (a `callbacks` record). Confirmed asks the guest's name, then **They are here: let them in** (`callback_confirmed`, no visit) or **Coming later: expect them** (stay, then a `visits` record linked from the callback). Said no, or no answer twice: **Do not let them in on the phone**, the estate's walk-in rule, **Turn away** (with a reason) or **CSO decided: let them in** (`walk_in_admitted`; pick the CSO from `role: cso`; reason required). |
| Leaving | Everyone inside, by home. Tap the person (`list_tap`), or type their code on the keypad. "Someone not on the list" records the name only. |
| Plates | On every Let them in and on Leaving: an optional **Vehicle plate**, collapsed until tapped. "Registered to this home" when it matches the home's `vehicles` (upper case; spaces, dashes and dots stripped). Sent as typed; the server normalises. |
| End my shift | "Who is taking over?" (everyone with consent but you) or **Nobody**. Queues the shift's end with `handover: {inside, unsynced, night_list_open}` and returns to Start your shift. A shift ends by itself after 14 hours (`end_reason: auto`), checked every minute, on resume and at start-up. |
| CSO view | Tabs **Gate** (the guard view's keypad and dock), **Now**, **People**, **Shifts**, **Numbers**. |
| Now | `GET /v1/device/cso` with `X-Shift-Id`, when it opens and every minute while it shows. "Updated hh:mm"; with no network, the last copy (kept in the database) and a note. **Needs you**: past their time (Call the resident, Mark left = exit `list_tap`), the night list from `/state` (Left / Still inside), gate phones not syncing, walk-ins today, turned away today. **On duty** per gate. |
| People | **Add a guest** (the same find-home, call and expect-later flow), then Expected / Inside (from `/state`, so offline) / Turned away (from the CSO endpoint). |
| Shifts | `shifts_today`: who, gate, from and to, how it ended, the handover counts, whether a photo is on file (never the photo). |
| Numbers / Emergency numbers | The directory from the cache, grouped, tap to call; "Didn't work" queues `POST /v1/device/directory/report`. |
| Sync (the chip, or the menu) | Last sync, queued count, push on or off, Sync now, and **Needs attention**: records the server rejected, with the reason. |

Every record carries `shift_id` and `guard_id` of the open shift: entries, exits, callbacks,
visits and rollup checks. Nothing can be recorded without an open shift. (The server's `visits`
and `rollup_checks` models do not have these fields yet and ignore them.)

Stays: about an hour = 60 min, a few hours = 180 min, overnight = 10:00 next day, a date = 18:00
that day, all in the estate's timezone (`Africa/Lagos`, via the `timezone` package).

## The estate shuttle (only where `/state.shuttle` is not null)

The contract's "The estate shuttle". Everything here is hidden when the estate runs no shuttle.
The new screens follow the handoff design (`docs/gatelog-handoff/design`, `lib/ui/kit.dart`):
one job per screen, Yes or No instead of lists, no typing, every result read aloud
(`flutter_tts`, English), charcoal with a fabric twill from 19:00 to 06:59 estate time and white
by day, Inter for words and JetBrains Mono for data (both bundled in `assets/fonts`, SIL OFL).
The older guard and CSO screens keep their look until their redesign is approved.

| Screen | |
|---|---|
| Rider shift start | On Start your shift, **Shuttle rider** opens: tap your face (riders only), the 6-digit PIN keypad (as for guards: set twice, 5 tries then 5 minutes), then the motorcycle as big tiles (`shuttle_id` on the shift record). The photo is taken when the motorcycle is tapped (the camera warms up on that screen and is never shown). |
| Rider view | One ride at a time. Waiting: the ride (kind, FROM, TO, how long it has waited, who or what, the note, "1 OF 3") and **Take it?** Yes / No. No shows the next one; "See them again" after the last. Taken: **Tap their card** (NFC, listening while it shows) or **No card** (home PIN), plus Hand back and Nobody came. Under way: **Did they arrive?** Yes / No. A parcel: **Got the parcel?** at the gate, and who took it (card or home PIN) at drop-off. "Taken by Ade" when the sync rejects a Take it: said aloud, shown, the ride gone. **New ride** (flagged down): card or home PIN or "Do you know them?", then "Picking up at ...?" and "Going to ...?" Yes / No. `/state` every 15 s while it shows. |
| Who rode | Card: hash the UID (`lib/core/card.dart`), look it up in `shuttle.cards`, "Card is Mrs Adeyemi, 14B. Is this them?". No card: the home PIN keypad (4 digits, PBKDF2 like a guard PIN, offline, in an isolate); 3 wrong tries on one home: "Ask them to call the gate", with the card or vouching offered; every check is a `pin_checks` record (`context: shuttle`). No PIN: "Did the guard send them?" (gate bookings) and "Do you know them?". |
| Home picker | No typing: the street, then the house numbers as tiles (one street goes straight to the numbers). |
| Shuttle to the home (guard menu; and on No code after a guest is let in) | The house, then Parcel or Guest, then "Book the shuttle?". `source: gate`, pickup the phone's gate. No typing: a parcel has no description; a guest let in on No code keeps the name already given. |
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
- Walk-ins: the server makes no visit for a `walk_in_admitted` entry, so `/state` never lists
  the guest as inside. The phone keeps an acknowledged walk-in entry until an acknowledged exit
  closes it, or 24 hours, so the guest stays in Leaving on this phone. Other gates do not see
  them (see Known gaps).

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

## What is stored where

| Where | What |
|---|---|
| `flutter_secure_storage` (Android Keystore) | Device token, HMAC keys (`keys[]` from state), the database key (32 random bytes made on first launch). |
| SQLite via drift, encrypted with SQLCipher | The last state: homes, residents, full phone numbers, vehicles, visits, gates, guards with their PIN hashes, directory, plus estate, device and rollup as JSON in `meta`. The outbox. Selfies waiting to upload. The ETag, last sync time, the open shift, PIN lockouts and the last CSO overview. |

SQLCipher comes from `package:sqlite3`'s build hook (`hooks: user_defines: sqlite3: source:
sqlcipher` in `pubspec.yaml`); the APK ships `libsqlcipher.so`. The database opens with
`PRAGMA key` first and then checks `PRAGMA cipher_version`; if that is empty (a plain SQLite
build) the app refuses to open the database rather than write numbers unencrypted. If the key
is lost (Keystore reset), the unreadable file is deleted and the phone has to be paired again.
Backups are off (`android:allowBackup="false"`).

Never logged: phone numbers, keys, PINs, PIN hashes, home PINs, card UIDs, positions, selfies, the token. `PhoneNumber.toString()`
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
- `test/no_code_test.dart`: the flow's outcomes (confirmed, said no, no answer twice) and the records for in now, later and turned away; walk-ins needing a decider and a reason; plate matching.
- `test/codes_test.dart`: every vector in `docs/code-test-vectors.json` (message and code).
- `test/verify_test.dart`: window edges, early and late, key versions, missing keys, uncoded visits, exit matches.
- `test/outbox_test.dart`: accepted and duplicates leave the queue, rejected parked, network failure retried, 422 split, directory reports, 401, purge after a pull, pins and shifts first, one answer for a shift's start and end, walk-ins kept until exited.
- `test/controller_test.dart`: offline admit and exit with plates, queue drain, the server-visit dedupe for callback entries, expect later, Undo, 401 wipe (selfies too), night list, nothing recorded without a shift.
- `test/estate_time_test.dart`: windows and stays in Lagos time.
- `test/shuttle_test.dart`: the card hash vector (`118658b9...`), the home PIN (offline, 3 tries, lockout across restarts, `pin_checks` records), rides laid over the state (take, hand back, card pickup, parcel at drop-off, no-show, flag-down in one batch, "taken by"), gate, dispatch and card bookings, positions (only in a rider shift, 15 s, 2 hours, batches of 200, 409 and 403, sent before the shift end, refused location).
- `test/rider_widget_test.dart`: the rider at 360dp and 320dp (face, PIN, motorcycle, one ride at a time, taken by, card, arrived, flag-down with the home PIN, end), day and night tokens, the guard's Shuttle to the home, the CSO's Shuttle tab, Book a ride and Issue a card.
- `test/widget_test.dart`: name, consent block, wrong then right PIN, no camera, keypad, plate match, Let them in, Leaving, menu, end shift with handover (at 360dp and 320dp); No code confirmed and let in; said no and the CSO's walk-in decision; a CSO setting a PIN and landing on Now, People and Shifts.

### Integration check (optional)

`test/integration/api_integration_test.dart` runs against a live API and skips unless
`GATELOG_IT_*` is set. It pairs, sets a PIN with the real 60,000-iteration hash (and
checks the server stored it), opens a shift with a selfie and checks the upload, checks that the
app's offline code equals the server's, admits with a plate (checked in the admin entry log),
exits, runs the No code outcomes including a CSO walk-in decision, hands over to the CSO, opens
the CSO's shift and reads the CSO overview, retries a batch (duplicates), then the shuttle: the
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
- **Not built (Phase 2):** SOS alarm, full-screen lock-screen alert, caller ID screening, IVR, iOS.
- **Walk-ins are invisible to other gates.** The API makes a visit for a `callback_confirmed`
  entry with no visit, but not for `walk_in_admitted`, so `/state` never lists a walk-in as
  inside. This phone keeps them in Leaving (up to 24 hours); other gates and the CSO's People tab
  do not see them, and the night list cannot include them. Fix on the server: make a visit for
  walk-ins as for callback entries.
- **`shift_id` on visits and rollup checks** is sent but the API's `VisitIn` and `RollupCheckIn`
  do not have the field yet, so it is dropped.
- **The approved mocks** (`Guard.dc.html`, `Cso.dc.html`) were not available when this was built;
  the screens follow the contract, the spec and the written brief. Check them against the mocks.
- **A confirmed call is recorded only with the choice** (in now, or expect later), so the later
  visit can be linked from the callback. Leaving the screen first asks for confirmation.
- **Run on the Pixel 9a emulator** against a local API (pair, PIN, selfie with the emulated
  camera, code with plate, No code, turn away, handover, the CSO's Now, People and Shifts). Not
  yet on a real gate phone.
