# Backend add-on: live tracking + profile pictures + late-ping guard

**Do NOT apply the older `backend_role_access.patch`.** It was generated against an earlier snapshot of the backend and would
duplicate the site-task models/routes and collide with migrations `0050` and `0051`. It is obsolete.
This add-on is written against the **current** backend (migrations up to `0051_dailyprogressreport_approved_at_and_more`),
touches nothing that already exists except five tiny edits, and does **not** change the site-task models, `0050`, `0051`,
the S3 helpers, `site_roles.py` or the current manager-read behaviour.

## What it adds
| # | Item | Where |
|---|---|---|
| 1 | `GET /api/dashboard/live-locations/` and `GET /api/dashboard/worker-path/` (Super Admin only; `TRACKING_VIEW_ROLES` to extend) | new `accounts/views_tracking.py` + 2 routes |
| 2 | `GET/POST/PUT/DELETE /api/accounts/users/<id>/profile-picture/` (JPEG/PNG/WEBP, max 300 KB, stored in the database) | `views_tracking.py` + 1 route |
| 3 | `ProfilePicture` model + migration `0052_profile_picture` (depends on the real `0051_dailyprogressreport_approved_at_and_more`) | new `profile_picture_model.py` + `migrations/0052_profile_picture.py` |
| 4 | `has_profile_picture`, `profile_picture_updated_at` on `GET /api/accounts/me/` | 3 lines in `views.py` |
| 5 | Late-ping guard: an older ping never moves `check_out` backwards | 1 block in `attendance.py` |
| 6 | 17 automated tests | new `accounts/test_tracking_profile_picture.py` |

`views_tracking.py` is self-contained: it imports nothing from `views.py` or `site_roles.py`, so it cannot be broken by those being refactored.

## Install
**Option A – patch** (from the repo root, the folder that contains `backend/`):
```
git apply --directory=backend backend_tracking_picture_addon.patch
```
If a hunk does not apply because those five files changed, use **Option B** for that file.

**Option B – copy files + five small edits**
Copy these from `backend_addon_files.zip` into `backend/accounts/`:
`views_tracking.py`, `profile_picture_model.py`, `migrations/0052_profile_picture.py`, `test_tracking_profile_picture.py`

Then make these edits:

1. `accounts/models.py` – add as the LAST lines:
```python
from .profile_picture_model import ProfilePicture  # noqa: E402,F401
```
2. `accounts/urls_dashboard.py`
```python
from .views_tracking import LiveLocationsView, WorkerPathView        # with the other imports
    path('live-locations/', LiveLocationsView.as_view(), name='dashboard-live-locations'),   # inside urlpatterns
    path('worker-path/', WorkerPathView.as_view(), name='dashboard-worker-path'),
```
3. `accounts/urls.py`
```python
from .views_tracking import ProfilePictureView                       # with the other imports
    path('users/<int:user_id>/profile-picture/', ProfilePictureView.as_view(), name='user_profile_picture'),  # inside urlpatterns
```
4. `accounts/views.py`, `CurrentUserView.get`, just before `return Response({ ... 'id': user.id, ...`:
```python
        from accounts.profile_picture_model import ProfilePicture
        pic_updated = ProfilePicture.objects.filter(user=user).values_list('updated_at', flat=True).first()
```
   and add two keys to the response dict (next to `'username'`):
```python
                'has_profile_picture': pic_updated is not None,
                'profile_picture_updated_at': pic_updated,
```
5. `accounts/attendance.py`, in the `else:` branch ("Existing attendance -> Update checkout"), right after `attendance = existing_attendance`:
```python
        # A late ping (queued on the phone while offline) older than the recorded check-out
        # must never move check-out backwards. The ping is still stored in WorkerLocation.
        if attendance.check_out is not None and timestamp < attendance.check_out:
            return {
                "attendance_status": attendance.status,
                "attendance_id": attendance.id,
                "event": "LOCATION_UPDATE",
            }
```

## Verify locally
```
cd backend
python manage.py makemigrations --check --dry-run      # expect: No changes detected
python manage.py migrate accounts                        # applies 0052 only
python manage.py test accounts.test_tracking_profile_picture      # expect: Ran 17 tests ... OK
```
(Verified on a copy of the backend with migration chain `0049 -> 0050 -> 0051 -> 0052`: no model changes detected, 17 tests pass, and the
late-ping test fails if the guard in step 5 is removed.)

## Production
1. **Migrate production BEFORE deploying the new code:** `python manage.py migrate accounts` against the production database
   (Vercel does not run migrations). Only `0052_profile_picture` is new.
2. Environment variables (names only, no values here): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_STORAGE_BUCKET_NAME`,
   `AWS_S3_REGION_NAME`, **`ATTENDANCE_TIMEOUT_MINUTES=45`** (the code default is 30; 45 is recommended because the app pings every 10 minutes
   and signal gaps are normal). IAM: `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` on `projects/*/site-tasks/*`.
   Leave `TRACKING_VIEW_ROLES` **unset** so only a Super Admin sees live paths.
3. **Scheduler:** `backend/vercel.json` has no cron and Vercel cannot run `manage.py`. Run
   `python manage.py close_stale_attendance` every 10-15 minutes from an external scheduler that has the production database variables.
   Example template for GitHub Actions (adjust the secret names to your production variables):
```yaml
name: close-stale-attendance
on:
  schedule: [{ cron: "*/15 * * * *" }]
  workflow_dispatch: {}
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install -r backend/requirements.txt
      - run: cd backend && python manage.py close_stale_attendance
        env:
          SECRET_KEY: ${{ secrets.SECRET_KEY }}
          DATABASE_URL: ${{ secrets.DATABASE_URL }}   # use the same DB variables your Vercel project uses
          ATTENDANCE_TIMEOUT_MINUTES: "45"
```

## What this add-on does NOT include (and why)
- **Automated tests for site tasks / S3 presign.** They must be written against the team's existing models (`evidence_files`, their S3 helper names), which are not part of this add-on.
- **Deduplication of GPS pings** (a retried upload can store the same point twice; the path stays in time order).
- Retention/deletion job for `WorkerLocation`; video upload; orphaned S3 object cleanup (see `BACKEND_REQUIREMENTS.md`).

## What the mobile app expects from the EXISTING site-task endpoints
The app calls these existing routes and reads the fields below (names must match; the app also accepts `evidence_files` instead of `evidence` on an update row):
- `GET /api/projects-data/site-tasks/?project=<id>` -> `{project:{id,name,status}, summary:{total,done,in_progress,pending,overall_percent}, tasks:[{id,project_id,project_name,order,name,description,progress_percent,status,last_updated_at,last_updated_by,updates_count}]}`
- `GET /api/projects-data/site-tasks/<id>/` -> `{task, history:[update]}`; `POST .../site-tasks/<id>/updates/` -> `201 {task, update}`; `GET /api/projects-data/site-task-updates/?limit=` -> `{results:[update]}`
- update row: `id, task_id, task_name, task_order, project_name, user_name, progress_before, progress_after, ai_progress_percent, edited_by_user, summary, ai_summary, findings[], remarks, analysis{}, media[], photo_count, evidence_count, evidence[{id,media_type,name,url,size_bytes,analysis{}}], lat, lon, created_at`
- `POST .../site-tasks/<id>/evidence/presign/` -> `{files:[{index,key,upload_url,method,headers}]}`; then the update's `evidence:[{key,name,content_type,size_bytes,captured_at,analysis}]`
In the app: avatar menu -> **Connection check** shows which of these routes answer.
