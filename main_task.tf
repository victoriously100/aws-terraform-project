/*
This is my main infrastructure
Summary
We have a VPC with 256 available IPs, with an Internet Gateway and two public Subnets in two separate AZs, two route tables with associations to each Subnets
and access to Public. A Security Group with HTTP and HTTPS Public access and SSH access to my Public IP address.
Two Ubuntu instances with each in one of the Public subnets within the VPC and User Data to install Apache server.
An ALB with Target Groups targeting the two Instances
We have an S3 Bucket with host static site enabled and created a Cloudfront distribuition pointing at the S3 bucket endpoint
It has ACM Certs in London and N.Virginia for the ALB and CloudFront with automated DNS validation which creates 2 CNAME record in Hosted Zone
We have two Route 53 A records for ALB and Cloudfront which we later used as Primary and Secondary on an Route 53 Health Check Failover policy
*/
# Terraform configuration for AWS infrastructure

provider "aws" {
  alias   = "eu_west_2"
  region  = var.aws_region_eu
  profile = var.aws_profile
}

provider "aws" {
  alias   = "us_east_1"
  region  = var.aws_region_us
  profile = var.aws_profile
}

# VPC
resource "aws_vpc" "demo_test" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.vpc_name }
}

# Internet Gateway
resource "aws_internet_gateway" "demo_igw" {
  vpc_id = aws_vpc.demo_test.id
  tags   = { Name = var.igw_name }
}

# Two Public Subnets
/*
resource "aws_subnet" "demo_pub_sub1" {
  vpc_id                  = aws_vpc.demo_test.id
  cidr_block              = var.public_subnet_1_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_1
  tags                    = { Name = var.public_subnet_1_name }
}
resource "aws_subnet" "demo_pub_sub2" {
  vpc_id                  = aws_vpc.demo_test.id
  cidr_block              = var.public_subnet_2_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_2
  tags                    = { Name = var.public_subnet_2_name }
}
*/
# Two Public Subnets
resource "aws_subnet" "demo_pub_sub" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.demo_test.id
  cidr_block              = var.public_subnets[count.index].cidr_block  # Fix attribute name
  map_public_ip_on_launch = true
  availability_zone       = var.public_subnets[count.index].availability_zone  # Fix attribute name
  tags                    = { Name = var.public_subnets[count.index].subnet_name }  # Fix attribute name
}


# Route Tables with routes as seperate resources
/*
resource "aws_route_table" "pub_rt1" {
  vpc_id = aws_vpc.demo_test.id
  tags = { Name = var.route_table_1_name }
}

resource "aws_route" "pub_route1" { # created the route as a resource of its own
  route_table_id = aws_route_table.pub_rt1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.demo_igw.id
}

resource "aws_route_table_association" "pub_assoc1" {
  subnet_id = aws_subnet.demo_pub_sub1.id
  route_table_id = aws_route_table.pub_rt1.id
}

resource "aws_route_table" "pub_rt2" {
  vpc_id = aws_vpc.demo_test.id
  tags = { Name = var.route_table_2_name}
}

resource "aws_route" "pub_route2" { # created the route as a resource of its own
  route_table_id = aws_route_table.pub_rt2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.demo_igw.id
}

resource "aws_route_table_association" "pub_assoc2" {
  subnet_id = aws_subnet.demo_pub_sub2.id
  route_table_id = aws_route_table.pub_rt2.id
}

*/

# Route Tables and Associations (Using for_each)
resource "aws_route_table" "pub_rt" {
  for_each = var.public_route_tables
  vpc_id   = aws_vpc.demo_test.id
  tags     = { Name = each.value }
}

resource "aws_route" "pub_route" {
  for_each               = aws_route_table.pub_rt
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.demo_igw.id
}

resource "aws_route_table_association" "pub_assoc" {
  for_each       = aws_route_table.pub_rt
  subnet_id      = element(aws_subnet.demo_pub_sub[*].id, index(keys(var.public_route_tables), each.key))
  route_table_id = each.value.id
}


# Security Group
resource "aws_security_group" "demo_sg" {
  vpc_id = aws_vpc.demo_test.id
  
  dynamic "ingress" { # HTTP & HTTPS inbound traffic
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value["from_port"]
      to_port     = ingress.value["to_port"]
      protocol    = ingress.value["protocol"]
      cidr_blocks = ingress.value["cidr_blocks"]
    }
  }

  egress { # Outbound traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch Template
resource "aws_launch_template" "test_launch_temp" {
  name_prefix   = var.launch_template_name
  image_id      = var.ami_id # Ubuntu AMI variable
  instance_type = var.instance_type
  key_name      = var.key_name#Key Pem with perm of 400
  vpc_security_group_ids = [aws_security_group.demo_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              echo "Welcome to my ASG instance" > /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-instance"
    }
  }
}

# Auto Scaling Group (ASG)
resource "aws_autoscaling_group" "demo_asg" {
  launch_template {
    id      = aws_launch_template.test_launch_temp.id
    version = "$Latest"
  }

  vpc_zone_identifier = aws_subnet.demo_pub_sub[*].id
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity

  tag {
    key                 = "Name"
    value               = "asg-instance"
    propagate_at_launch = true
  }
}

