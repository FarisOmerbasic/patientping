# Runbook: deploy, roll back, and a deploy job that hangs

- **Alert / trigger:** a merge to `main` (a normal deploy); a red `deploy` job, or a broken release found later (a rollback); a run whose `deploy` job doesn't finish (it hangs)
- **Severity:** critical when users get errors, warning otherwise
- **Owner:** Faris
- **Last tested:** 2026-11-10

## A normal deploy

A **merge** to `main` starts it. A pull request on its own only runs `lint`, `test` and `build`: its `image` and `deploy` jobs are skipped. The run on `main` then runs `image`, which pushes both images to ECR as `sha-<commit>` and looks for a running server tagged `patientping-dev`. When one runs, `deploy` waits in the environment `production` for an approval, about 2 minutes after the merge. When none runs, `deploy` is skipped, the run stays green, and the `image` job's last step says `no dev server runs, so deploy is skipped`.

1. On the run's page: *Review deployments*, tick `production`, *Approve and deploy*. If the server was destroyed after the run started, *Reject*: a waiting deploy counts as running, and every later run on `main` queues behind it.
2. The job finds the server by its `Name` tag, sends `deploy.sh sha-<commit>` to it through Run Command, waits for the result, and runs a smoke test from GitHub's runner.
3. It worked when the run is green, and the deploy log has `deploy.sh: sha-<commit> deployed and healthy` and the smoke test's `200`. From the laptop, with the address from the log's `server:` line (or `terraform output -raw public_ip` in `infra/envs/dev`):

   ```bash
   curl -fsS -o /dev/null -w "%{http_code}\n" "http://$IP/api/patients"
   ```

   Good is `200`. It took 55 s and 45 s from the approval to healthy on 2026-11-10.

**When the new version doesn't answer 200,** `deploy.sh` puts the last good version back by itself (the tag in `/opt/patientping/CURRENT_TAG`, written only after a passed health check), waits for its 200, and still exits 1. The job is red, and the site answers with the old version. In the drill on 2026-11-10, the failure was noticed 72 s into the script, the rollback took 30 s, and users got errors for about 89 s. **Then fix forward:** `main` still has the broken commit, so the next merge, a docs PR too, would deploy it again. Fix `main` with a new PR before anything else is merged.

## A manual rollback to a chosen version

For the cases the automatic rollback doesn't cover: a fresh server has no `CURRENT_TAG` yet, or the release passed its check and is broken in another way (`deploy.sh` only asks `/api/patients`).

1. **Find the tag.** It is `sha-` and the full merge commit of the version to go back to. `git fetch`, then `git log --oneline origin/main` lists the merges, and `git rev-parse` with a short commit gives the full one. The last version that passed on the server is in `/opt/patientping/CURRENT_TAG` (in a session: `sudo cat /opt/patientping/CURRENT_TAG`). Check that its images are in ECR:

   ```bash
   aws ecr describe-images --profile pp-readonly --repository-name patientping-api --image-ids imageTag="sha-$SHA" --query 'imageDetails[0].imageTags' --output text
   ```

2. **Run it on the server through SSM Run Command**, the same `send-command` the `deploy` job uses, from the laptop. Set `SHA` to the full commit from step 1 first. The script itself comes from `main`'s newest commit, so the rollback runs the newest `deploy.sh` with the old tag:

   ```bash
   ID=$(aws ec2 describe-instances --profile pp-readonly --filters Name=tag:Name,Values=patientping-dev Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)
   SCRIPT_SHA=$(git rev-parse origin/main)
   CMD_ID=$(aws ssm send-command --profile pp-admin --instance-ids "$ID" --document-name AWS-RunShellScript --comment "rollback to sha-$SHA" --parameters "commands=[\"curl -fsSL https://raw.githubusercontent.com/FarisOmerbasic/patientping/$SCRIPT_SHA/deploy/deploy.sh -o /tmp/deploy.sh\",\"bash /tmp/deploy.sh sha-$SHA\"]" --query Command.CommandId --output text)
   aws ssm get-command-invocation --profile pp-readonly --command-id "$CMD_ID" --instance-id "$ID" --query '[Status,ResponseCode]' --output text
   ```

