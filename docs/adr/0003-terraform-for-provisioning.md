# ADR 0003: Build the AWS environments with Terraform, keep the CLI for checks and secrets

- **Status:** accepted
- **Date:** 2026-11-06

## Context

The dev network and the server were first built by hand with the AWS CLI, from a command log on the laptop. That worked, but:

- The nine creates for the network had to run in the right order, and each ID lived in a shell variable that was gone once the terminal closed.
- Taking it apart meant thirteen deletes in reverse order by hand: seven for the network, six for the server and its role.
- Some mistakes were easy to miss, because AWS accepted them: a second internet gateway after a `--query` typo had put `None` into a variable, and a subnet made with the VPC's whole block.
- The same commands had to be typed again every time the environment was rebuilt.
- What existed, and which permissions the server had, was written down only in AWS and in a log that wasn't in the repo.

## Options considered

1. **The AWS CLI by hand:** good for learning what each command does. But it's easy to miss a step or a value, everything has to be typed again for each rebuild, and nothing in the repo shows what exists.
2. **Terraform:** the environment is described in files, and `plan`, `apply` and `destroy` replace the long lists of commands. The references between resources set the order, `terraform fmt` and `validate` catch small mistakes, and a change is a diff in a pull request. Against it: the state holds every value in plain text, so it must never be committed, and it needs its own bucket (`infra/bootstrap`). It also needs short-lived keys from `aws configure export-credentials`, which run out after an hour.
3. **AWS CloudFormation:** AWS's own tool for the same job. AWS keeps the state, so there's no bucket to look after. But it only covers AWS, and later parts of this project use Azure.

## Decision

A mix, each for what it's best at:

- **Terraform** for everything that gets built: the network, the instance role and the server (`infra/envs/dev`), the ECR repositories (`infra/shared`) and the state bucket (`infra/bootstrap`).
- **The AWS CLI** for reading and checking (the `describe` lines, `/aws-cost-check`), and for the secrets. A password is typed into a prompt and stored with `aws ssm put-parameter`, so its value never passes through Terraform's files or its state.
- **AWS Systems Manager Parameter Store** keeps the secrets, and the server reads them with its own role.

No CloudFormation: one tool for what gets built, and it can cover the Azure parts too.

## Consequences

- Building is faster and repeatable. On 2026-11-06, `terraform apply` made all twelve resources of the dev environment in 32 seconds, the nginx page answered 67 seconds after that, and `destroy` removed everything in 32 seconds. Because of that, dev can be destroyed whenever it's not in use and costs nothing in between.
- The order is no longer remembered by hand: the references set it, and `destroy` goes the other way round.
- The server's permissions are written down in `infra/envs/dev/server.tf` and `infra/policies/pp-ec2-ssm-trust.json`, so a change to them is reviewed in a pull request.
- A change made in the console shows up in the next `plan`, and the next `apply` undoes it.
- New work: learning Terraform's language and each resource's argument names, keeping the state bucket safe (versioning and `prevent_destroy`), and getting fresh keys before each session.
- A change to `deploy/user-data.sh` only runs on a new server: the provider applies it in place, and cloud-init runs user data only at the first boot.
