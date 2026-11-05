resource "aws_ecr_repository" "api" {
  name = "patientping-api"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "web" {
  name = "patientping-web"

  image_scanning_configuration {
    scan_on_push = true
  }
}