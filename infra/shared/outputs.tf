output "ci_role_arn" {
  description = "The ARN of the GitHub Actions role"
  value       = aws_iam_role.github_ci.arn
}
