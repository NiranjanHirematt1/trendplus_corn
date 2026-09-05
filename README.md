# trendplus-cron

A keep-alive pinger. Nothing else.

GitHub Actions → every 10 minutes → one GET to the Trendplus **Render backend** →
log the status code and stop. That inbound request resets Render's idle timer, so the
instance never spins down and no visitor ever waits ~50s for a cold start.

```
.
├── .github/workflows/job-search-cron.yml   # the whole project
├── trigger.sh                              # optional: same ping, run locally
├── .gitignore
└── README.md
```

## Which URL to ping — this matters

Ping the **Render service**, not the pretty domain:

```
TRENDPLUS_CRON_URL = https://trendplus-lvkt.onrender.com/health
```

`https://trendplus.co.in` serves the **frontend** (static hosting — it never sleeps, so
pinging it achieves nothing) and it does not proxy to Render: `https://trendplus.co.in/health`
returns 404, while `https://trendplus-lvkt.onrender.com/health` returns `{"status":"ok"}`.
A ping to the custom domain would go green every time while the backend quietly slept.

`/health` is the right path: it is the cheapest route on the service, and *any* inbound
request is enough to reset the idle timer — it does not need to do real work.

Quick check that a URL really hits Render: it must return `{"status":"ok"}`, and the very
first request after a long idle period takes tens of seconds (the cold start you are
trying to avoid).

## Setup

1. **Add the secret.** Repo → Settings → Secrets and variables → Actions → Secrets →
   *New repository secret*
   - Name: `TRENDPLUS_CRON_URL`
   - Value: `https://trendplus-lvkt.onrender.com/health`
2. **Run it once by hand.** Actions tab → *Trendplus Keep-Alive* → **Run workflow**.
3. Open the run → step *Ping endpoint*. Success looks like:
   ```
   Backend pinged successfully
   HTTP status: 200
   Elapsed: 0.42s | response size: 15 bytes (body not logged)
   ```
   An `Elapsed` above 10s raises a warning — that means the instance had been asleep and
   the ping woke it, which is exactly what this is here to prevent.

Optional repository *variables* (Variables tab), only if a default is ever wrong:

| Variable | Default | Purpose |
|---|---|---|
| `TRENDPLUS_HTTP_METHOD` | `GET` | method to use |
| `TRENDPLUS_MAX_TIME` | `150` | seconds for the whole request (generous, for cold starts) |
| `TRENDPLUS_AUTH_HEADER_NAME` | `X-Admin-Secret` | header name, if you ever ping a protected route |

Optional secret `TRENDPLUS_AUTH_TOKEN`: if you create it, its value is sent in that header.
If it does not exist, no auth header is sent. Nothing is hard-coded.

## Checking that the schedule works

- Actions tab → runs labelled `schedule` should appear roughly every 10 minutes.
- Schedules only run from the **default branch** (`main`), and the first one usually shows
  up 5–20 minutes after the push. GitHub's cron is best-effort — runs are often a few
  minutes late and an occasional one is skipped, which is why the interval is 10 and not 15.
- GitHub **disables scheduled workflows after 60 days of repository inactivity** (it emails
  you first). Any commit re-arms it.
- Pause it any time: Actions → the workflow → `...` → **Disable workflow**.
- Public repo ⇒ Actions minutes are free and unlimited.

Heads up on Render's own limit: a free instance that never sleeps burns ~730 instance-hours
a month against the 750-hour free allowance, and that allowance is shared across all free
services in the account. One always-awake service fits; two do not.

## "The Actions tab says there are no workflows"

Things to check, in order:

1. You are on the **Actions** tab of the right repo, and the left sidebar lists
   *Trendplus Keep-Alive*. "There are no workflow runs yet" is a different message —
   it means the workflow is registered but has not run, which is normal until you press
   **Run workflow** or the first schedule fires.
2. The file is on the **default branch** at exactly `.github/workflows/job-search-cron.yml`
   (repo root — not nested inside another folder). Confirm on the Code tab.
3. `git status` shows nothing to commit and `git log origin/main..main` is empty — i.e. the
   push actually landed.
4. Settings → Actions → General → "Allow all actions" is selected, not "Disable actions".