3. Good is `Success 0`: the chosen version answers 200, and `CURRENT_TAG` names it now. `--query StandardOutputContent` (and `StandardErrorContent`) shows the script's lines. `deploy.sh` never prints a password; never run it with `bash -x`.

Two warnings:

- **`main` still has the newer commits.** The next merge deploys `main`'s newest commit again. Fix `main` first, with a revert or a fix PR.
- **Never roll back across a migration.** The database stays at the new version, the old release's migrate step finds no file for it (`no migration found for version N`, exit 1), and `api` and `worker`, which wait for that step, never start: the site goes down. Fix forward instead. (Seen in a test with the migrate tool on 2026-11-10; Compose had already replaced the running containers with ones that stayed `created`.)

## The deploy job hangs or takes long

Since 2026-11-10 the job waits for the server up to three times, about 300 s in all. A deploy that rolls back took 102 s, so more than 100 s on its own is normal; its first wait then ends with `Max attempts exceeded ... "InProgress"`, which is expected.

### Quick checks (in order)

1. The run's page: `deploy` says it's waiting. Good: *Review deployments* is there, so it waits for an approval. Approve, or *Reject* when no server runs.
2. The run is queued and doesn't start: `gh run list --branch main --limit 3`. Bad: an older run on `main` is still `waiting`. Runs on `main` wait their turn and are never cancelled, so approve or reject the older one. To reject it from the terminal, with its run number in `RUN` (from that list):

   ```bash
   gh api -X POST "repos/FarisOmerbasic/patientping/actions/runs/$RUN/pending_deployments" -F "environment_ids[]=$(gh api repos/FarisOmerbasic/patientping/environments/production --jq .id)" -f state=rejected -f comment="No server running"
   ```
3. The *Deploy* step runs long: the command on the server, with the command and the server from the log's `command:` and `server:` lines. `InProgress` is normal for up to about two minutes; `Success` or `Failed` means it's done.

   ```bash
   aws ssm get-command-invocation --profile pp-readonly --command-id "$CMD_ID" --instance-id "$ID" --query '[Status,ResponseCode]' --output text
   ```

4. The server's agent: good is `Online`. Anything else, and Run Command can't reach the server.

   ```bash
   aws ssm describe-instance-information --profile pp-readonly --query 'InstanceInformationList[].[InstanceId,PingStatus]' --output text
   ```

5. After all three waits the job fails with `deploy: the command ended with InProgress`. The server goes on: check 3 again, then `--query StandardErrorContent` for what it's doing.

### Likely causes and fixes

| Cause | How to confirm | Fix |
|---|---|---|
| The deploy waits for an approval | *Review deployments* on the run's page | approve, or reject when no server runs |
| The run queues behind an older one | `gh run list --branch main` shows an older run `waiting` | approve or reject that one |
| A rollback is running (seen on 2026-11-10) | the command is `InProgress`, then `Failed`, with `rolling back to ...` in `StandardErrorContent` | nothing: wait. The job turns red, and the site answers with the old version |
| A fresh server is still running its user data | the server is only minutes old | nothing: `deploy.sh` waits for `cloud-init` first |
| The agent is offline | check 4 isn't `Online` | wait a minute after the start; if it stays offline, check the instance profile `pp-ec2-ssm` |

## Escalation / rollback

A release that doesn't answer 200 is rolled back by `deploy.sh` itself. For anything else, the manual rollback above, never across a migration. Afterwards, fix `main` forward before the next merge.

## Prevention

- PR 2 of the drill had a wrong port in `nginx.conf`, and all its checks were green: they lint, test and build, and none of them asks nginx for `/api/`. A CI job that starts the stack with Compose and runs one `curl` through nginx would catch that before the merge.
- Migrations that keep the previous version working (add a column first, remove the old one in a later release), so a rollback stays possible.
- In the drill, `mssql` was recreated with every new release, so each deploy also waits for SQL Server to start. Finding out why, and keeping it running, would make deploys and rollbacks faster.
