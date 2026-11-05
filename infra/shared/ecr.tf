# Tags can't be pushed twice, so a sha-<commit> tag always names the same image.
# Only latest may move.
resource "aws_ecr_repository" "api" {
  name                 = "patientping-api"
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "latest"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "web" {
  name                 = "patientping-web"
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  tags = {
    Component = "web"
  }

  image_tag_mutability_exclusion_filter {
    filter      = "latest"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}
