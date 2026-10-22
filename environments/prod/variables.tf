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

variable "eks_cluster_name" {
  description = "Production EKS cluster name"
  type        = string
  default     = "production-eks-cluster"
}

variable "dr_region" {
  description = "Disaster recovery AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "create_rds_read_replica" {
  description = "Create same-region RDS read replica"
  type        = bool
  default     = false
}

variable "create_cross_region_replica" {
  description = "Create cross-region RDS read replica"
  type        = bool
  default     = false
}

variable "enable_cross_region_backups" {
  description = "Enable cross-region automated backup replication"
  type        = bool
  default     = false
}

variable "create_cross_region_snapshot" {
  description = "Create a manual snapshot and copy it to DR region"
  type        = bool
  default     = false
}

variable "enable_performance_insights" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = false
}


