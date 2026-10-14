# Production AWS Terraform Infrastructure

Production-style AWS infrastructure built using reusable Terraform modules.

## Architecture

The project creates:

- VPC-A
- VPC-B
- Transit Gateway
- Transit Gateway VPC Attachments
- EC2-A
- EC2-B
- Bastion Host
- Public Subnet
- Private Subnets
- Internet Gateway
- Route Tables
- Security Groups
- S3 Bucket
- S3 Gateway VPC Endpoint for VPC-A
- S3 Gateway VPC Endpoint for VPC-B

## Environments

- Dev
- Stage
- Prod

## Terraform Modules

- VPC
- EC2
- Bastion
- Transit Gateway
- S3
- VPC Endpoint

## Architecture Flow

```text
User
 |
 v
Bastion
 |
 v
VPC-A
 |
 +------> EC2-A
 |
 +------> Transit Gateway ------> VPC-B ------> EC2-B

EC2-A
 |
 v
S3 Gateway Endpoint
 |
 v
S3 Bucket

EC2-B
 |
 v
S3 Gateway Endpoint
 |
 v
S3 Bucket
