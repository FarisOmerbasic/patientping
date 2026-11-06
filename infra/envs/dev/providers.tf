provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "patientping"
      ManagedBy = "terraform"
    }
  }
}
