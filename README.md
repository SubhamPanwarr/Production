# Production AWS Terraform Infrastructure

Production-style AWS infrastructure deployed through Terraform.

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

## Environments

- Dev
- Stage
- Prod

## Terraform Modules

- VPC
- EC2
- Bastion
- Transit Gateway

## Architecture Flow

User -> Bastion -> VPC-A -> Transit Gateway -> VPC-B

## Deployment

```bash
cd environments/prod

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply


---

# Step 22 — Check the full repository

Run:

```bash
cd ~/Production
