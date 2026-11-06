# CMS Site Manager AI (Flutter)

Role-based mobile app for the Civil Works Site Monitoring backend. The interface is chosen from
`highest_role` in `GET /api/accounts/me/`.

| Role | Experience |
|---|---|
| `SITE_ENGINEER` | **Home**: live clock + weather, check-in/out, overall progress, 15 site tasks · **Tasks** · **History**. Per task: add photos/videos → AI estimates progress → edit → save |
| `TEAM_LEAD` | Overview · Attendance (today + history) · Progress (task progress + every update) |
| `PROJECT_MANAGER` | Same + Projects |
| `SUPER_ADMIN` | Same + **Data** (everything in the database) |

## Construction background
The login and loading screens show a construction-site picture (crane, excavator, workers, piles and solar panel rows): a sunrise version for the Light theme and a dusk version for Regular and Dark (`assets/images/construction_day.jpg`, `construction_dusk.jpg`). They are original illustrations made for this app. To use a real photo, replace those two files (same names, portrait, about 1080 x 2400) and keep to a photo you have the right to use. A fade of the page colour keeps the text readable. The loading animation (S-shaped route through the 12 milestones) plays on top of it.

## AI analysis (no key in the app)
The AI estimate runs through the backend: `POST {BASE_URL}/api/accounts/ai/generate/` with the user's normal login token and a **90 second** timeout.
The Gemini key lives only in the backend's environment (Vercel `GEMINI_API_KEY`), so there is nothing to set before building and nothing to find in the APK.
Limits are enforced by the server (30 requests per hour and 200 per day per user, about 4 MB, 14 parts). The app shows clear messages for login expired, limit reached, too large, too slow and no network.

## What's new in v3.0 (clean white UI + Theme tab)
- **New design from the "clean white UI" reference** (looks only; no features copied): white daylight canvas, slate text, solar-amber accent, emerald for good, hairline-bordered cards with soft shadows, rounded 16 px cards, small rounded status tags, segmented controls, a calmer bottom bar with a rounded highlight, 48 px+ tap targets, **Plus Jakarta Sans** text and **JetBrains Mono** numbers (fonts bundled in `assets/fonts`, SIL OFL).
- **Theme tab** (Site Engineer bottom bar, and *avatar menu -> Theme* for every role): **Light** (the clean white design, default), **Regular** (the original navy + orange colours) and **Dark** (neutral charcoal). Applied immediately, remembered on the phone, no restart and the current screen is kept.
- **Scan results are calmer:** after a camera scan the *Review and edit* card comes first and the assistant's notes come after it. Safety observations are now a low-key "Safety notes" card in the lower part of the notes (soft amber, small severity word, "Suggested:" action) instead of a big red banner at the top. Risk tags in scan results use warm orange / amber / green, never red.
- How the themes work (for developers): `lib/theme/app_palette.dart` holds the three palettes; `AppTheme.xxx` colours are getters that read the active palette (so they can no longer be used inside `const` widgets); `ThemeController` stores the choice and the whole app is rebuilt once after a change, keeping the current screen. Tests: `flutter test test/theme_test.dart` (palettes, readable contrast in all three themes, saved choice).

## What's new in v2.4 (matches `MOBILE_BACKEND_API_AND_IMAGE_STORAGE.md`)
- **Safe retries (`client_uuid`):** every save carries a UUID that is re-sent on each retry and on offline sync; the server answers 200 "already saved" instead of adding a second history row.
- **Photo upload follows the contract exactly:** presign → `PUT` straight to S3 with the returned headers, no JWT, **no redirects** → attach. A retry does not upload the same photos again.
- **Clear photo errors:** 403 (phone clock / expired link), 301/307 (server region wrong), 503 (storage not configured), plus the "photos NOT stored" warning from v2.3.
- **Per-photo GPS** is sent with every stored photo.
- **Connection check** also tests site assignments and the site boundary (needed for the on-site / off-site rule).
- Server-side items now done by the backend team: assigned-site geofence with 5 m tolerance (opt-in), scheduler trigger for stale attendance, assignments readable by Super Admin / Team Lead / Project Manager. See `MOBILE_INTEGRATION_STATUS.md`.

