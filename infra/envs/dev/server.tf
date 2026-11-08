# The newest Amazon Linux 2023 image, read again at every plan. When AWS publishes a new one,
# the next plan replaces a running server (a new ami forces it). That's fine for dev, which is
# destroyed when not in use. Revisit once the server keeps data on its disk.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "pp-ec2-ssm"
  assume_role_policy = file("${path.module}/../../policies/pp-ec2-ssm-trust.json")
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# What the deploy needs on the server, nothing more: pull the images (the ECR login and the
# pull, no push, no listing) and read the dev parameters. Every program that runs as root on
# the server can use these keys.
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy" "read_params" {
  name   = "pp-ec2-read-params"
  role   = aws_iam_role.ec2_ssm.id
  policy = file("${path.module}/../../policies/pp-ec2-read-params.json")
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "pp-ec2-ssm"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = module.network.subnet_id
  vpc_security_group_ids      = [module.network.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/../../../deploy/user-data.sh")

  root_block_device {
    encrypted   = true
    volume_size = 20
    volume_type = "gp3"
  }

  # Only IMDSv2, whatever the AMI allows: a request needs a session token first.
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "patientping-dev"
  }
}
