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
provider "aws" {
  alias   = "eu_west_2"
  region  = "eu-west-2"
  profile = "default"
}
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "default"
}

# VPC
resource "aws_vpc" "demo_test" {
  cidr_block = "10.0.0.0/24" #256 IPs CIDR range
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = { Name = "demo-test" }
}

# Internet Gateway
resource "aws_internet_gateway" "demo_igw" {
  vpc_id = aws_vpc.demo_test.id
  tags = { Name = "demo-igw" }
}

# Two Public Subnets
resource "aws_subnet" "demo_pub_sub1" {
  vpc_id = aws_vpc.demo_test.id
  cidr_block = "10.0.0.0/25" #128 IPs
  map_public_ip_on_launch = true
  availability_zone = "eu-west-2a"
  tags = { Name = "demo-pub-sub1" }
}

resource "aws_subnet" "demo_pub_sub2" {
  vpc_id = aws_vpc.demo_test.id
  cidr_block = "10.0.0.128/25" #128 IPs
  map_public_ip_on_launch = true
  availability_zone = "eu-west-2b"
  tags = { Name = "demo-pub-sub2" }
}

# Route Tables with routes as seperate resources
resource "aws_route_table" "pub_rt1" {
  vpc_id = aws_vpc.demo_test.id
  tags = { Name = "public-route-table-1" }
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
  tags = { Name = "public-route-table-2" }
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

# Security Group
resource "aws_security_group" "demo_sg" {
  vpc_id = aws_vpc.demo_test.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["188.29.107.168/32"] #["192.168.0.32/32"]
  }/* Only my exact IP should be selected
      I tried to automate the pulling of this IP but couldn't tho I have a manual way add public at home network
    */
  ingress { # HTTP inbound traffic
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { # HTTPS inbound traffic 
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { # Outbound traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1" #all ports
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Two EC2 Instances in both Subnets
resource "aws_instance" "demo_instance1" {
  ami           = "ami-091f18e98bc129c4e" # Ubuntu AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.demo_pub_sub1.id
  vpc_security_group_ids = [aws_security_group.demo_sg.id]
  key_name      = "aws-demo-test" #Key Pem with perm of 400

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              echo "Welcome to my Ubuntu page" > /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
  tags = { Name = "demo-instance1" }
}
  
resource "aws_instance" "demo_instance2" {
  ami           = "ami-091f18e98bc129c4e"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.demo_pub_sub2.id
  vpc_security_group_ids = [aws_security_group.demo_sg.id]
  key_name      = "aws-demo-test"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              echo "Hi this is 2nd Ubuntu page" > /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
  tags = { Name = "demo-instance2" }
}

# Application Load Balancer
resource "aws_lb" "demo_alb" {
  name               = "demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_sg.id]
  subnets            = [aws_subnet.demo_pub_sub1.id, aws_subnet.demo_pub_sub2.id]
}

# Target Group
resource "aws_lb_target_group" "demo_tg" {
  name     = "demo-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo_test.id
}
# Attach the instances to the TG
resource "aws_lb_target_group_attachment" "demo_attach1" {
  target_group_arn = aws_lb_target_group.demo_tg.arn
  target_id        = aws_instance.demo_instance1.id
  port            = 80
}

resource "aws_lb_target_group_attachment" "demo_attach2" {
  target_group_arn = aws_lb_target_group.demo_tg.arn
  target_id        = aws_instance.demo_instance2.id
  port            = 80
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
resource "aws_s3_bucket_policy" "web_bucket_policy" {
  bucket = aws_s3_bucket.web_bucket.id

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
    origin_id   = "S3-web-seeksdevstraining"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "allow-all"
    target_origin_id       = "S3-web-seeksdevstraining"
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
  domain_name       = "*.seeksdevstraining.com"
  validation_method = "DNS"
  provider         = aws.eu_west_2 # London 
}

resource "aws_acm_certificate" "cloudfront_cert" {
  domain_name       = "web.seeksdevstraining.com"
  validation_method = "DNS"
  provider         = aws.us_east_1 # N.Virginia
}

# Automate DNS validation for ACM Certificates - this loops through domain_validation_options (dvo) to create dynamic Route 53 DNS records to validate the ACM certs
resource "aws_route53_record" "alb_cert_validation" {
  for_each = { for dvo in aws_acm_certificate.alb_cert.domain_validation_options : dvo.domain_name => dvo }

  zone_id = "Z03534432K2YUY96QKS9O"  # Your Route 53 Hosted Zone ID
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 60
  records = [each.value.resource_record_value]
}

resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = { for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : dvo.domain_name => dvo }

  zone_id = "Z03534432K2YUY96QKS9O"  # Your Route 53 Hosted Zone ID
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
  zone_id = "Z03534432K2YUY96QKS9O"
  name    = "web.seeksdevstraining.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "alb_dns" {
  zone_id = "Z03534432K2YUY96QKS9O" # my Route 53 Hosted Zone ID
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
  fqdn              = "web.seeksdevstraining.com" #lsting to monitor my domain name listed using fqdn
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
  zone_id = "Z03534432K2YUY96QKS9O"
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
  zone_id = "Z03534432K2YUY96QKS9O"
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
