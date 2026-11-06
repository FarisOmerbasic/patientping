# Infra

Terraform for PatientPing on AWS, in `us-east-1`. Each folder is one configuration with its own state.

| Folder | What it makes | Where its state is |
|---|---|---|
| `bootstrap/` | the state bucket `pp-tfstate-586631277130`: versioning, a public access block, a lifecycle rule for old versions, an HTTPS-only policy, and `prevent_destroy` | `bootstrap/terraform.tfstate` on the laptop, kept out of Git by `.gitignore` |
| `shared/` | the ECR repositories `patientping-api` and `patientping-web`, with scan on push and tags that can't be pushed twice (except `latest`) | `shared/terraform.tfstate` in the state bucket, with a lock file next to it while a plan or apply runs |
| `envs/dev/` | the dev environment, 12 resources. The network: the VPC `pp-dev` (`10.20.0.0/16`), one public subnet in `us-east-1a` with a route to an internet gateway, and the security group `pp-web` (TCP 80 in, everything out). The server: `patientping-dev`, a `t3.micro` on the newest Amazon Linux 2023 with an encrypted disk, a public IP, `deploy/user-data.sh` as its user data, and the role `pp-ec2-ssm` through an instance profile of the same name, for SSM. The server costs about $0.016 an hour while it's up (the instance and its public IPv4 address), the rest nothing, so the whole environment is destroyed when not in use. `apply` and `destroy` take about 30 seconds each | `dev/terraform.tfstate` in the state bucket, with a lock file next to it while a plan or apply runs | `dev/terraform.tfstate` in the state bucket, with a lock file next to it while a plan or apply runs |
| `policies/` | no Terraform: IAM policies written by hand, see its README | |

## Order

`bootstrap/` first, once. A configuration with the `s3` backend needs its bucket before its `terraform init`, so the bucket can't be made by a configuration that keeps its state in it. Then the others, each with `terraform init`, `plan` and `apply`.

## Credentials

The AWS provider can't use an `aws login` profile, so each terminal that runs Terraform first gets short-lived keys for the admin role:

```bash
eval "$(aws configure export-credentials --profile pp-admin --format env)"
echo "$AWS_CREDENTIAL_EXPIRATION"
```

The keys last about an hour, and only in that terminal. Without the `eval "$(` and `)"`, the command prints the secret key instead.

## If bootstrap's local state is lost

The bucket and everything in it is still there, only Terraform has forgotten that it made it. A `plan` would then want to create the bucket again, and fail on the name. Bring each resource back into a new state instead, from `bootstrap/`:

```bash
terraform import aws_s3_bucket.tfstate pp-tfstate-586631277130
terraform import aws_s3_bucket_versioning.tfstate pp-tfstate-586631277130
terraform import aws_s3_bucket_public_access_block.tfstate pp-tfstate-586631277130
terraform import aws_s3_bucket_lifecycle_configuration.tfstate pp-tfstate-586631277130
terraform import aws_s3_bucket_policy.tfstate pp-tfstate-586631277130
```

`terraform plan` should then say `No changes`.
