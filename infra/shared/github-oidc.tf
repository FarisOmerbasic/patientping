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

resource "aws_iam_role_policy" "push_images" {
  name   = "gha-patientping-push-images"
  role   = aws_iam_role.github_ci.name
  policy = file("${path.module}/../policies/gha-patientping-ci-push.json")
}