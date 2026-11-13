# Observability

The Compose stack has three pieces for this. Prometheus fetches `/metrics` from the API, the worker and itself every 15 seconds (`observability/prometheus.yml`), and checks two alert rules. Alertmanager sends the alerts that fire to a Discord channel. Grafana draws the numbers, on http://localhost:3000 (`admin` / `admin`, only on `127.0.0.1`).

Grafana is set up from files, not clicks, so a new container comes back the same after `make down` and `make up`:

| File | What it does |
|---|---|
| `observability/grafana/provisioning/datasources/prometheus.yml` | the data source `Prometheus` at `http://prometheus:9090`, with the fixed uid `prometheus` that the panels point at |
| `observability/grafana/provisioning/dashboards/patientping.yml` | the provider: load every dashboard file from `/var/lib/grafana/dashboards` |
| `observability/grafana/dashboards/patientping.json` | the `PatientPing` dashboard, exported from Grafana with the model *Classic* |

## The PatientPing dashboard

Rate, errors and duration: how many requests come in, how many fail, how long they take. And the worker's reminders.

| Panel | Query | What it tells you |
|---|---|---|
| Requests per second | `sum(rate(http_requests_total[1m]))` | How busy the API is: how many requests it answers each second, averaged over the last minute. |
| Share of 5xx | `(sum(rate(http_requests_total{route=~"/api/.+",code=~"5.."}[1m])) / (sum(rate(http_requests_total{route=~"/api/.+"}[1m])) > 0)) or vector(0)` | The share of the requests to `/api/` that got a server error (5xx). It doesn't grow with the traffic like the number of errors does, so one threshold means the same by day and by night. Only `/api/` counts, because `/metrics` and `/healthz` answer 200 several times a minute and would hide the errors at a quiet hour. `> 0` and `or vector(0)` show 0 when no request came in, instead of "No data". |
| p95 latency | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[1m])))` | If it says 300 ms, 95 of 100 requests were answered within 300 ms, and the slowest 5 took longer. It's an estimate from the histogram's buckets, so with every request under 5 ms it shows 4.75 ms. |
| Reminders sent, last hour | `increase(reminders_sent_total[1h])` | How many reminders the worker sent for appointments in the last hour. |

Measured on 2026-11-12, with SQL Server stopped for about a minute during a loop of requests: every `/api/patients` answered 500 after about 4 seconds (`lookup mssql on 127.0.0.11:53: no such host`), the share of 5xx rose to about 58%, and p95 rose from 4.75 ms to about 4 s. The share's first query also counted `/metrics` and `/healthz`, which don't touch the database and kept answering 200. Counting only `/api/`, the same kind of outage on 2026-11-13 showed 100%, where the first query showed 58%.

## Alerts

The rules are in `observability/alerts.yml`, and each one links to [the runbook](runbooks/api-down.md):

| Alert | Fires when | Waits (`for`) | Severity |
|---|---|---|---|
| `APIDown` | `up{job='api'} == 0`: Prometheus can't fetch the API's `/metrics` | 1 minute | critical |
| `HighErrorRate` | more than 5% of the requests to `/api/` get a 5xx, over the last 5 minutes | 5 minutes | warning |

Both are about what users feel, not about causes like SQL Server or CPU. With SQL Server stopped, `HighErrorRate` fired on the errors, and `APIDown` stayed quiet because the API itself was up. With the API stopped, it's the other way round: nothing counts its errors, and `APIDown` fires.

The way from a problem to a message:

1. Prometheus checks the rules every 15 seconds (`evaluation_interval`). A rule whose query returns something is *pending*, and *firing* once that has lasted its whole `for`. A shorter blip goes back to *inactive* and sends nothing.
2. Prometheus sends the firing alerts to Alertmanager (`alerting:` in `prometheus.yml`, `alertmanager:9093`).
3. Alertmanager (`observability/alertmanager.yml`) groups them by name, waits 30 seconds for others of the same name (`group_wait`), and sends one message to Discord. When the alert ends, the "resolved" message comes at the group's next turn (`group_interval`, 1 minute). An alert that keeps firing is sent again every 4 hours.

Measured on 2026-11-13: with the API stopped, `APIDown` reached Discord about 2 minutes later, and `[RESOLVED]` came about 3 minutes after the start. With SQL Server stopped, `HighErrorRate` reached Discord about 6.5 minutes later in one run and about 7.5 in another: the 5-minute window still holds the good requests from before the stop, so the more traffic there was, the longer the share takes to pass 5%.

The pages: http://localhost:9090/alerts shows each rule's state, and Alertmanager's page, http://localhost:9093, shows the alerts it holds and the silences.

### Discord

Alertmanager sends through a webhook of a Discord channel. Anyone who has the webhook's URL can post into the channel, so it stays out of Git: it's the only line of `observability/discord.url`, which `.gitignore` ignores (`observability/*.url`), and `alertmanager.yml` only names the file (`webhook_url_file`).

To get the messages: in a Discord server of your own, the channel's *Edit Channel*, *Integrations*, *Webhooks*, *New Webhook*, then *Copy Webhook URL*. Paste it into `observability/discord.url` in an editor, never on the command line, where the shell's history would keep it. Then:

```bash
docker compose up -d --force-recreate alertmanager
docker compose exec alertmanager amtool alert add Test severity=info --alertmanager.url=http://localhost:9093
```

A message titled `[FIRING:1] Test (info)` should arrive about 30 seconds later, and `[RESOLVED] Test (info)` about 5 minutes after that, because an alert from `amtool` has no end and Alertmanager calls it resolved after 5 minutes.

Without the file, Docker would make a folder owned by root in its place, so `make up` makes it empty first. Alertmanager then runs and logs `unsupported protocol scheme ""` at each message it can't send.

### Checks

`make lint`, which CI runs too, checks the three files: `promtool check config` reads `prometheus.yml` and the rules file it names, `amtool check-config` reads `alertmanager.yml`, and `promtool test rules` runs the rules' unit tests in `observability/alerts.test.yml`. Those feed made-up series to the rules: `APIDown` waits its whole minute and stays quiet through a 30-second blip, and `HighErrorRate` fires at a quiet hour when every patient request fails, but not at 2% errors. The quiet hour is the case the first version of the rule missed, because it also counted `/metrics` and `/healthz`.

A test that only checks the shape passes a rule that never fires. To see one fire for real, stop what it watches, and keep the Alerts page or Discord open:

```bash
docker compose stop api
```

`docker compose start api` ends the test.

## Changing the dashboard

A provisioned dashboard can't be saved from Grafana's page. Change it there, then *Export*, *Export as code*, the model *Classic* with *Share dashboard with another instance* off, and replace `patientping.json` with it. The panels must keep pointing at the uid `prometheus`:

```bash
jq -r '[.. | .datasource? | objects | .uid] | unique | .[]' observability/grafana/dashboards/patientping.json
```

It should print `-- Grafana --` (Grafana's own source for annotations) and `prometheus`. Then `docker compose up -d --force-recreate grafana`.

`docker compose exec grafana ls /var/lib/grafana/dashboards` shows what the container sees. On 2026-11-13, a Grafana container that had run since the evening before saw both of its mounted folders empty, so a changed file never reached it. A new container saw them again.
