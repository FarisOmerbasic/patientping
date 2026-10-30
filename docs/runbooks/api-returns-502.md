# Runbook: the page opens, but `/api/` answers 502

- **Alert / trigger:** a ticket: the page at http://localhost:8080 opens, but the patients and appointments don't load, and a red error line shows where the lists should be
- **Severity:** critical
- **Owner:** Faris
- **Last tested:** 2026-10-26

## Symptom
The front page loads, but every request under `/api/` gets nginx's `502 Bad Gateway` page. `docker compose ps -a` can still show every service `(healthy)`: each health check asks its own container from inside, so a broken connection between containers doesn't show up there.

## Quick checks (in order)
1. `docker compose ps -a`: compare it with the known-good table. Good: `api` `Up ... (healthy)` with `8080/tcp` in PORTS. Bad: `api` `Exited`, missing, or an empty PORTS column.
2. `curl -s -w ' %{http_code}\n' localhost:8080/api/patients`: good is the list and ` 200`. Bad is nginx's 502 page and ` 502`.
3. `docker compose logs web | grep error`: good is nothing new. Bad is a line that names what nginx tried, like `api could not be resolved (3: Host not found)` or `connect() failed (111: Connection refused)`.
4. `docker inspect "$(docker compose ps -q api)" | jq '.[0].NetworkSettings.Networks'`: good is one entry, `patientping_default`, with an address. Bad is `{}`. Never plain `docker inspect`: it prints `DB_PASSWORD`.

## Likely causes and fixes
| Cause | How to confirm | Fix |
|---|---|---|
| The `api` container is on no network (seen on Day 20, after `docker network disconnect`) | PORTS empty in `ps -a`, `"Networks": {}` in check 4, `api could not be resolved` in nginx's log | `docker compose up -d`: Compose makes the container again on its network. `docker compose restart api` doesn't help, because the same container still has no network |
| The `api` container is stopped or missing | `ps -a` shows `api` `Exited` or no `api` line, and nginx logs `api could not be resolved` | `docker compose logs --tail 20 api` for why it ended, then `docker compose up -d` |
| The API listens on another port than 8080 (seen on Day 19 in the diner) | nginx logs `connect() failed (111: Connection refused)` with the upstream's port | put the port in `compose.yaml` and `nginx.conf` back in line, then `docker compose up -d` |

## Escalation / rollback
`docker compose up -d` gets the page back fastest. It makes again any container that doesn't match `compose.yaml`, and leaves the rest running. Check with the `curl` from quick check 2. Find the cause before or right after, or it comes back: the old container is gone after `up -d`, and its evidence with it.

## Prevention
`docker compose logs web | grep error` showed the cause at once, while every health check said `(healthy)`. Later, an alert that asks `/api/patients` through nginx every minute, or that counts nginx's 5xx answers, would catch it before a clinic calls (Day 43).