## What's new in v2.2
- **New look:** "solar sunrise on midnight" colour scheme (orange brand colour, mint = good, rose = danger), cleaner cards, much larger numbers on dashboards (also fixes the KPI tile overflow).
- **Robot logo** replaces the sparkle icon wherever the assistant's analysis is shown.
- **Detailed AI report:** longer overview plus *hazards and safety issues* (each with severity, location and corrective action), "do this today" actions, PPE / housekeeping / weather, work completed / in progress / remaining and quality notes. It is saved with the update and shown to managers. Measured quantities and the editable fields are unchanged.
- **Superadmin on-site / off-site:** each engineer is measured against **their own assigned site only**; within **5 m** counts as on site; off-site engineers show their distance (Overview, Attendance, Map, Route).
- Unit tests: `flutter test` (geometry: `test/geo_utils_test.dart`, AI report parsing: `test/ai_analysis_test.dart`).

## What's new in v2.0
- **Live path tracking:** after check-in the phone saves its position every **10 minutes** (background service on Android; failed pings are kept and uploaded later). The Superadmin sees a live map and the full route of any engineer for any day (Map tab, or "View route on map" on a worker).
- **Profile pictures** are stored in the database (avatar menu -> *Change profile photo*); shown in lists, the map and the account menu.
- Map tiles use OpenStreetMap for testing; for production set a commercial tile URL: `--dart-define=MAP_TILE_URL=...`.
- Android 13+: allow notifications so the "Site tracking is on" notice is visible; on some phones disable battery optimisation for the app so tracking is not stopped.

## 1. Build

No AI key is needed. Run `flutter pub get`, then `flutter run` (or `flutter build apk --release --obfuscate --split-debug-info=build/symbols`).
The AI estimate needs the backend endpoint above to be deployed and `GEMINI_API_KEY` set in Vercel.

## 2. Backend

The site-task, photo (S3) and role features already exist in the team's backend. What the app additionally needs:
live tracking (`/api/dashboard/live-locations/`, `/api/dashboard/worker-path/`), profile pictures
(`/api/accounts/users/<id>/profile-picture/`), the late-ping guard and migration `0052_profile_picture`.
These come as a small add-on: see `BACKEND_ADDON_INSTALL.md` (and `backend_tracking_picture_addon.patch`).
**Do not use the older `backend_role_access.patch`: it is obsolete.**

The app works without these (task data is kept on the phone and uploaded later; the map falls back to existing endpoints).
Check what the server provides: avatar menu -> **Connection check**.

## How progress works

1. Engineer opens a task and adds photos / videos (stored in the phone's private storage).
2. **Analyse progress**: the AI reads the new photos and estimates the completion %, summary and findings.
3. The engineer can edit the %, summary, findings and remarks.
4. **Save progress**: the photos are uploaded straight to AWS S3 (private bucket) and a history row is written to the
   database (before → after %, AI estimate, whether it was edited, summary, findings, remarks, the S3 key of every photo
   with that photo's own AI analysis, video metadata, GPS). Videos stay on the device for now.
5. The task % / status and the project's overall % update; managers see everything under Progress.

## Run

Production server (default):
```
flutter clean
flutter pub get
flutter run
```

Your own / local backend (reference port 8009), no code change needed:
```
# Android emulator talking to the backend on this PC
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8009

# Real phone on the same Wi-Fi (use your PC's IP; Django must listen on 0.0.0.0:8009 and allow that host)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8009
```
`http://` works in debug builds only (release builds stay https-only).

After logging in, open the avatar menu → **Connection check** to see which endpoints the server provides
(login, attendance, dashboards, site tasks, photo upload links) and copy the report for your backend team.
