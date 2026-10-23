# -------------------------------------------------------
# Get latest Amazon Linux 2023 AMI
# -------------------------------------------------------





locals {
  common_tags = {
    Environment = var.environment
    Application = "Production-Network"
  }
}

# =======================================================
# VPC-A
# =======================================================

module "vpc_a" {
  source = "../../modules/vpc"

  vpc_name = "prod-vpc-a"
  vpc_cidr = "10.10.0.0/16"

  public_subnet_cidr  = "10.10.1.0/24"
  private_subnet_cidr = "10.10.2.0/24"
  tgw_subnet_cidr     = "10.10.10.0/28"

  availability_zone = var.availability_zone

  create_igw = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.common_tags
}

# =======================================================
# VPC-B
# =======================================================

module "vpc_b" {
  source = "../../modules/vpc"

  vpc_name = "prod-vpc-b"
  vpc_cidr = "10.20.0.0/16"

  private_subnet_cidr = "10.20.2.0/24"
  tgw_subnet_cidr     = "10.20.10.0/28"

  availability_zone = var.availability_zone

  create_igw = false

  tags = local.common_tags
}

#-----------------------------------------------
resource "aws_eip" "nat_vpc_a" {
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "prod-vpc-a-nat-eip"
    }
  )
}

resource "aws_nat_gateway" "vpc_a" {
  allocation_id = aws_eip.nat_vpc_a.id
  subnet_id     = module.vpc_a.public_subnet_id

  depends_on = [
    module.vpc_a
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "prod-vpc-a-nat"
    }
  )
}

# =======================================================
# Transit Gateway
# =======================================================

module "transit_gateway" {
  source = "../../modules/transit-gateway"

  name        = "prod-tgw"
  description = "Production Transit Gateway"

  vpc_attachments = {
    vpc-a = {
      vpc_id = module.vpc_a.vpc_id

      subnet_ids = [
        module.vpc_a.tgw_subnet_id
      ]
    }

    vpc-b = {
      vpc_id = module.vpc_b.vpc_id

      subnet_ids = [
        module.vpc_b.tgw_subnet_id
      ]
    }
  }

  tags = local.common_tags
}

# =======================================================
# VPC-A -> VPC-B route
# =======================================================

resource "aws_route" "vpc_a_private_to_vpc_b" {
  route_table_id         = module.vpc_a.private_route_table_id
  destination_cidr_block = "10.20.0.0/16"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
}

# Bastion also needs to reach VPC-B

resource "aws_route" "vpc_a_public_to_vpc_b" {
  route_table_id         = module.vpc_a.public_route_table_id
  destination_cidr_block = "10.20.0.0/16"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
}

# =======================================================
# VPC-B -> VPC-A route
# =======================================================

resource "aws_route" "vpc_b_private_to_vpc_a" {
  route_table_id         = module.vpc_b.private_route_table_id
  destination_cidr_block = "10.10.0.0/16"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
}

# =======================================================
# Bastion Host
# =======================================================

module "bastion" {
  source = "../../modules/bastion"

  name          = "prod-bastion"
  ami_id        = var.ami_id
  instance_type = var.instance_type

  subnet_id = module.vpc_a.public_subnet_id
  vpc_id    = module.vpc_a.vpc_id

  key_name   = var.key_name
  admin_cidr = var.admin_cidr

  tags = local.common_tags
}

# =======================================================
# EC2-A
# =======================================================

module "ec2_a" {
  source = "../../modules/ec2"

  instance_name = "prod-ec2-a"

  ami_id        = var.ami_id
  instance_type = var.instance_type

  subnet_id = module.vpc_a.private_subnet_id
  vpc_id    = module.vpc_a.vpc_id

  key_name = var.key_name

  iam_instance_profile = module.ec2_s3_iam.instance_profile_name

  ssh_allowed_cidrs = [
    "10.10.1.0/24"
  ]

  tags = local.common_tags
}

# =======================================================
# EC2-B
# =======================================================

module "ec2_b" {
  source = "../../modules/ec2"

  instance_name = "prod-ec2-b"

  ami_id        = var.ami_id
  instance_type = var.instance_type

  subnet_id = module.vpc_b.private_subnet_id
  vpc_id    = module.vpc_b.vpc_id

  key_name = var.key_name

  iam_instance_profile = module.ec2_s3_iam.instance_profile_name

  # Bastion comes from VPC-A.
  ssh_allowed_cidrs = [
    "10.10.0.0/16"
  ]

  tags = local.common_tags
}

# =======================================================
# S3 Bucket
# =======================================================

module "s3" {
  source = "../../modules/s3"

  bucket_name = "subhampanwarr-production-app-data-2026"

  versioning_enabled = true

  tags = local.common_tags
}

# =======================================================
# S3 Gateway Endpoint - VPC-A
# =======================================================

module "s3_endpoint_vpc_a" {
  source = "../../modules/vpc-endpoint"

  vpc_id     = module.vpc_a.vpc_id
  aws_region = var.aws_region

