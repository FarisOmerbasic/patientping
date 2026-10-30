# Runbook: available memory dropped

- **Alert / trigger:** memory alert: `available` in `free -h` drops all at once and stays down
- **Severity:** warning
- **Owner:** Faris
- **Last tested:** 2026-10-17 (first `/breakit`: found in about 8 minutes, fixed in about 2)

## Symptom
`available` in `free -h` dropped by about 1.4G all at once and didn't come back. No program was using the memory: `ps` showed the same programs with the same `%MEM` as before.

## Quick checks (in order)
1. `free -h`: good is `available` around 4.7Gi and `shared` around 51Mi. Bad is `available` down and `shared` up by about the same amount.
2. `ps aux --sort=-%mem | head -5`: good is the usual programs with the same `%MEM` as before (`START` shows how long each one has been running). If a new or growing program is at the top, this runbook doesn't fit: a program is using the memory, not a file.
3. `df -h /tmp`: good is about 1%. Bad is well above that, with `Used` close to the jump in `shared`.
4. `du -sh /tmp/* 2>/dev/null | sort -h | tail -5`: the five biggest names in `/tmp`, largest at the bottom. Bad is one big file you don't expect.

## Likely causes and fixes
| Cause | How to confirm | Fix |
|---|---|---|
| A big file in `/tmp`. On this machine `/tmp` is a tmpfs, kept in memory, so the file uses RAM, not disk | `df -h /tmp` well above 1%, `du` names the file, `ls -l <file>` shows a time that matches the alert | Ask whose file it is, then move it to the real disk under `~` or delete it with `rm`. Check with `free -h`: `shared` back near 51Mi, `available` back up |

## Escalation / rollback
Fastest way back, even before the file is found: restart WSL. In Windows PowerShell, `wsl --shutdown` stops all WSL distros. A tmpfs is cleared on restart, so `/tmp` is empty afterwards. The cost: everything else that is running stops too, including VS Code's connection, Docker Desktop's link to WSL, and any running job.

## Prevention
- Alert when `Use%` of `/tmp` goes above 25%. Normal is 1%. An alert at 1% would fire all the time and get ignored.
- Scripts that write big exports write them to the real disk, in a directory under `~`, not to `/tmp`.
