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
