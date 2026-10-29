# Runbook: healthcheck.sh

- **Owner:** Faris
- **Last tested:** 2026-10-16

## What it does

`scripts/healthcheck.sh` checks the health of a list of URLs given as arguments. It prints a table with each URL's HTTP status, response time and OK or FAIL. Then it exits 0 if every URL is healthy, 1 if at least one failed, and 2 if it was called the wrong way.

## How to run it

```
Usage: healthcheck.sh [-t TIMEOUT] [-r RETRIES] URL [URL...]
```

- `-t TIMEOUT`: seconds to wait for an answer (default 5).
- `-r RETRIES`: how many times each URL is tried, with 2 seconds between tries (default 3). `-r 1` means one try.
- Both values must be whole numbers of 1 or more.

Example: two URLs, a 2-second timeout and one try each.

```
$ scripts/healthcheck.sh -t 2 -r 1 http://localhost:8080 http://localhost:8080/nope; echo "exit=$?"
URL                                      Status Elapsed(s) Result
http://localhost:8080                    200      0.005713 OK
http://localhost:8080/nope               404      0.002282 FAIL
Failed is greater than 0, exiting with code 1
exit=1
```

The exit code isn't printed by the script. A pipeline reads it directly, and in a terminal `echo $?` shows it.

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | every URL is healthy | nothing |
| 1 | the check ran, and at least one URL failed | find the FAIL row. The status tells you more: `000` means no answer at all, `404` means the page doesn't exist, `5xx` means the app itself is broken. Fix what failed. |
| 2 | called the wrong way, nothing was checked | read the one-line message or the help text. Fix the command that calls the script: replace the bad value or add the missing URL. The services may be fine. |

## Test commands

Setup: a healthy target on port 8080 (`docker run -d --name web -p 8080:80 nginx:stable`), and nothing listening on port 9.

| Command | Expected result |
|---|---|
| `scripts/healthcheck.sh -r 1 http://localhost:8080; echo "exit=$?"` | one OK row, `exit=0` |
| `scripts/healthcheck.sh -r 1 http://localhost:9 http://localhost:9; echo "exit=$?"` | two FAIL rows, `exit=1` |
| `scripts/healthcheck.sh; echo "exit=$?"` | the help text, `exit=2` |
| `scripts/healthcheck.sh -r 0 http://localhost:8080; echo "exit=$?"` | `healthcheck.sh: retries must be a whole number of 1 or more: 0`, `exit=2` |
| `scripts/healthcheck.sh -r abc http://localhost:8080; echo "exit=$?"` | `healthcheck.sh: retries must be a whole number of 1 or more: abc`, `exit=2` |
| `scripts/healthcheck.sh -t abc -r 1 http://localhost:8080; echo "exit=$?"` | `healthcheck.sh: timeout must be a whole number of 1 or more: abc`, `exit=2` |

256 dead URLs. Exit codes only go from 0 to 255, so before Day 6, 256 failures came out as `exit=0`:

```
urls=(); for i in $(seq 1 256); do urls+=("http://localhost:9"); done
scripts/healthcheck.sh -r 1 "${urls[@]}" > /dev/null; echo "exit=$?"      # exit=1
```

The error messages go to stderr, so `2>/dev/null` hides them and leaves only the `exit=` line.
