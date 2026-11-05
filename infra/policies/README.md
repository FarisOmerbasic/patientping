# Policies

IAM policies written by hand. `ecr-pull-and-s3-prefix.json` is an example of least privilege and isn't attached to anything. `pp-ec2-ssm-trust.json` was the trust policy of the role `pp-ec2-ssm`, made and deleted again on 2026-11-05.

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

The trust policy of the role `pp-ec2-ssm`. It says who may take the role on: the EC2 service, which then hands the role to a server through an instance profile of the same name. What the role may do is a separate policy, `AmazonSSMManagedInstanceCore`, which AWS maintains. It lets the SSM agent on the server register with Systems Manager and open sessions, so the server needs no SSH port and no SSH key.

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
