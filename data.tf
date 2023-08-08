data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_region" "current" {}

data "aws_subnets" "instance_subnet" {
  filter {
    name   = "tag:Subnet-group"
    values = ["${var.instance_subnet}"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Subnet-group"
    values = ["public"]
  }
}

data "aws_ami" "amis" {
  most_recent = true
  owners      = ["self"]
  tags = {
    Name = format("%s-%s-%s-AMI", var.environment, var.application_type, var.application)
  }
}