# Application Load Balancer
resource "aws_lb" "demo_alb" {
  name               = "demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_sg.id]
  subnets            = aws_subnet.demo_pub_sub[*].id
}

# Target Group
resource "aws_lb_target_group" "demo_tg" {
  name     = "demo-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo_test.id
}

# ASG Target Group Attachment
resource "aws_autoscaling_attachment" "asg_tg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.demo_asg.id
  lb_target_group_arn    = aws_lb_target_group.demo_tg.arn
}

# ALB Listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.demo_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_tg.arn
  }
}
#added S3 Cloudfront, secondary part from here

# S3 Bucket
resource "aws_s3_bucket" "web_bucket" {
  bucket = "web.seeksdevstraining.com"
}

resource "aws_s3_bucket_website_configuration" "web_bucket_website" {
  bucket = aws_s3_bucket.web_bucket.id

  index_document {
    suffix = "index.html"
  }
}
# Enable Block Public Access to S3
resource "aws_s3_bucket_public_access_block" "web_bucket_block" {
  bucket                  = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "web_bucket_policy" {
  bucket = aws_s3_bucket.web_bucket.id

/*
# Use these objects to upload html file with maintenance image dynamically
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.web_bucket.id
  key    = "index.html"
  source = "~/codes/S3/Custom Error/index.html"  # Path updated
  content_type = "text/html"
}

resource "aws_s3_object" "image_file" {
  bucket = aws_s3_bucket.web_bucket.id
  key    = "images/static.png"  # Name changed to static.png
  source = "~/codes/S3/Custom Error/static.png"  # Path updated
  content_type = "image/png"
}
*/
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::web.seeksdevstraining.com/*"
    }
  ]
}
POLICY
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.web_bucket.bucket_regional_domain_name #aws_s3_bucket.web_bucket.website_endpoint
    origin_id   = "web.seeksdevstraining.com"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "allow-all"
    target_origin_id       = "web.seeksdevstraining.com"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.cloudfront_cert.arn
    ssl_support_method             = "sni-only" # a standard to associate an ACM cert to CF
  }
}

variable "cloudfront_certificate_arn" {
  description = "ARN of the CloudFront ACM certificate"
  default     = ""
}

# ACM Certificates
resource "aws_acm_certificate" "alb_cert" {
  domain_name       = var.alb_cert_domain
  validation_method = "DNS"
  provider         = aws.eu_west_2 # London 
}

resource "aws_acm_certificate" "cloudfront_cert" {
  domain_name       = var.cloudfront_cert_domain
  validation_method = "DNS"
  provider         = aws.us_east_1 # N.Virginia
}

# Automate DNS validation for ACM Certificates - this loops through domain_validation_options (dvo) to create dynamic Route 53 DNS records to validate the ACM certs
resource "aws_route53_record" "alb_cert_validation" {
  for_each = { for dvo in aws_acm_certificate.alb_cert.domain_validation_options : dvo.domain_name => dvo }

  zone_id = var.route53_zone_id # Your Route 53 Hosted Zone ID
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 60
  records = [each.value.resource_record_value]
}

resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = { for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : dvo.domain_name => dvo }

  zone_id = var.route53_zone_id # Your Route 53 Hosted Zone ID
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 60
  records = [each.value.resource_record_value]
}

# ALB Listener HTTPS
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.demo_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_tg.arn
  }
}

# Route 53 Records
resource "aws_route53_record" "cloudfront_dns" {
  zone_id = var.route53_zone_id
  name    = "web.seeksdevstraining.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "alb_dns" {
  zone_id = var.route53_zone_id #my Route 53 Hosted Zone ID
  name    = "web.seeksdevstraining.com"
  type    = "A"
  alias {
    name                   = aws_lb.demo_alb.dns_name
    zone_id                = aws_lb.demo_alb.zone_id
    evaluate_target_health = true  
  }
  lifecycle {
    ignore_changes = [alias]
  }
}

# Route 53 Health Check
resource "aws_route53_health_check" "demo_server_check" {
  fqdn              = "web.seeksdevstraining.com" #listening to monitor my domain name listed using fqdn
  port              = 80
  type              = "HTTP"
  failure_threshold = 3
  request_interval  = 30
  tags = {
    Name = "demo-test-health-check"
  }
}

# Route 53 Failover Policy
resource "aws_route53_record" "failover_record_primary" {
  zone_id = var.route53_zone_id
  name    = "web.seeksdevstraining.com"
  type    = "A"
  set_identifier = "Primary-ALB"
  failover_routing_policy {
    type = "PRIMARY"
  }
  alias {
    name                   = aws_lb.demo_alb.dns_name
    zone_id                = aws_lb.demo_alb.zone_id
    evaluate_target_health = true
  }
  health_check_id = aws_route53_health_check.demo_server_check.id
}

resource "aws_route53_record" "failover_record_secondary" {
  zone_id = var.route53_zone_id
  name    = "web.seeksdevstraining.com"
  type    = "A"
  set_identifier = "Secondary-CloudFront"
  failover_routing_policy {
    type = "SECONDARY"
  }
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}
