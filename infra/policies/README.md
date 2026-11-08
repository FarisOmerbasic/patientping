# Policies

IAM policies written by hand.

| File | What it is | Used by |
|---|---|---|
| `ecr-pull-and-s3-prefix.json` | an example of least privilege | nothing: it isn't attached anywhere |
| `pp-ec2-ssm-trust.json` | who may take the dev server's role `pp-ec2-ssm` | `envs/dev/server.tf`, through `file()` |
| `pp-ec2-read-params.json` | what the dev server's role may read from Parameter Store: the names under `/patientping/dev/` | `envs/dev/server.tf`, as an inline policy |
| `gha-patientping-ci-trust.json` | who may take the CI role `gha-patientping-ci`: a push to `main` in this repository | `shared/github-oidc.tf`, through `file()` |
| `gha-patientping-ci-push.json` | what the CI role may do: log in to ECR and push to the two repositories | `shared/github-oidc.tf`, as an inline policy |

## `ecr-pull-and-s3-prefix.json`

The permissions for one job: a server that pulls the image `patientping-api` from ECR, and reads and writes its files below `patientping/` in one S3 bucket. Nothing else.

| Statement | Allows | On |
|---|---|---|
| `ListThePatientpingPrefix` | `s3:ListBucket` | the bucket, only for keys below `patientping/` (the `s3:prefix` condition) |
| `ReadWritePatientpingFiles` | `s3:GetObject`, `s3:PutObject` | the objects below `patientping/` |
| `LogInToEcr` | `ecr:GetAuthorizationToken` | `*`: the call returns a login for the whole registry, so it can't be limited to one repository |
| `PullPatientpingApiImage` | `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` | the repository `patientping-api` only |

`111122223333` is the example account number from AWS's documentation, so the bucket `pp-sandbox-111122223333` and the repository's ARN are placeholders. Both have to be replaced before the policy is attached anywhere.

Left out on purpose: deleting files, reading older versions, listing the whole bucket or any other prefix, pushing images, and every other repository. In a versioned bucket, an overwrite with `PutObject` keeps the old version, so the job can't destroy data.

A listing has to ask for the prefix with its slash: `aws s3 ls s3://<bucket>/patientping/` is allowed, and `aws s3 ls s3://<bucket>/patientping` is denied.

## How `ecr-pull-and-s3-prefix.json` was checked

`validate-policy` checks how a policy is written (known call names, ARNs of the right shape, known condition keys, valid JSON), not what it allows. A `s3:ListBucket` on the objects' ARN instead of the bucket's passes it with no findings, and is still denied at the real call. So the file was also run through the policy simulator, which only evaluates the file and changes nothing in the account. Both need only read access (this project uses `--profile pp-readonly`):

```bash
aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY \
  --policy-document file://infra/policies/ecr-pull-and-s3-prefix.json

aws iam simulate-custom-policy \
  --policy-input-list "$(cat infra/policies/ecr-pull-and-s3-prefix.json)" \
  --action-names s3:GetObject s3:PutObject \
  --resource-arns arn:aws:s3:::pp-sandbox-111122223333/patientping/notes.txt arn:aws:s3:::pp-sandbox-111122223333/other/notes.txt \
  --query 'EvaluationResults[].ResourceSpecificResults[].[EvalResourceName,EvalResourceDecision]' --output table
```

Results on 2026-11-03: `validate-policy` returned no findings, and the simulator decided:

| Call | On | Decision |
|---|---|---|
| `s3:GetObject`, `s3:PutObject` | `patientping/notes.txt`, `patientping/sub/dir/x.txt` | `allowed` |
| `s3:GetObject`, `s3:PutObject` | `other/notes.txt`, `patientping-secrets/x.txt`, another account's bucket | `implicitDeny` |
| `s3:ListBucket` | the bucket, prefix `patientping/` | `allowed` |
| `s3:ListBucket` | the bucket, prefix `patientping`, `patientping-secrets/` or none | `implicitDeny` |
| `s3:DeleteObject`, `s3:GetObjectVersion`, `s3:DeleteObjectVersion` | `patientping/x.txt` | `implicitDeny` |
| `ecr:GetAuthorizationToken` | `*` | `allowed` |
| `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` | `patientping-api` | `allowed` |
| `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` | `patientping-web`, or `patientping-api` in another region | `implicitDeny` |
| `ecr:PutImage`, `ecr:InitiateLayerUpload` | `patientping-api` | `implicitDeny` |

