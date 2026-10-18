# Production AWS Infrastructure Using Terraform

## Project Overview

This project provisions a production-style AWS infrastructure using **Terraform** with a modular and reusable architecture.

The infrastructure includes:

- Two VPCs
- Public and private subnets
- Bastion host
- Private EC2 instances
- Transit Gateway
- Internet Gateway
- NAT Gateway
- Amazon S3
- S3 VPC Endpoints
- IAM roles for EC2 to access S3
- Amazon RDS MySQL
- RDS DB subnet group
- Security Groups
- Remote Terraform state using Amazon S3

The goal of this project is to demonstrate how a DevOps Engineer can design and deploy secure, reusable, production-style AWS infrastructure using Infrastructure as Code.

---

# Architecture

```text
                            INTERNET
                                |
                                |
                         Internet Gateway
                                |
                     +---------------------+
                     |       VPC-A         |
                     |    10.10.0.0/16     |
                     +---------------------+
                         |
             +-----------+-----------+
             |                       |
      Public Subnet              Private Subnet
       us-east-1a                 us-east-1a
             |                       |
        Bastion Host               EC2-A
             |                       |
             |                       |
             |                       +--------------------+
             |                       |                    |
             |                       | TCP 3306           |
             |                       v                    v
             |                  Amazon RDS               S3
             |                    MySQL                  |
             |                  Private Subnets          |
             |                us-east-1a / 1b             |
             |                                            |
             |                                      S3 VPC Endpoint
             |
             |
             +---------------- Transit Gateway ----------------+
                                                            |
                                                            |
                                                  +---------------------+
                                                  |       VPC-B         |
                                                  |    10.20.0.0/16     |
                                                  +---------------------+
                                                            |
                                                     Private Subnet
                                                            |
                                                          EC2-B
                                                            |
                                                            v
                                                     S3 VPC Endpoint
                                                            |
                                                            v
                                                           S3
```

---

# Application and Database Flow

The application flow is:

```text
User / Administrator
        |
        v
Bastion Host
        |
        v
EC2-A
        |
        | TCP 3306
        v
Amazon RDS MySQL
```

The RDS database is deployed inside private subnets and is not publicly accessible.

EC2-A accesses RDS using the RDS DNS endpoint.

Example:

```text
prod-mysql.xxxxxxxxx.us-east-1.rds.amazonaws.com
```

The application should always use the RDS endpoint instead of the RDS IP address.

---

# AWS Services Used

## Amazon VPC

Two separate VPCs are created:

```text
VPC-A
CIDR: 10.10.0.0/16

VPC-B
CIDR: 10.20.0.0/16
```

Each VPC contains networking components such as:

- Subnets
- Route Tables
- Security Groups
- Internet Gateway
- NAT Gateway
- Transit Gateway attachment

---

# Public and Private Subnets

VPC-A includes public and private subnets.

Example:

```text
10.10.1.0/24
Public Subnet - us-east-1a

10.10.2.0/24
Private Subnet - us-east-1a

10.10.3.0/24
Additional Public Subnet - us-east-1b

10.10.4.0/24
Additional Private Subnet - us-east-1b
```

The second Availability Zone was introduced to support services such as:

- RDS DB Subnet Group
- Future Application Load Balancer
- High Availability architecture

---

# Bastion Host

The Bastion Host is deployed in the public subnet.

It provides secure administrative access to EC2 instances deployed in private subnets.

Access flow:

```text
Laptop
   |
   | SSH 22
   v
Bastion Host
   |
   | SSH 22
   v
Private EC2
```

Private EC2 instances do not require direct SSH access from the internet.

---

# Amazon EC2

Private EC2 instances are deployed inside VPC-A and VPC-B.

Example:

```text
EC2-A
Private IP: 10.10.2.x

EC2-B
Private IP: 10.20.2.x
```

The instances can communicate between VPCs through Transit Gateway.

---

# Transit Gateway

AWS Transit Gateway is used to connect VPC-A and VPC-B.

Without Transit Gateway, multiple VPC-to-VPC connections could require many individual peering connections.

Architecture:

