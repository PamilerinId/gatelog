# Gatelog UI prototype

These `.dc.html` files are exported from the design canvas (https://claude.ai/artifact/F9ZxBq9Ne8hp4FXkbuPixH). They are reference markup, not runnable code: each depends on the canvas runtime (`support.js`, `<x-dc>`, `{{holes}}`). Read them for layout, sizes, copy and colours, then rebuild in Next.js (dashboard) and Flutter (guard app).

| File | Screen | Target |
| --- | --- | --- |
| `Main.dc.html` | Exco dashboard: satellite map, markers, status panel, live log, legend, day/night toggle | Next.js |
| `Guard-ShiftStart.dc.html` | 1 · Start shift: tap your face, PIN keypad | Flutter |
| `Guard-Home.dc.html` | 2 · Home: three fixed jobs | Flutter |
| `Guard-Gate.dc.html` | 3 · Code is correct: house number large, Let in / No | Flutter |
| `Guard-Call.dc.html` | 4 · Phone call: callback done, say visitor's name, Did they say yes? | Flutter |
| `Guard-SOS.dc.html` | 5 · SOS: house, route map, I'm going | Flutter |

`sat_night.jpg` and `sat_day.jpg` are the sample satellite backgrounds (Esri World Imagery, a sample Ibadan neighbourhood; prototype use only). In `Main.dc.html` they appear as `/_blob/9d5a…` (night) and `/_blob/1a80…` (day).

## Tokens

Charcoal black and sterile white only. Colour is reserved for markers and states.

| Token | Night | Day |
| --- | --- | --- |
| background | `#111111` (+ fabric twill on mobile) | `#F2F2F0` |
| surface | `#1C1C1C` | `#FFFFFF` |
| text | `#F4F4F2` | `#141414` |
| muted | `#A8A8A6` | `#4A4A48` |
| line | `rgba(244,244,242,0.10)` | `rgba(20,20,20,0.10)` |
| primary button | `#F4F4F2` bg, `#111111` text | `#141414` bg, `#FFFFFF` text |
| gate marker | `#F4F4F2` dot | `#141414` dot |
| guard marker | `#5AA9FF` | `#1D63C9` |
| SOS / No | `#FF5A4E` | `#D92D20` (text `#B42318`) |
| warning / offline / unverified | `#F5C542` | `#F5C542` dot, `#8A5A00` text |

Mobile fabric (night): `repeating-linear-gradient(45deg, rgba(255,255,255,0.03) 0 1px, transparent 1px 3px), repeating-linear-gradient(-45deg, rgba(0,0,0,0.35) 0 1px, transparent 1px 3px)` over `#111111`.

Type: Inter for UI, JetBrains Mono for data (codes, house numbers, times, coordinates, status labels). Radii: cards 20 to 28px, buttons 16 to 28px, chips 999px. Touch targets at least 56px on the guard app.

## SOS escalation ladder (diagram dropped from the spec export)

1. At once: gate guards by push and voice call; resident's contacts by SMS and WhatsApp.
2. No acknowledgement in 60 s: security head by voice call and SMS; estate officials by SMS; gate called again.
3. No acknowledgement in 3 min: everyone called again by voice; estate admin by SMS; repeats every 3 min.
4. Anyone acknowledges: escalation stops; the resident hears who is coming, by SMS and a call.
