# ADR 0001: Sign in to AWS with `aws login` and role profiles, not access keys

- **Status:** accepted
- **Date:** 2026-10-20

## Context

The AWS CLI needs credentials. The usual first setup is an IAM user with long-lived access keys in `~/.aws/credentials`. An access key works until someone deletes it, so a key that leaks, in a commit, a screenshot or a log, can be used for months.

Scripts and an AI assistant run commands against this account, so the credentials they use should have as few rights and as short a life as possible.

Constraints: one person, and an account on the AWS free plan, which can't use AWS Organizations.

## Options considered

1. **IAM user with access keys:** simple, and works with every tool. But the keys are long-lived secrets on disk, and every tool that reads them gets the user's full rights.
2. **IAM user with MFA, `aws login` and role profiles:** `aws login` gives short-lived credentials after a sign-in with MFA. Two profiles assume roles through STS: `pp-readonly` (read only) and `pp-admin` (changes). No key is stored. Works on the free plan.
3. **IAM Identity Center:** the usual way for people to sign in to AWS, with short-lived credentials and permission sets. It needs AWS Organizations, which this account can't use on the free plan.

## Decision

Option 2: `aws login` for short-lived credentials, and the role profiles `pp-readonly` and `pp-admin`. Day-to-day work, scripts and the AI assistant use `pp-readonly`, so a mistake can't change anything. Changes go through `pp-admin`, on purpose.

## Consequences

- No long-lived AWS key exists on disk or in the repo. A leaked credential expires on its own.
- Each role has its own permissions policy, and its trust policy limits who may assume it.
- `aws login` has to be run again when the session ends.
- Every change in the account needs a deliberate switch to `pp-admin`.
- `aws sts get-caller-identity --profile pp-readonly` shows which role a command runs as.
- Follow-up: move to IAM Identity Center after upgrading from the free plan, in a new ADR that supersedes this one. CI will get AWS access through OIDC, also without stored keys.