```text
VPC-A
   |
   |
Transit Gateway
   |
   |
VPC-B
```

Transit Gateway provides centralized routing between connected VPCs.

---

# Amazon S3

Amazon S3 is used for application or infrastructure-related object storage.

Example bucket:

```text
subhampanwarr-production-app-data-2026
```

Private EC2 instances access S3 through an S3 Gateway VPC Endpoint.

Traffic flow:

```text
EC2
 |
 |
S3 VPC Endpoint
 |
 |
Amazon S3
```

This avoids sending S3 traffic through the public internet.

---

# S3 VPC Endpoint

Gateway VPC Endpoints are configured for Amazon S3.

Benefits:

- Private communication with S3
- No public internet dependency
- No NAT Gateway required for S3 traffic
- Better security
- Potential NAT data-transfer cost reduction

---

# IAM Role for EC2

EC2 instances use IAM roles instead of storing AWS access keys directly on the server.

Architecture:

```text
EC2
 |
 |
IAM Role
 |
 |
Amazon S3
```

This follows AWS security best practices.

---

# Amazon RDS MySQL

Amazon RDS is used to provide a managed MySQL database.

Configuration used in this project:

```text
Engine           : MySQL
Port             : 3306
Storage          : GP3
Allocated Storage: 20 GB
Public Access    : Disabled
Encryption       : Enabled
Backup Retention : 1 day
Multi-AZ         : Disabled for lab environment
```

The backup retention value is configured as one day because the current AWS account has Free Tier restrictions.

For a real production environment, backup retention should normally be increased according to the organization's recovery and compliance requirements.

---

# RDS DB Subnet Group

RDS requires a DB subnet group containing private subnets from multiple Availability Zones.

Example:

```text
Private Subnet
10.10.2.0/24
us-east-1a

Private Subnet
10.10.4.0/24
us-east-1b
```

Architecture:

```text
DB Subnet Group
       |
       +---- Private Subnet - AZ-A
       |
       +---- Private Subnet - AZ-B
```

The database itself remains private.

---

# RDS Security

RDS does not allow direct access from the internet.

Instead, its security group permits MySQL traffic only from the EC2 application security group.

```text
EC2 Security Group
       |
       | TCP 3306
       v
RDS Security Group
```

This is more secure than allowing:

```text
3306 from 0.0.0.0/0
```

which should never be used for a production database.

---

# RDS Endpoint

Applications connect to RDS using its DNS endpoint.

Example:

```text
prod-mysql.xxxxxxxxx.us-east-1.rds.amazonaws.com
```

Port:

```text
3306
```

Do not configure applications using the database private IP because the IP can change.

---

# Testing RDS Connectivity

RDS is private, so it cannot normally be accessed directly from a laptop.

The correct path is:

```text
Laptop
   |
   v
Bastion
   |
   v
EC2-A
   |
   v
RDS
```

From EC2-A, connectivity can be tested with:

```bash
nc -zv <RDS-ENDPOINT> 3306
```

Example:

```bash
nc -zv prod-mysql.xxxxxxxxx.us-east-1.rds.amazonaws.com 3306
```

Successful output should indicate that TCP port `3306` is reachable.

---

# Connecting to MySQL

From EC2-A:

```bash
mysql \
  -h <RDS-ENDPOINT> \
  -P 3306 \
  -u <DB_USERNAME> \
  -p
```

Then verify the database:

```sql
SHOW DATABASES;
```

Select the application database:

```sql
USE productiondb;
```

Create a test table:

```sql
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100)
);
```

Insert test data:

```sql
INSERT INTO users (name)
VALUES ('Shubham');
```

Verify:

```sql
SELECT * FROM users;
```

---

# Terraform Project Structure

```text
Production/
│
├── environments/
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── variables.tf
│       └── terraform.tfvars
│
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ec2/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── bastion/
│   │
│   ├── transit-gateway/
│   │
│   ├── s3/
│   │
│   ├── vpc-endpoint/
│   │
│   ├── iam-ec2-s3/
│   │
│   └── rds/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── .gitignore
└── README.md
```

---

# Terraform Remote State