  route_table_ids = [
    module.vpc_a.private_route_table_id
  ]

  endpoint_name = "prod-vpc-a-s3-endpoint"

  tags = local.common_tags
}

# =======================================================
# S3 Gateway Endpoint - VPC-B
# =======================================================

module "s3_endpoint_vpc_b" {
  source = "../../modules/vpc-endpoint"

  vpc_id     = module.vpc_b.vpc_id
  aws_region = var.aws_region

  route_table_ids = [
    module.vpc_b.private_route_table_id
  ]

  endpoint_name = "prod-vpc-b-s3-endpoint"

  tags = local.common_tags
}

module "ec2_s3_iam" {
  source = "../../modules/iam-ec2-s3"

  role_name  = "prod-ec2-s3-role"
  bucket_arn = module.s3.bucket_arn
}

# =======================================================
# VPC-A Additional Public Subnet - AZ-B
# Used by Application Load Balancer
# =======================================================

resource "aws_subnet" "vpc_a_public_2" {
  vpc_id                  = module.vpc_a.vpc_id
  cidr_block              = "10.10.3.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name                     = "prod-vpc-a-public-subnet-2"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

resource "aws_route_table_association" "vpc_a_public_2" {
  subnet_id      = aws_subnet.vpc_a_public_2.id
  route_table_id = module.vpc_a.public_route_table_id
}

# =======================================================
# VPC-A Additional Private DB Subnet - AZ-B
# =======================================================

resource "aws_subnet" "vpc_a_private_2" {
  vpc_id            = module.vpc_a.vpc_id
  cidr_block        = "10.10.4.0/24"
  availability_zone = var.availability_zone_2

  tags = merge(
    local.common_tags,
    {
      Name                              = "prod-vpc-a-private-subnet-2"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

resource "aws_route_table_association" "vpc_a_private_2" {
  subnet_id      = aws_subnet.vpc_a_private_2.id
  route_table_id = module.vpc_a.private_route_table_id
}

resource "aws_route" "vpc_a_private_internet" {
  route_table_id         = module.vpc_a.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_a.id
}

# =======================================================
# RDS MySQL
# =======================================================
module "rds" {
  source = "../../modules/rds"

  identifier = "prod-mysql"

  vpc_id = module.vpc_a.vpc_id

  subnet_ids = [
    module.vpc_a.private_subnet_id,
    aws_subnet.vpc_a_private_2.id
  ]

  allowed_security_group_ids = [
    module.ec2_a.security_group_id,
    module.eks.cluster_security_group_id
  ]

  db_name     = "productiondb"
  db_username = var.db_username


  instance_class    = "db.t3.micro"
  allocated_storage = 20

  max_allocated_storage = 100

  multi_az = false

  # ---------------------------------------------------
  # Backup
  # ---------------------------------------------------

  backup_retention_period = 1

  backup_window      = "03:00-04:00"
  maintenance_window = "Sun:04:00-Sun:05:00"

  delete_automated_backups = true

  # Lab settings
  deletion_protection = false
  skip_final_snapshot = true

  # ---------------------------------------------------
  # Parameter Group
  # ---------------------------------------------------

  create_parameter_group = true

  parameter_group_family = "mysql8.0"

  slow_query_log_enabled = true
  long_query_time        = 2

  # ---------------------------------------------------
  # Performance Insights
  # ---------------------------------------------------

  performance_insights_enabled = var.enable_performance_insights

  performance_insights_retention_period = 7

  # ---------------------------------------------------
  # Same Region Read Replica
  # ---------------------------------------------------

  create_read_replica = var.create_rds_read_replica

  read_replica_identifier = "prod-mysql-read-1"

  read_replica_instance_class = "db.t3.micro"

  tags = local.common_tags
}

# =======================================================
# Amazon EKS - Day 1
# =======================================================
module "eks" {
  source = "../../modules/eks"

  cluster_name = var.eks_cluster_name

  private_subnet_ids = [
    module.vpc_a.private_subnet_id,
    aws_subnet.vpc_a_private_2.id
  ]

  # =====================================================
  # General Purpose Node Group
  # =====================================================

  instance_types = ["t3.small"]

  min_size     = 2
  desired_size = 2
  max_size     = 4

  capacity_type = "ON_DEMAND"

  # =====================================================
  # Dedicated Frontend Node Group
  # =====================================================

  create_workload_node_group = true

  workload_node_group_name = "frontend"

  workload_instance_types = [
    "t3.small"
  ]

  workload_min_size     = 1
  workload_desired_size = 1
  workload_max_size     = 2

  workload_labels = {
    workload    = "frontend"
    environment = "production"
  }

  workload_taints = [
    {
      key    = "dedicated"
      value  = "frontend"
      effect = "NO_SCHEDULE"
    }
  ]

  tags = merge(
    local.common_tags,
    {
      ManagedBy = "Terraform"
      Component = "EKS"
    }
  )
}


