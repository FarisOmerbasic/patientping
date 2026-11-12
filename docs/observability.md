# Observability

The Compose stack has two pieces for this. Prometheus fetches `/metrics` from the API, the worker and itself every 15 seconds (`observability/prometheus.yml`). Grafana draws the numbers, on http://localhost:3000 (`admin` / `admin`, only on `127.0.0.1`).

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
| Share of 5xx | `(sum(rate(http_requests_total{code=~"5.."}[1m])) or vector(0)) / sum(rate(http_requests_total[1m]))` | The share of all answers that were server errors (5xx). It doesn't grow with the traffic like the number of errors does, so one threshold means the same by day and by night. `or vector(0)` shows 0 when nothing has failed yet, instead of "No data". |
| p95 latency | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[1m])))` | If it says 300 ms, 95 of 100 requests were answered within 300 ms, and the slowest 5 took longer. It's an estimate from the histogram's buckets, so with every request under 5 ms it shows 4.75 ms. |
| Reminders sent, last hour | `increase(reminders_sent_total[1h])` | How many reminders the worker sent for appointments in the last hour. |

Measured on 2026-11-12, with SQL Server stopped for about a minute during a loop of requests: every `/api/patients` answered 500 after about 4 seconds (`lookup mssql on 127.0.0.11:53: no such host`), the share of 5xx rose to about 58%, and p95 rose from 4.75 ms to about 4 s. The share stayed below 100% because `/metrics` and `/healthz` don't touch the database and kept answering 200.

## Changing the dashboard

A provisioned dashboard can't be saved from Grafana's page. Change it there, then *Export*, *Export as code*, the model *Classic* with *Share dashboard with another instance* off, and replace `patientping.json` with it. The panels must keep pointing at the uid `prometheus`:

```bash
jq -r '[.. | .datasource? | objects | .uid] | unique | .[]' observability/grafana/dashboards/patientping.json
```

It should print `-- Grafana --` (Grafana's own source for annotations) and `prometheus`. Then `docker compose up -d --force-recreate grafana`.