Terraform state is stored remotely in Amazon S3.

This provides:

- Centralized state storage
- Team collaboration
- State persistence
- Protection against accidental local state loss

Terraform state files should never be committed to GitHub.

Files such as the following must remain ignored:

```text
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
*.tfvars
tfplan
plan.txt
```

---

# Terraform Deployment

Move to the production environment directory:

```bash
cd ~/Production/environments/prod
```

Format the Terraform code:

```bash
terraform fmt -recursive
```

Initialize:

```bash
terraform init
```

Validate:

```bash
terraform validate
```

Create a Terraform plan:

```bash
terraform plan -out=tfplan
```

Create a human-readable copy:

```bash
terraform show -no-color tfplan > plan.txt
```

Review:

```bash
less plan.txt
```

Apply:

```bash
terraform apply tfplan
```

---

# Terraform State Validation

To list resources:

```bash
terraform state list
```

To check RDS resources:

```bash
terraform state list | grep rds
```

Example:

```text
module.rds.aws_db_instance.this
module.rds.aws_db_subnet_group.this
module.rds.aws_security_group.rds
```

To inspect RDS:

```bash
terraform state show module.rds.aws_db_instance.this
```

To retrieve the endpoint:

```bash
terraform state show module.rds.aws_db_instance.this | grep address
```

---

# Important Security Practices

This project follows several security principles.

### Private EC2 Instances

Application servers are deployed in private subnets.

### Private RDS

RDS is not publicly accessible.

### Security Group Referencing

RDS accepts traffic from the application EC2 Security Group instead of allowing entire CIDR ranges unnecessarily.

### Bastion Access

Administrative SSH access occurs through a Bastion Host.

### IAM Roles

EC2 instances use IAM roles instead of hard-coded AWS access keys.

### S3 VPC Endpoint

S3 can be accessed privately through a VPC Endpoint.

### Encryption

RDS storage encryption is enabled.

---

# Why RDS Cannot Be Accessed Directly From Laptop

The RDS endpoint resolves to a private IP address.

Example:

```text
prod-mysql.xxxxx.rds.amazonaws.com
        |
        v
10.10.4.x
```

A local laptop does not normally have a route to:

```text
10.10.0.0/16
```

Therefore:

```text
DNS resolution = successful
```

does not necessarily mean:

```text
Network connectivity = successful
```

RDS connectivity should be tested from the EC2 application server inside the VPC.

---

# High Availability

The current lab environment uses:

```text
RDS Multi-AZ = false
```

to reduce lab cost.

For real production environments, it can be changed to:

```hcl
multi_az = true
```

This provides an RDS standby instance in another Availability Zone.

---

# Production Improvements

Future improvements for this infrastructure include:

- Application Load Balancer
- Auto Scaling Group
- Multiple EC2 application instances
- HTTPS using ACM
- Route 53
- AWS WAF
- RDS Multi-AZ
- RDS Read Replica
- AWS Secrets Manager
- CloudWatch alarms
- SNS notifications
- AWS Backup
- GitHub Actions CI/CD
- Dev, staging, and production environments

A future highly available architecture would look like:

```text
                    Internet
                       |
                       v
              Application Load Balancer
                       |
             ---------------------
             |                   |
           EC2-A               EC2-B
        us-east-1a          us-east-1b
             |                   |
             ---------+-----------
                       |
                       v
                 RDS Multi-AZ
                 /          \
             Primary       Standby
             AZ-A           AZ-B
```

---

# Key Concepts Demonstrated

This project demonstrates practical knowledge of:

- Infrastructure as Code
- Terraform Modules
- Terraform Remote State
- AWS VPC
- Public and Private Subnets
- Route Tables
- Internet Gateway
- NAT Gateway
- Security Groups
- Bastion Host
- Amazon EC2
- IAM Roles
- Amazon S3
- VPC Endpoints
- Transit Gateway
- Amazon RDS
- RDS DB Subnet Groups
- Private database architecture
- Multi-AZ concepts
- AWS networking
- Secure application-to-database connectivity



# Author

**Shubham Panwar**

AWS / DevOps Engineer