`make lint` checks that every file in this folder is valid JSON (`jq empty`). The AWS checks need credentials, so they don't run in CI yet.

## `pp-ec2-ssm-trust.json`

The trust policy of the role `pp-ec2-ssm`. It says who may take the role on: the EC2 service, which then hands the role to a server through an instance profile of the same name. What the role may do is in three other policies. `AmazonSSMManagedInstanceCore`, which AWS maintains, lets the SSM agent on the server register with Systems Manager and open sessions, so the server needs no SSH port and no SSH key. `AmazonEC2ContainerRegistryPullOnly`, also AWS's, allows the ECR login and pulling images, and nothing else. `pp-ec2-read-params.json`, below, allows reading the dev parameters.

| Part | What it says |
|---|---|
| `"Principal": {"Service": "ec2.amazonaws.com"}` | who: the EC2 service |
| `"Action": "sts:AssumeRole"` | what: take the role on, and get its short-lived credentials |
| no `Resource` | a trust policy sits on the role, so the role is its resource. A `Resource` line is an error here |

The server got the role's credentials from its metadata service, so no key was ever on its disk: on the server, `ls ~/.aws` found nothing, and `aws sts get-caller-identity` answered `assumed-role/pp-ec2-ssm/i-...`.

A trust policy is checked with the resource type for trust policies, not as an identity policy:

```bash
aws accessanalyzer validate-policy --policy-type RESOURCE_POLICY \
  --validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument \
  --policy-document file://infra/policies/pp-ec2-ssm-trust.json
```

It returned no findings. A copy with a `Resource` line got `ROLE_TRUST_POLICY_SYNTAX_ERROR_RESOURCE`. Like the validator above, it checks the shape: it also passed the service name written as `EC2.amazonaws.com`, which the file now spells in lower case, as AWS's documentation does.

## `pp-ec2-read-params.json`

What the dev server's role `pp-ec2-ssm` may read from Parameter Store, where the passwords are kept as `SecureString`s. It's an inline policy (`aws_iam_role_policy`) in `envs/dev/server.tf`, so it belongs to the role and is deleted with it.

| Statement | Allows | On |
|---|---|---|
| `ReadPatientpingDevParameters` | `ssm:GetParameter`, `ssm:GetParametersByPath` | the path `/patientping/dev` and every name under it |

There are two ARNs because the two calls are checked against different resources. `GetParameter` is checked against the parameter's own name, which `parameter/patientping/dev/*` matches. `GetParametersByPath` is checked against the path itself, `parameter/patientping/dev`, which the `/*` doesn't match.

The passwords are encrypted with the account's default key `aws/ssm`. Its key policy lets every principal in the account decrypt through SSM, so the role needs no `kms:Decrypt` of its own. It also means that any role that may call `ssm:GetParameter` on these names can read them, including AWS's `ReadOnlyAccess`, which allows `ssm:Get*`. A key of the project's own, whose policy names only this role, would narrow that.

`validate-policy --policy-type IDENTITY_POLICY` returned no findings. The policy simulator, on 2026-11-08:

| Call | On | Decision |
|---|---|---|
| `ssm:GetParameter` | `/patientping/dev/db_password`, `/patientping/dev/mssql_sa_password` | `allowed` |
| `ssm:GetParametersByPath` | `/patientping/dev` | `allowed` |
| `ssm:GetParameter` | `/patientping/prod/db_password`, `/patientping/development/x`, `/DATABASE_URL` | `implicitDeny` |
| `ssm:PutParameter`, `ssm:DeleteParameter` | `/patientping/dev/db_password` | `implicitDeny` |

Before the second ARN was added, `GetParametersByPath` on `/patientping/dev` was `implicitDeny`.

