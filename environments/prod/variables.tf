variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "key_name" {
  description = "Existing AWS EC2 key pair"
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP address in CIDR format"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  description = "Pinned AMI ID for EC2 instances"
  type        = string
}

variable "availability_zone_2" {
  description = "Second Availability Zone"
  type        = string
  default     = "us-east-1b"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}
