# trendplus-cron

A scheduler. Nothing else.

GitHub Actions → every 15 minutes → one HTTP request to an endpoint on the existing
Trendplus site → log the status code and stop.

No scrapers, no filters, no email, no database, no frontend, no backend, no deployment.
All of that already lives in Trendplus. This repo replaces cron-job.org only.

```
.
├── .github/workflows/job-search-cron.yml   # the whole project
├── trigger.sh                              # optional: run the same call locally
├── .gitignore
└── README.md
```

---

## 1. First: find the endpoint that actually runs the job search

Do **not** put the homepage in the secret. Hitting the homepage of either deployment
only wakes the server up — it does not start a search. Here is how to find the real one.

### Which of your two URLs is which

| URL | What it is |
|---|---|
| `https://trendplus-five.vercel.app/` | the **frontend** (static HTML/JS). It has no schedulable work; it only calls the API from a browser. Not a cron target. |
| `https://trendplus-lvkt.onrender.com` | the **API backend** (FastAPI, "TrendPulse API v2.0.0"). The endpoint you want is on this host. |

### How to list every endpoint the backend has

The backend publishes its own machine-readable route list:

- Open **`https://trendplus-lvkt.onrender.com/docs`** in a browser (interactive Swagger UI), or
- Open **`https://trendplus-lvkt.onrender.com/openapi.json`** (raw JSON of every route).

Look for the route whose description matches "run / trigger / refresh / update", and
check its **method** (GET vs POST) and whether it requires a **header**.

### What that list currently shows

Routes on `trendplus-lvkt.onrender.com`:

```
GET  /health
GET  /api/trend                     GET  /api/sector
GET  /api/trend/dates               GET  /api/sector/list
GET  /api/search                    GET  /api/sector/{sector_name}
GET  /api/symbol/{sym}              GET  /api/superstrength
GET  /api/admin/status              GET  /api/admin/runs
POST /api/admin/run        <-- triggers the engine run (the "search")
POST /api/admin/backfill            (full historical re-processing — NOT for a 15-min cron)
```

`POST /api/admin/run` is documented as *"Triggers a full engine run in the background.
The run loads all bhav files, computes metrics, and upserts to DB."* It requires a
header named **`X-Admin-Secret`**. That is almost certainly your endpoint:

```
TRENDPLUS_CRON_URL   = https://trendplus-lvkt.onrender.com/api/admin/run
TRENDPLUS_AUTH_TOKEN = <the value of X-Admin-Secret / ADMIN_SECRET from your Render env vars>
```

### Confirm it yourself before trusting it (30 seconds)

1. Check the "before" state — note `last_run` / `successful_runs`:
   `https://trendplus-lvkt.onrender.com/api/admin/status`
2. Fire the endpoint once (PowerShell):
   ```powershell
   curl.exe -X POST -H "X-Admin-Secret: YOUR_SECRET" -i https://trendplus-lvkt.onrender.com/api/admin/run
   ```
3. Reload `/api/admin/status`. If `currently_running` flips to `true`, or `last_run` /
   `successful_runs` changes, that endpoint is the right one. If nothing changes, it is not.

Three other ways to identify it, if the above is ever ambiguous:

- **Read your own repo**: grep the Trendplus backend for the route decorators
  (`@app.post(` / `@router.post(`) — the file names the path directly.
- **Watch the browser**: open the site, press F12 → Network, click the button that
  starts a refresh, and copy the request URL + method it fires.
- **Look at what cron-job.org was configured with**: its job history shows the exact URL,
  method and headers it was sending, plus whether the responses were 200s.

If the endpoint turns out to be a GET rather than a POST, or the header is named
something else, you do not touch the workflow — you change one repository *variable*
(see the table in section 3).

---

## 2. Create the GitHub repository

Option A — from your machine (GitHub CLI):

```bash
cd "E:\my corn\trendplus-cron"
git init
git add .
git commit -m "GitHub Actions scheduler for Trendplus job search"
git branch -M main
gh repo create trendplus-cron --private --source=. --remote=origin --push
```

Option B — from the website:

1. Go to <https://github.com/new>.
2. Name: `trendplus-cron`. Visibility: **Private**. Do **not** add a README/.gitignore
   (this project already has them).
3. Create the repository, then push from the folder:

```bash
cd "E:\my corn\trendplus-cron"
git init
git add .
git commit -m "GitHub Actions scheduler for Trendplus job search"
git branch -M main
git remote add origin https://github.com/<your-username>/trendplus-cron.git
git push -u origin main
```

Note: private repos consume Actions minutes (2,000/month free). Every 15 minutes is
~2,880 runs/month at a few seconds each — comfortably inside the free tier, but if you
would rather not count minutes at all, make the repo **public**; Actions is unlimited there.
Nothing secret is in the files — the URL and token live in Secrets either way.

---

## 3. Add the secrets

**Settings → Secrets and variables → Actions → Secrets tab → New repository secret**

| Secret | Required | Value |
|---|---|---|
| `TRENDPLUS_CRON_URL` | yes | the full endpoint URL, e.g. `https://trendplus-lvkt.onrender.com/api/admin/run` |
| `TRENDPLUS_AUTH_TOKEN` | only if the endpoint needs auth | the token value. If this secret is absent, no auth header is sent at all. |

**Variables tab** (plain config, not secret — all optional, only add one if the default is wrong):

| Variable | Default | Use when |
|---|---|---|
| `TRENDPLUS_HTTP_METHOD` | `POST` | your endpoint is a `GET` |
| `TRENDPLUS_AUTH_HEADER_NAME` | `X-Admin-Secret` | your header is named something else, e.g. `Authorization` (then set the secret to `Bearer eyJ...`) or `X-API-Key` |
| `TRENDPLUS_CONNECT_TIMEOUT` | `20` | seconds to wait for the connection |
| `TRENDPLUS_MAX_TIME` | `120` | seconds for the whole request. Render free instances sleep and can take ~50s to wake, hence the generous default. |

Secrets are masked in logs automatically, and nothing in this repo prints the token or
the response body.

---

## 4. Test it manually

1. Repo → **Actions** tab. If you see "Workflows aren't being run on this forked
   repository" or a green enable button, click to enable Actions.
2. Select **Trendplus Job Search Cron** in the left sidebar.
3. **Run workflow** (top right) → branch `main` → **Run workflow**.
4. Open the run → job **Trigger Trendplus job search** → step **Call Trendplus endpoint**.

Success looks like:

```
Method: POST
Auth header: X-Admin-Secret (value hidden)
Job search triggered successfully
HTTP status: 200
Elapsed: 1.84s | response size: 62 bytes (body not logged)
```

Then reload `https://trendplus-lvkt.onrender.com/api/admin/status` and confirm the run
actually registered on the Trendplus side. A green workflow only proves the request was
delivered — the status endpoint proves the work started.

Failures are explicit, and the first 300 bytes of the body are shown only when something
went wrong:

- `Secret TRENDPLUS_CRON_URL is not set.` → secret missing or misspelled
- `Trendplus returned HTTP status: 401/403` → wrong or missing token, or wrong header name
- `Trendplus returned HTTP status: 404` → wrong path in the URL
- `Trendplus returned HTTP status: 405` → right path, wrong method → set `TRENDPLUS_HTTP_METHOD`
- `timed out after 120s` → endpoint is slow or the instance never woke → raise `TRENDPLUS_MAX_TIME`
- `DNS resolution failed` / `connection refused` → hostname wrong or the service is down

## 5. Check the schedule is running

- **Actions** tab → the run list. Scheduled runs are labelled `schedule`; manual ones
  `workflow_dispatch`. You should see a new entry roughly every 15 minutes.
- The schedule only starts **after** the workflow file exists on your **default branch**
  (`main`). The first scheduled run typically appears 5–20 minutes after the push.
- GitHub's cron is best-effort: at busy times runs are delayed by several minutes and an
  occasional interval is skipped. `*/15` means "about every 15 minutes", not exactly.
- Cron is **UTC**. Irrelevant here (it runs all day), but it matters if you ever narrow the
  hours — 9:00 AM IST is `30 3 * * *`.
- GitHub **disables scheduled workflows after 60 days with no repository activity** and
  emails you first. Any commit re-arms it; re-enable from the Actions tab.
- To pause it: Actions → the workflow → `...` → **Disable workflow**. To stop permanently,
  delete the `schedule:` block (`workflow_dispatch` keeps the manual button).

## 6. Turn off the old cron-job.org job

Once you have seen a few green scheduled runs here, delete or disable the cron-job.org job
so the endpoint is not being hit twice.