## `gha-patientping-ci-trust.json`

The trust policy of the role `gha-patientping-ci`. It says who may take the role on: a GitHub Actions job from this repository, on a push to `main`, with the OIDC token GitHub signs for that job. The role is in `shared/github-oidc.tf`, next to the OIDC provider that makes AWS trust GitHub's tokens.

| Part | What it says |
|---|---|
| `"Principal": {"Federated": "arn:aws:iam::586631277130:oidc-provider/token.actions.githubusercontent.com"}` | who: a token checked by the account's OIDC provider for GitHub Actions |
| `"Action": "sts:AssumeRoleWithWebIdentity"` | what: trade that token for the role's short-lived keys |
| `token.actions.githubusercontent.com:aud` is `sts.amazonaws.com` | the token was made for AWS STS |
| `token.actions.githubusercontent.com:sub` is `repo:FarisOmerbasic@154029097/patientping@1413694710:ref:refs/heads/main` | the token comes from this repository, for a push to `main`. Every repository on GitHub gets its tokens from the same issuer, so without this line any of them could take the role |

Both keys are under one `StringEquals`, so both must match, letter for letter. The `sub` has the immutable form that GitHub gives repositories made after 2026-07-15: the owner and the repository each carry their number, so a new repository with the same name doesn't match. `gh api repos/FarisOmerbasic/patientping/actions/oidc/customization/sub` shows the prefix (`sub_claim_prefix`). A pull request's token ends with `:pull_request` and another branch's with `:ref:refs/heads/<branch>`, so both are refused: the `image` job, run once on a pull request as a test, failed with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. A job with an `environment:` gets yet another `sub`.

The provider's ARN is typed into the file as text, so Terraform can't see the link, and the role's block has a `depends_on` on the provider.

Checked like `pp-ec2-ssm-trust.json`, with `--validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument`. It returns one SUGGESTION, `CONFIRM_AUDIENCE_CLAIM_TYPE`: `aud` holds one value, so it must not get a qualifier like `ForAnyValue:`, and it has none. Without the `sub` line, the same check gives a SECURITY_WARNING, `MISSING_GITHUB_REPO_CONDITION_KEY`. Like the other checks, it reads the shape: a `sub` with a wrong digit passes it, and only a real run shows the mistake.

## `gha-patientping-ci-push.json`

What the role `gha-patientping-ci` may do. It's an inline policy (`aws_iam_role_policy`), so it belongs to the role and is deleted with it.

| Statement | Allows | On |
|---|---|---|
| `LogInToEcr` | `ecr:GetAuthorizationToken` | `*`: the call returns a login for the whole registry, so it can't be limited to one repository |
| `PushPatientpingImages` | `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`, `ecr:BatchGetImage` | the repositories `patientping-api` and `patientping-web` in `us-east-1` |

The six actions are the ones on AWS's page *IAM permissions for pushing an image*. `ecr:BatchGetImage` also lets the job's `docker manifest inspect` find out whether a `sha-` tag is already published.

`validate-policy --policy-type IDENTITY_POLICY` returned no findings. The policy simulator on the role itself evaluates the role's real policies and changes nothing:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::586631277130:role/gha-patientping-ci \
  --action-names ecr:PutImage ecr:BatchDeleteImage \
  --resource-arns arn:aws:ecr:us-east-1:586631277130:repository/patientping-api \
  --query 'EvaluationResults[].ResourceSpecificResults[].[EvalResourceName,EvalResourceDecision]' --output table
```

| Call | On | Decision |
|---|---|---|
| `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:BatchGetImage` | `patientping-api`, `patientping-web` | `allowed` |
| `ecr:GetAuthorizationToken` | `*` | `allowed` |
| `ecr:PutImage` | another repository, or `patientping-api` in `eu-west-1` | `implicitDeny` |
| `ecr:BatchDeleteImage`, `ecr:DeleteRepository`, `ecr:SetRepositoryPolicy` | `patientping-api` | `implicitDeny` |
| `s3:ListAllMyBuckets`, `iam:CreateUser`, `sts:AssumeRole` | `*` | `implicitDeny` |
