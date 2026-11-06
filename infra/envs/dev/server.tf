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

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "pp-ec2-ssm"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/../../../deploy/user-data.sh")

  tags = {
    Name = "patientping-dev"
  }
}
