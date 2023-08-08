# Server security group 
module "server_sg" {
  count               = var.load_balancing ? 1 : 0
  source              = "terraform-aws-modules/security-group/aws"
  version             = "5.1.0"
  name                = format("%s-%s-%s-sg", var.environment, var.application_type, var.application)
  vpc_id              = data.aws_vpc.selected.id
  ingress_cidr_blocks = [data.aws_vpc.selected.cidr_block]
  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.lb_sg[0].security_group_id
    },
    {
      rule                     = "https-443-tcp"
      source_security_group_id = module.lb_sg[0].security_group_id
    },
  ]
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "outbound rule"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

module "public_server_sg" {
  count               = var.load_balancing ? 0 : 1
  source              = "terraform-aws-modules/security-group/aws"
  version             = "5.1.0"
  name                = format("%s-%s-%s-sg", var.environment, var.application_type, var.application)
  vpc_id              = data.aws_vpc.selected.id
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "outbound rule"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}



# Application Autoscaling group
module "asg" {
  source = "terraform-aws-modules/autoscaling/aws"
  name   = format("%s-%s-%s-asg", var.environment, var.application_type, var.application)
  version             = "6.10.0"
  min_size            = var.server_configuration.min_required
  max_size            = var.server_configuration.max_required
  user_data           = var.user_data
  enabled_metrics           = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
  desired_capacity    = var.server_configuration.desired_capacity
  health_check_type   = "EC2"
  vpc_zone_identifier = data.aws_subnets.instance_subnet.ids

  # Launch template 
  launch_template_name   = format("%s-%s-%s-asg-template", var.environment, var.application_type, var.application)
  update_default_version = true

  image_id = data.aws_ami.amis.image_id
  # image_id = var.instance_ami
  instance_type               = var.server_configuration.instance_type
  enable_monitoring           = true
  target_group_arns           = var.load_balancing ? [module.nlb[0].target_group_arns[0], module.nlb[0].target_group_arns[1]] : null
  create_iam_instance_profile = true
  iam_role_name               = format("%s-%s-%s-role", var.environment, var.application_type, var.application)
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonS3ReadOnlyAccess       = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    AmazonSSMFullAccess          = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
    CloudWatchAgentAdminPolicy   = "arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy"
    CloudWatchAgentServerPolicy  = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  scaling_policies = {
    cpu_utilization_policy = {
      policy_type               = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
          # resource_label         = "MyLabel"
        }
        target_value = 50.0
      }
    }
  }

  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      no_device   = 0 #?
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = var.server_configuration.volume_size
        volume_type           = var.server_configuration.volume_type
      }
    }
  ]

  network_interfaces = [
    {
      delete_on_termination = true
      security_groups       = var.load_balancing ? [module.server_sg[0].security_group_id] : [module.public_server_sg[0].security_group_id]
    }
  ]

  tags = {
    Environment      = var.environment
  }
}

# # security group for alb 
module "lb_sg" {
  count  = var.load_balancing ? 1 : 0
  source = "terraform-aws-modules/security-group/aws"

  name        = format("%s-%s-%s-sg", var.environment, var.application_type, var.application)
  description = "Security group for application service"
  vpc_id      = var.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "outbound rule"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Environment      = var.environment
  }
}

module "nlb" {

  source             = "terraform-aws-modules/alb/aws"
  count              = var.load_balancing ? 1 : 0
  name               = format("%s-%s-%s-nlb", var.environment, var.application_type, var.application)
  vpc_id             = data.aws_vpc.selected.id
  load_balancer_type = "network"
  subnets            = data.aws_subnets.public.ids

  target_groups = [
    {
      backend_protocol = "TCP"
      backend_port     = 443
    },
    {
      backend_protocol = "TCP"
      backend_port     = 80
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "TCP"
      target_group_index = 0
    },
    {
      port               = 443
      protocol           = "TCP"
      target_group_index = 1
    }
  ]

  tags = {
    Environment      = var.environment
  }
}

# EFS mounting

module "efs" {
  source        = "terraform-aws-modules/efs/aws"
  name          = format("%s-%s-%s-efs", var.environment, var.application_type, var.application)
  count         = var.create_efs ? 1 : 0
  encrypted     = true
  attach_policy = true
  throughput_mode                 = "elastic"
  enable_backup_policy            = true
  security_group_vpc_id           = data.aws_vpc.selected.id
  provisioned_throughput_in_mibps = 256

  mount_targets = {
    "us-east-1a" = {
      subnet_id = data.aws_subnets.public.ids[0]
    }
    "us-east-1b" = {
      subnet_id = data.aws_subnets.public.ids[1]
    }
  }

  security_group_rules = {
    vpc = {
      cidr_blocks = ["10.10.0.0/16"]
    }
  }

  tags = {
    Environment      = var.environment
  }
}
