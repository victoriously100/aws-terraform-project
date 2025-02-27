variable "aws_region_eu" {
  description = "AWS region for the EU provider"
  default     = "eu-west-2"
}

variable "aws_region_us" {
  description = "AWS region for the US provider"
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS profile to use"
  default     = "default"
}
#VPC variables
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/24"
}

variable "vpc_name" {
  description = "Name of the VPC"
  default     = "demo-test"
}

variable "igw_name" {
  description = "Name of the internet gateway"
  default     = "demo-igw"
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for the first public subnet"
  default     = "10.0.0.0/25"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for the second public subnet"
  default     = "10.0.0.128/25"
}
variable "public_subnets" {
  description = "List of public subnets"
  type = list(object({
    cidr_block        = string
    availability_zone = string
    subnet_name       = string
  }))
  default = [
    {
      cidr_block        = "10.0.0.0/25"
      availability_zone = "eu-west-2a"
      subnet_name       = "public_subnet_1"
    },
    {
      cidr_block        = "10.0.0.128/25"
      availability_zone = "eu-west-2b"
      subnet_name       = "public_subnet_2"
    }
  ]
}

variable "availability_zone_1" {
  description = "Availability zone for the first subnet"
  default     = "eu-west-2a"
}

variable "availability_zone_2" {
  description = "Availability zone for the second subnet"
  default     = "eu-west-2b"
}
#Route Table variables
variable "route_table_1_name" {
  description = "Name of the first public route table"
  default     = "public-route-table-1"
}

variable "route_table_2_name" {
  description = "Name of the second public route table"
  default     = "public-route-table-2"
}

variable "public_route_tables" {
  description = "Map of route tables with their names"
  type        = map(string)
  default = {
    "rt1" = "public-route-table-1"
    "rt2" = "public-route-table-2"
  }
}




#Security Group variables
variable "ingress_rules" {
  description = "List of ingress rules for the security group"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["188.29.107.168/32"] #Only my exact IP should be selected
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}
#Launch templates and ASG variables
variable "launch_template_name" {
  description = "Name of the launch template"
  type        = string
  default     = "test-launch-temp"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
  default     = "ami-091f18e98bc129c4e"
}

variable "instance_type" {
  description = "Instance type for EC2 instances"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Key pair name for SSH access"
  type        = string
  default     = "my-key"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

#S3 variable
variable "bucket_regional_domain_name" {
  type = string
  default = "web.seeksdevstraining.com"  
}

#ACM cert variables
variable "alb_cert_domain" {
  description = "Domain name for the ALB ACM certificate"
  default     = "*.seeksdevstraining.com"
}

variable "cloudfront_cert_domain" {
  description = "Domain name for the CloudFront ACM certificate"
  default     = "web.seeksdevstraining.com"
}

variable "route53_zone_id" {
  description = "Route 53 Hosted Zone ID"
  default     = "Z03534432K2YUY96QKS9O"
}

# This is an alternative way to set variables and use then later within TF builds
/*variable "my_ip" {
  description = "Your public IP address" # description only
  type        = string
}*/

# then can run this on bash to store the actual variable as it stores it in the state file for terraform to locate it whenever you run apply
# terraform apply -var="my_ip=$(curl -s ifconfig.me)"

#url = "https://api.ipify.org?format=text" good way to get ip add can remove the format
