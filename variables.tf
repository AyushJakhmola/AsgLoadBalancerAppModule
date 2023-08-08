variable "environment" {
  default = "staging"
}

variable "application" {
  default = "shortener"
}

variable "application_type" {
  default = "guru"
}

variable "vpc_id" {
  default = "vpc-0c6e142227f7755c1"
}

variable "region" {
  default = ""
}

variable "tags" {
  type = map(string)
  default = {
    Managed_by = "Squareops"
  }
}

variable "load_balancing" {
  default = false
}

variable "create_efs" {
  default = false
}

variable "instance_subnet" {
  default = "private"
}

variable "instance_ami" {
  default = ""
}

variable "user_data" {
  default = ""
}

variable "server_configuration" {
  description = "Configurations for instances managged by autodcaling"
  type        = map(string)
  default = {
    instance_type    = "t3.medium"
    volume_size      = 8
    volume_type      = "gp3"
    min_required     = 0
    max_required     = 1
    desired_capacity = 1
  }
}