Technologies:

```text
AWS
Terraform
Linux
Git
GitHub
EC2
VPC
RDS
S3
Transit Gateway
IAM
Networking
```


---

# Amazon EKS - Day 1 Implementation

The production infrastructure has been extended with **Amazon EKS** so Kubernetes workloads can run on AWS while reusing the existing VPC-A networking.

## Day 1 Goal

Day 1 focuses only on creating the Kubernetes infrastructure foundation:

- EKS control plane
- EKS IAM roles
- Managed Node Group
- Two private subnets across two Availability Zones
- Node scaling configuration
- Kubernetes cluster access through `kubectl`

Application Deployments, Services, Ingress, ALB, HPA, persistent storage, monitoring, and CI/CD will be added in later phases.

## EKS Network Placement

The EKS cluster uses the existing VPC-A private subnet in `us-east-1a` and the additional private subnet in `us-east-1b`.

```text
VPC-A - 10.10.0.0/16
|
+-- Private Subnet - 10.10.2.0/24 - us-east-1a
|      |
|      +-- EKS Worker Node
|
+-- Private Subnet - 10.10.4.0/24 - us-east-1b
       |
       +-- EKS Worker Node
```

The EKS control plane is managed by AWS. The application compute layer runs on an EKS Managed Node Group inside the private subnets.

## Day 1 EKS Architecture

```text
                     AWS Managed EKS Control Plane
                                |
                 +--------------+--------------+
                 |                             |
        Private Subnet AZ-A           Private Subnet AZ-B
          10.10.2.0/24                  10.10.4.0/24
                 |                             |
          Worker Node-1                  Worker Node-2
                 |                             |
               Pods                          Pods
```

## Managed Node Group Configuration

```text
Instance Type : t3.medium
Capacity Type : ON_DEMAND
Minimum Nodes : 2
Desired Nodes : 2
Maximum Nodes : 4
```

## Terraform EKS Module

A reusable EKS module has been added:

```text
modules/
└── eks/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

The production environment calls this module from:

```text
environments/prod/main.tf
```

The EKS module receives the two real private subnet IDs:

```hcl
private_subnet_ids = [
  module.vpc_a.private_subnet_id,
  aws_subnet.vpc_a_private_2.id
]
```

This keeps the worker nodes private while spreading them across two Availability Zones.

## IAM Configuration

The EKS control plane uses an IAM role with:

```text
AmazonEKSClusterPolicy
```

The managed worker nodes use an EC2 IAM role with:

```text
AmazonEKSWorkerNodePolicy
AmazonEC2ContainerRegistryPullOnly
AmazonEKS_CNI_Policy
```

For this first implementation, the VPC CNI permissions are attached to the node role. A later security-hardening phase can move add-on permissions to dedicated workload identities.

## Validate Terraform

From the production environment:

```bash
cd ~/Production/environments/prod

terraform fmt -recursive
terraform validate
terraform plan
```

Before applying, verify that Terraform is creating the expected EKS and IAM resources and is **not unexpectedly destroying or replacing** existing VPC, subnet, RDS, Transit Gateway, NAT Gateway, or S3 resources.

## Apply EKS

After reviewing the plan:

```bash
terraform apply
```

## Configure kubectl

After the cluster has been created:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name production-eks-cluster
```

Validate cluster access:

```bash
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide
kubectl get pods -A
```

The Day 1 success condition is:

```text
EKS cluster created
+
Managed Node Group created
+
Two worker nodes joined
+
kubectl connected
+
Worker nodes show Ready
```

## Next Kubernetes Phases

The planned Kubernetes implementation will progressively add:

1. Namespace
2. Deployment and ReplicaSet
3. Pods
4. ClusterIP Service
5. Amazon ECR
6. AWS Load Balancer Controller
7. Ingress and ALB
8. ConfigMaps and Secrets
9. Readiness and Liveness Probes
10. Resource Requests and Limits
11. Metrics Server and HPA
12. Karpenter or node autoscaling
13. EBS CSI, PV, and PVC
14. Prometheus and Grafana
15. Jenkins CI/CD deployment into EKS
