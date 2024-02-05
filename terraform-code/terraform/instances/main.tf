

#----------------------------------------------------------
# ACS730 - Week 3 - Terraform Introduction
#
# Build EC2 Instances
#
#----------------------------------------------------------

#  Define the provider
provider "aws" {
  region = "us-east-1"
}

# Data source for AMI id
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


# Data source for availability zones in us-east-1
data "aws_availability_zones" "available" {
  state = "available"
}

# Data block to retrieve the default VPC id
data "aws_vpc" "default" {
  default = true
}

# Data block to retrieve aws subnets in default vpc
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}


# Data block to retrieve iam instance profile
data "aws_iam_instance_profile" "lab_instance_profile" {
  name = "LabInstanceProfile"
}

# Define tags locally
locals {
  default_tags = merge(module.globalvars.default_tags, { "env" = var.env })
  prefix       = module.globalvars.prefix
  name_prefix  = "${local.prefix}-${var.env}"
}

# Retrieve global variables from the Terraform module
module "globalvars" {
  source = "../../modules/globalvars"
}

# Reference subnet provisioned by 01-Networking 
resource "aws_instance" "my_amazon" {
  ami                         = data.aws_ami.latest_amazon_linux.id
  instance_type               = lookup(var.instance_type, var.env)
  key_name                    = aws_key_pair.my_key.key_name
  vpc_security_group_ids      = [aws_security_group.my_sg.id]
  associate_public_ip_address = false
  iam_instance_profile        = data.aws_iam_instance_profile.lab_instance_profile.name

  user_data = file("install_httpd.sh.tpl")

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-Amazon-Linux"
    }
  )
}


# Adding SSH key to Amazon EC2
resource "aws_key_pair" "my_key" {
  key_name   = local.name_prefix
  public_key = file("${local.name_prefix}.pub")
}

# Security Group
resource "aws_security_group" "my_sg" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "SSH from everywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
   ingress {
    description      = "SSH from everywhere"
    from_port        = 8081
    to_port          = 8081
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
   ingress {
    description      = "SSH from everywhere"
    from_port        = 8082
    to_port          = 8082
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
   ingress {
    description      = "SSH from everywhere"
    from_port        = 8083
    to_port          = 8083
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-sg"
    }
  )
}

# Elastic IP
resource "aws_eip" "static_eip" {
  instance = aws_instance.my_amazon.id
  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-eip"
    }
  )
}




# Create ECR repo


resource "aws_ecr_repository" "my_ecr_app_repo" {
  name = "${local.name_prefix}-app"
  image_tag_mutability = "MUTABLE"

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-app"
    }
  )
}

resource "aws_ecr_repository" "my_ecr_db_repo" {
  name = "${local.name_prefix}-db"
  image_tag_mutability = "MUTABLE"

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-db"
    }
  )
}




# Create a security group for the ALB
resource "aws_security_group" "alb_sg" {
  name        = "allow_lb_traffic"
  description = "Allow app-lb inbound traffic"
  vpc_id      = data.aws_vpc.default.id



  # Allow incoming traffic on port 80
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outgoing traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  
  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-alb-sg"
    }
  )
}

# Create the Application Load Balancer
resource "aws_lb" "app-lb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnet_ids.default.ids
}

# Define target group for the applications
resource "aws_lb_target_group" "app-lb-tg" {
  name     = "app-lb-target-group"
  port     = 80 
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Register targets to the target group
resource "aws_lb_target_group_attachment" "app1" {
  target_group_arn = aws_lb_target_group.app-lb-tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 8081
}

resource "aws_lb_target_group_attachment" "app2" {
  target_group_arn = aws_lb_target_group.app-lb-tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 8082
}


resource "aws_lb_target_group_attachment" "app3" {
  target_group_arn = aws_lb_target_group.app-lb-tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 8083
}

# Create ALB listener with rules to route traffic to different ports based on paths


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app-lb.arn
  port              = 80
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app-lb-tg.arn

  }
   
}
