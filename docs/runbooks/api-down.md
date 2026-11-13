# Runbook: the API is down, or answers with errors

- **Alert / trigger:** `APIDown` (Prometheus can't fetch the API's `/metrics` for 1 minute) or `HighErrorRate` (more than 5% of the requests to `/api/` get a 5xx, for 5 minutes), sent by Alertmanager to Discord. Both rules are in `observability/alerts.yml`.
- **Severity:** `APIDown` critical, `HighErrorRate` warning
- **Owner:** Faris
- **Last tested:** 2026-11-13

## APIDown

### Symptom
Nobody gets an answer from the API. The page at http://localhost:8080 opens, because nginx still runs, but every request under `/api/` gets nginx's 502. The Discord message is titled `[FIRING:1] APIDown (api:8080 api critical)`. `HighErrorRate` stays quiet, because with the API down nothing counts its answers.

### Quick checks (in order)
1. `docker compose ps -a`: good is `api` with `Up ... (healthy)`. Bad is `Exited (...)`, `Restarting`, or no `api` line at all.
2. `docker compose logs --tail 50 api`: the last lines before it stopped. A JSON line with `"level":"ERROR"` and its `err` field usually names the reason.
3. `docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' "$(docker compose ps -aq api)"`: the exit code, and `true` if memory killed it. Never plain `docker inspect`: it prints `DB_PASSWORD`.
4. If `compose.yaml` or `.env` changed just before: `docker compose config --quiet; echo "exit=$?"`.

### Likely causes and fixes
| Cause | How to confirm | Fix |
|---|---|---|
| The container was stopped (seen on 2026-11-13, `docker compose stop api` on purpose) | `ps -a` shows `api` `Exited` | `docker compose up -d` |
| It stopped on an error at the start | exit code 1, and an `ERROR` line in check 2 | fix what the line names, then `docker compose up -d` |
| It was killed | exit code 137; `OOMKilled` `true` means memory | `docker compose up -d`; for memory, see `available-memory-dropped.md` |
| The container exists but has no network (seen in a drill) | `Up` in `ps -a` but nginx logs `api could not be resolved` | see `api-returns-502.md` |

### Escalation / rollback
`docker compose up -d` brings the API back: it starts a stopped container and makes a missing one again. Then check from outside, through nginx, the way users come in:

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/patients
```

Good is `200`. The `[RESOLVED] APIDown` message follows about 3 minutes later. On the server, a release that doesn't start is rolled back with `deploy-and-rollback.md`.

## High error rate

### Symptom
The API runs and answers, but more than 5% of the requests to `/api/` get a 5xx. Users see an error where the lists should be. The Discord message is titled `[FIRING:1] HighErrorRate (warning)`. `APIDown` stays quiet, because the API itself is up.

### Quick checks (in order)
1. `docker compose ps -a`: `api` is `Up`, so look at what it needs behind it. Is `mssql` `Up ... (healthy)`?
2. `docker compose logs --tail 20 api`: the `err` field of the `request failed` lines names what fails.
3. `curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/patients`: `500` while the problem lasts, `200` when it's fixed.

### Likely causes and fixes
| Cause | How to confirm | Fix |
|---|---|---|
| SQL Server is stopped (seen on 2026-11-13, `docker compose stop mssql` on purpose) | `mssql` `Exited` in `ps -a`, and `"err":"lookup mssql on 127.0.0.11:53: no such host"` in the API's log | `docker compose up -d`; the API answers 200 again within about 10 seconds |
| A new release with a bug | the errors started right after a deploy, and the log names a code path | roll back to the last good tag with `deploy-and-rollback.md` |

### Escalation / rollback
As for `APIDown`: `docker compose up -d` locally, `deploy-and-rollback.md` on the server. The `[RESOLVED]` message comes a few minutes after the fix, because the share is taken over the last 5 minutes and still holds the errors for a while.

## Prevention
Both alerts are on symptoms, what users feel, and not on causes like SQL Server or CPU: with SQL Server stopped, no rule about SQL Server was needed, because `HighErrorRate` fired on the errors it caused.

`make lint`, in CI too, runs the rules' unit tests in `observability/alerts.test.yml`: `APIDown` waits its whole minute and stays quiet through a 30-second blip, and `HighErrorRate` fires at a quiet hour when every patient request fails, but not at 2% errors. Its first version also counted `/metrics` and `/healthz`, which always answer 200, and at one patient request every 2 minutes it stayed quiet while every one of them failed.

Measured on 2026-11-13: `APIDown` was *pending* about 40 s after the stop, *firing* 1 minute later, and in Discord about 2 minutes after the stop; `[RESOLVED]` about 3 minutes after the start. `HighErrorRate`, still in its first version, with SQL Server stopped and a request every 0.2 s: *pending* about 1 minute after the stop, *firing* 5 minutes later, and in Discord about 30 s after that; it ended about 5 minutes after SQL Server was started again, because the 5-minute share still held the errors. The current version, after a steady 4.8 requests a second: *pending* 1 min 56 s after SQL Server stopped and *firing* 6 min 56 s after it, because the 5-minute window still held the good requests from before the stop, while the failing ones came only about every 4 seconds.
