# GitHub Actions jobs log in to AWS with the OIDC token GitHub signs for each job, so no AWS key is stored in GitHub.
# The provider makes AWS trust GitHub's tokens. Which repository and branch may take the role is the role's trust policy.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_ci" {
  name               = "gha-patientping-ci"
  assume_role_policy = file("${path.module}/../policies/gha-patientping-ci-trust.json")
  # The provider's ARN is typed into the JSON as text, so Terraform can't see the link. This gives it the order.
  depends_on = [aws_iam_openid_connect_provider.github]
}

# What the role may do: log in to ECR and push to the two repositories, nothing else.
resource "aws_iam_role_policy" "push_images" {
  name   = "gha-patientping-push-images"
  role   = aws_iam_role.github_ci.name
  policy = file("${path.module}/../policies/gha-patientping-ci-push.json")
}

# Policy below is for the deploy job, which is separate from the build job.
resource "aws_iam_role_policy" "deploy" {
  name   = "gha-patientping-deploy"
  role   = aws_iam_role.github_ci.name
  policy = file("${path.module}/../policies/gha-patientping-ci-deploy.json")
}
