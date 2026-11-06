# Mobile app ↔ backend: integration status (v2.4)

Source of truth: `MOBILE_BACKEND_API_AND_IMAGE_STORAGE.md` (backend, Requirements v2.3). Status of every item for the app:

| Backend contract | What the app does | State |
|---|---|---|
| JWT, `GET /api/accounts/me/` incl. `has_profile_picture` | Login, role routing, profile photo | Done |
| Site tasks, history, `GET site-tasks/?project=` | Task list, progress, history; phone-only fallback if the route is missing / 5xx | Done |
| **Presign → PUT → attach (S3)** | `EvidenceUploader`: up to 6 photos per save; headers exactly as returned; no JWT; **no redirects**; evidence entries carry per-photo AI analysis and GPS | Done |
| Photo confirmation | Looks at `photo_count`, `evidence_count`, `evidence[]`; if all are 0 shows "photos NOT stored" and keeps the photos on the phone | Done |
| **`client_uuid` idempotency** | One UUID per draft, re-sent on every retry and on offline sync; `200` replay treated as success; photos already uploaded are not uploaded twice | Done (new in v2.4) |
| Fallback `photos[]` when presign is 503 / missing | Up to 3 small copies; clear on-screen reason | Done |
| Signed URLs (60 min) | Never stored; history screens re-fetch each time | Done |
| Videos | Stay on the phone; only `media[]` metadata is sent | Done |
| Profile pictures (DB, ≤ 300 KB) | Resized 512×512 JPEG q80, `POST` base64; avatars everywhere | Done |
| 10-minute GPS pings, offline queue, late pings | Background tracking; queue uploaded oldest first | Done |
| Live locations / worker path (Super Admin) | Map tab and route screen | Done |
| Assigned-site on/off-site, 5 m | Computed in the app from `assignments` + `boundary` (works with or without the server's `GEOFENCE_ASSIGNED_SITE_ONLY`) | Done |
| `close-stale-attendance` scheduler | Server only | n/a |
| Video upload / video AI, custom task lists, weights, approvals | Not built (phase 2 / open decisions) | Open |

## First test on a phone (about 5 minutes)
1. Avatar menu → **Connection check**: every row green (especially *Photo upload links*, *Site assignments*, *Site boundary*).
2. Task → add 2 photos → **Analyse** → **Save progress**. Expect "Progress saved" with no warning; open the history entry: the photos show.
3. Switch the phone to flight mode, save another update: "Saved on this phone". Switch it back on and open Home: it uploads once (check the history has ONE new row, not two).
4. Superadmin: Overview → "Off site now" lists only engineers more than 5 m from THEIR OWN site.
If a photo message appears, `BACKEND_REQUIREMENTS.md` §18 / backend guide §3.6 explains it.
