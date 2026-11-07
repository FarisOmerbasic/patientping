# Infra

Terraform for PatientPing on AWS, in `us-east-1`. Each folder is one configuration with its own state, except `modules/network/`, a module that a configuration calls, and `policies/`.

| Folder | What it makes | Where its state is |
|---|---|---|
| `bootstrap/` | the state bucket `pp-tfstate-586631277130`: versioning, a public access block, a lifecycle rule for old versions, an HTTPS-only policy, and `prevent_destroy` | `bootstrap/terraform.tfstate` on the laptop, kept out of Git by `.gitignore` |
| `shared/` | the ECR repositories `patientping-api` and `patientping-web`, with scan on push and tags that can't be pushed twice (except `latest`) | `shared/terraform.tfstate` in the state bucket, with a lock file next to it while a plan or apply runs |
| `envs/dev/` | the dev environment, 12 resources. The network is `modules/network`, called with dev's values: the name `pp-dev`, the VPC's block `10.20.0.0/16`, and the subnet `10.20.1.0/24` in `us-east-1a`. The server: `patientping-dev`, a `t3.micro` on the newest Amazon Linux 2023 with an encrypted disk, a public IP, `deploy/user-data.sh` as its user data, and the role `pp-ec2-ssm` through an instance profile of the same name, for SSM. The server costs about $0.016 an hour while it's up (the instance and its public IPv4 address), the rest nothing, so the whole environment is destroyed when not in use. `apply` and `destroy` take about 30 seconds each | `dev/terraform.tfstate` in the state bucket, with a lock file next to it while a plan or apply runs |
| `modules/network/` | nothing by itself: a module with the network's eight resources, made by the configuration that calls it. The VPC, one public subnet with a route to an internet gateway, and the security group `pp-web` (TCP 80 in, everything out). The caller sets the name, the VPC's and the subnet's blocks and the zone, and gets back the IDs of the VPC, the subnet and the group | in the caller's state, under `module.network.` |
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

## Checks

None of these asks AWS anything, so they need no keys. From `infra/`:

```bash
terraform fmt -check -recursive
tflint --init
tflint --recursive --config "$PWD/.tflint.hcl"
```

and `terraform validate` in each configuration after its `terraform init`. `.tflint.hcl` turns on the AWS rules, which know AWS's own values, such as the instance types. `--config` needs the full path: with `--recursive`, tflint looks for `.tflint.hcl` in each folder it checks, and a folder without one gets only the built-in rules, without a message. Plain `tflint --recursive` passes `t3.micrro` with exit 0.

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
