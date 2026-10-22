# Production AWS Infrastructure with Terraform, EKS, ALB, ECR & Secrets Manager

## Project Overview

This repository implements a production-style AWS platform using **Terraform**, reusable modules, Amazon EKS, Amazon RDS, Amazon ECR, AWS Load Balancer Controller, AWS Secrets Manager, and multi-VPC networking.

The project is designed as a practical DevOps lab that demonstrates how production infrastructure is provisioned, secured, connected, validated, and troubleshot.

## What This Project Includes

- Multi-VPC networking
- Public and private subnets across multiple Availability Zones
- Internet Gateway and NAT Gateway
- Bastion-based administrative access
- Private EC2 instances
- AWS Transit Gateway connectivity between VPCs
- S3 Gateway VPC Endpoints
- IAM roles for EC2-to-S3 access
- Amazon RDS MySQL in private subnets
- AWS-managed RDS master password in Secrets Manager
- Custom RDS parameter group
- RDS backup and DR configuration
- Cross-Region DR networking and KMS
- Amazon EKS managed cluster
- EKS managed worker node group in private subnets
- Kubernetes namespace, Deployment, Pods, probes, resources, and ClusterIP Service
- AWS Load Balancer Controller
- Internet-facing Application Load Balancer through Kubernetes Ingress
- Amazon ECR repository and custom container image workflow
- Secrets Store CSI Driver
- AWS Secrets Manager CSI provider
- IRSA-based pod access to Secrets Manager
- SecretProviderClass-based RDS secret mounting
- Remote Terraform state in Amazon S3

---

# High-Level Architecture

```text
                                    INTERNET
                                        |
                                        v
                               Internet Gateway
                                        |
                        +---------------+---------------+
                        |                               |
                        v                               v
                Public Subnet AZ-A              Public Subnet AZ-B
                  10.10.1.0/24                    10.10.3.0/24
                        |                               |
                        +-------------+-----------------+
                                      |
                             Internet-facing ALB
                                      |
                                      v
                          Kubernetes ALB Ingress
                                      |
                                      v
                           nginx-service ClusterIP
                                      |
                       +--------------+--------------+
                       |              |              |
                       v              v              v
                     Pod-1          Pod-2          Pod-3
                       |
                       | CSI mounted secret
                       v
                AWS Secrets Manager
                       |
                       v
                    RDS MySQL


Private EKS worker nodes
        |
        | outbound internet access
        v
Private Route Table
        |
        v
NAT Gateway
        |
        v
Internet Gateway


VPC-A 10.10.0.0/16
        |
        v
Transit Gateway
        |
        v
VPC-B 10.20.0.0/16


Primary Region: us-east-1
DR Region:      us-west-2
```

---

# AWS Network Design

## VPC-A — Primary Application VPC

```text
CIDR   : 10.10.0.0/16
Region : us-east-1
```

### Public Subnets

```text
10.10.1.0/24 - us-east-1a
10.10.3.0/24 - us-east-1b
```

These subnets are used for public-facing infrastructure such as:

- Bastion Host
- NAT Gateway
- Internet-facing Application Load Balancer

Both public subnets are tagged for AWS Load Balancer Controller discovery:

```text
kubernetes.io/role/elb = 1
```

### Private Subnets

```text
10.10.2.0/24 - us-east-1a
10.10.4.0/24 - us-east-1b
```

These subnets are used by:

- Private EC2 instances
- EKS managed worker nodes
- RDS subnet group

Private subnets use:

```text
kubernetes.io/role/internal-elb = 1
```

---

# NAT Gateway

The EKS worker nodes run in private subnets and do not have public IP addresses.

They still require outbound access for tasks such as:

- EKS node bootstrap
- Pulling container images
- Accessing AWS public APIs
- Downloading dependencies
- Reaching external services

The private route table therefore contains:

```text
0.0.0.0/0 -> NAT Gateway
```

The NAT Gateway is placed in a public subnet and reaches the internet through the Internet Gateway.

```text
Private EKS Node
      |
      v
Private Route Table
      |
      v
NAT Gateway
      |
      v
Internet Gateway
      |
      v
Internet / AWS Public Endpoint
```

## Practical Issue Solved

During the build, EC2 worker instances launched successfully but the EKS managed node group failed with:

```text
NodeCreationFailure
Instances failed to join the kubernetes cluster
```

IAM and EC2 health were correct. The missing component was outbound connectivity from the private subnets.

After adding:

- Elastic IP
- NAT Gateway
- Private default route to NAT

the recreated worker nodes successfully joined the EKS cluster.

---

# VPC-B — Secondary Private VPC

```text
CIDR   : 10.20.0.0/16
Region : us-east-1
```

VPC-B hosts private infrastructure and communicates with VPC-A through AWS Transit Gateway.

---

# AWS Transit Gateway

Transit Gateway provides centralized VPC-to-VPC connectivity.

```text
VPC-A
  |
  v
Transit Gateway
  |
  v
VPC-B
```

This design scales better than creating many individual VPC peering relationships.

---

# Bastion Host

The Bastion Host runs in a public subnet and provides administrative access to private resources.

```text
Administrator
     |
     | SSH
     v
Bastion Host
     |
     | SSH
     v
Private EC2
```

Private EC2 instances do not require direct internet-facing SSH access.

---

# Amazon S3 and VPC Endpoints

Amazon S3 is used for application and infrastructure-related object storage.

Private workloads can reach S3 through Gateway VPC Endpoints.

```text
Private Resource
      |
      v
S3 Gateway VPC Endpoint
      |
      v
Amazon S3
```

Benefits:

- Private S3 connectivity
- Reduced NAT dependency
- Improved security
- Potential NAT Gateway cost reduction

---

# Amazon RDS MySQL

The primary RDS database runs in private subnets inside VPC-A.

Current configuration includes:

```text
Engine             : MySQL
Engine Version     : 8.0.46
Port               : 3306
Storage            : GP3
Initial Storage    : 20 GB
Maximum Storage    : 100 GB
Public Access      : Disabled
Storage Encryption : Enabled
Multi-AZ           : Disabled for lab
```

The RDS parameter group uses:

```text
mysql8.0
```

This matches the MySQL 8.0 engine family.

## RDS Credentials

Terraform uses:

```hcl
manage_master_user_password = true
```

This means AWS generates and stores the RDS master credentials in AWS Secrets Manager instead of hardcoding the password in Terraform.

---

# RDS Secrets Manager Integration

The RDS-managed secret is consumed by Kubernetes through:

```text
RDS
 |
 v
AWS Secrets Manager
 |
 v
IAM Role
 |
 v
IRSA
 |
 v
production-app ServiceAccount
 |
 v
Secrets Store CSI Driver
 |
 v
SecretProviderClass
 |
 v
/mnt/secrets-store inside Pod
```

The Kubernetes ServiceAccount is associated with an IAM role using IRSA:

```text
production-app
      |
      v
production-eks-cluster-app-secrets-role
```

The secret is mounted read-only into the application Pod.

The database password is therefore not hardcoded in:

- Git
- Terraform variables
- Docker image
- Kubernetes Deployment
- application source code

---

# Secrets Store CSI Driver

The EKS cluster uses the AWS Secrets Store CSI add-on.

The add-on installs:

- Secrets Store CSI Driver
- AWS Secrets Manager provider
- SecretProviderClass CRD

The project defines:

```text
SecretProviderClass: production-db-secret
Namespace: production
Provider: aws
```

The secret is mounted into the Pod at:

```text
/mnt/secrets-store
```

---

# Amazon EKS

Amazon EKS provides the Kubernetes orchestration layer.

AWS manages the Kubernetes control plane while worker nodes run in private subnets.

```text
             AWS Managed EKS Control Plane
                         |
             +-----------+-----------+
             |                       |
     Private Subnet AZ-A      Private Subnet AZ-B
       10.10.2.0/24             10.10.4.0/24
             |                       |
        Worker Node-1            Worker Node-2
             |                       |
           Pods                    Pods
```

## Managed Node Group

Current configuration:

```text
Instance Type : t3.small
Capacity Type : ON_DEMAND

Minimum Nodes : 2
Desired Nodes : 2
Maximum Nodes : 4
```

The two worker nodes are distributed across private subnets in separate Availability Zones.

---

# Kubernetes Workload

The Kubernetes workload contains:

- Namespace
- Deployment
- ReplicaSet
- 3 Pods
- ClusterIP Service
- Resource requests
- Resource limits
- Readiness probe
- Liveness probe
- ServiceAccount
- CSI volume
- Secrets Manager volume mount

Current resource configuration:

```text
Replicas : 3

Requests
CPU      : 100m
Memory   : 128Mi

Limits
CPU      : 250m
Memory   : 256Mi
```

Application flow:

```text
Deployment
    |
    v
ReplicaSet
    |
    +---- Pod
    |
    +---- Pod
    |
    +---- Pod
           |
           v
    nginx-service
      ClusterIP
```

---

# AWS Load Balancer Controller

The AWS Load Balancer Controller runs inside EKS and watches Kubernetes Ingress resources.

The project uses an ALB Ingress configured with:

```text
Scheme      : internet-facing
Target Type : ip
Listener    : HTTP 80
Health Path : /
IngressClass: alb
```

Request flow:

```text
Internet
   |
   v
AWS Application Load Balancer
   |
   v
Kubernetes Ingress
   |
   v
nginx-service
   |
   v
Pod IP targets
```

Because the Ingress uses:

```text
alb.ingress.kubernetes.io/target-type = ip
```

the ALB registers Pod IP addresses directly in the target group.

All three application targets were validated as healthy.

---

# ALB Subnet Discovery Troubleshooting

During deployment the Ingress initially failed with:

```text
FailedBuildModel
couldn't auto-discover subnets:
subnets count less than minimal required count: 1 < 2
```

The cause was that only one public subnet had:

```text
kubernetes.io/role/elb = 1
```

The second public subnet was updated with the same tag.

The Ingress was also configured explicitly with both public subnet IDs:

```text
alb.ingress.kubernetes.io/subnets
```

After reconciliation:

```text
SuccessfullyReconciled
```

the Application Load Balancer became active.

---

# Amazon ECR

Amazon ECR stores the custom application container image.

Repository:

```text
production-app
```

The custom image workflow is:

```text
Dockerfile
    |
    v
docker build
    |
    v
production-app:v1
    |
    v
docker tag
    |
    v
Amazon ECR
    |
    v
EKS Deployment
```

Example build:

```bash
docker build -t production-app:v1 .
```

Authenticate to ECR:

```bash
aws ecr get-login-password \
  --region us-east-1 | \
docker login \
  --username AWS \
  --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

Push:

```bash
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/production-app:v1
```

The image was successfully pushed and verified in ECR.

---

# Disaster Recovery Region

A second AWS provider is configured for disaster recovery.

```text
Primary Region : us-east-1
DR Region      : us-west-2
```

DR VPC:

```text
CIDR: 10.30.0.0/16
```

Private DR subnets:

```text
10.30.1.0/24 - us-west-2a
10.30.2.0/24 - us-west-2b
```

The DR design includes:

- DR VPC
- RDS subnet group
- KMS encryption
- Cross-Region Read Replica support
- Automated backup replication support
- Manual snapshot copy support

---

# Terraform Project Structure

```text
Production/
|
|-- app/
|   |-- Dockerfile
|   `-- index.html
|
|-- environments/
|   `-- prod/
|       |-- backend.tf
|       |-- ecr.tf
|       |-- ingress.tf
|       |-- kubernetes.tf
|       |-- load-balancer-controller.tf
|       |-- main.tf
|       |-- outputs.tf
|       |-- providers.tf
|       |-- rds-dr.tf
|       |-- secret-provider-class.tf
|       |-- secrets-csi.tf
|       |-- secrets.tf
|       `-- variables.tf
|
|-- modules/
|   |-- aws-load-balancer-controller/
|   |-- bastion/
|   |-- ec2/
|   |-- ecr/
|   |-- eks/
|   |-- eks-secrets-access/
|   |-- iam-ec2-s3/
|   |-- rds/
|   |-- rds-dr/
|   |-- s3/
|   |-- transit-gateway/
|   |-- vpc/
|   `-- vpc-endpoint/
|
|-- .gitignore
`-- README.md
```

---

# Terraform Remote State

Terraform state is stored remotely in Amazon S3.

Benefits:

- Centralized state
- Persistent state storage
- Team collaboration
- Protection from accidental local state loss

Generated and sensitive files should not be committed to Git.

Examples:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
tfplan*
plan*.txt
backend.hcl
```

---

# Deployment and Validation

## Terraform

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

## Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name production-eks-cluster
```

## Validate EKS nodes

```bash
kubectl get nodes -o wide
```

Expected:

```text
2 worker nodes
STATUS = Ready
```

## Validate application Pods

```bash
kubectl get pods -n production -o wide
```

Expected:

```text
3 Pods
READY = 1/1
STATUS = Running
```

## Validate Service

```bash
kubectl get svc -n production
```

## Validate Ingress

```bash
kubectl get ingress -n production
```

The Ingress should show an AWS ALB DNS name in the ADDRESS column.

## Validate ALB

```bash
curl -I http://<ALB-DNS-NAME>
```

Expected:

```text
HTTP/1.1 200 OK
```

## Validate ALB target health

```bash
aws elbv2 describe-target-health \
  --region us-east-1 \
  --target-group-arn <TARGET-GROUP-ARN>
```

Expected:

```text
All Pod IP targets = healthy
```

## Validate SecretProviderClass

```bash
kubectl get secretproviderclass -n production
kubectl describe secretproviderclass production-db-secret -n production
```

## Validate CSI mounted secret

Do not print the actual secret value.

```bash
kubectl exec -n production <POD-NAME> -- ls -l /mnt/secrets-store
```

## Validate ServiceAccount

```bash
kubectl get pod -n production <POD-NAME> \
  -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

Expected:

```text
production-app
```

---

# Key Practical Troubleshooting Scenarios

## 1. EKS Nodes Failed to Join

Symptoms:

```text
NodeCreationFailure
Instances failed to join the kubernetes cluster
```

Checks performed:

- EC2 instance state
- Auto Scaling health
- IAM node role policies
- EKS endpoint configuration
- private subnet routing

Root cause:

```text
NAT Gateway missing
```

Fix:

```text
Elastic IP
   +
NAT Gateway
   +
0.0.0.0/0 -> NAT route
```

Result:

```text
Both EKS nodes became Ready
```

## 2. ALB Could Not Discover Two Subnets

Symptoms:

```text
FailedBuildModel
subnets count less than minimal required count: 1 < 2
```

Root cause:

```text
Second public subnet missing kubernetes.io/role/elb = 1
```

Fix:

- Added ELB tag to second public subnet
- Explicitly configured both public subnet IDs on the Ingress

Result:

```text
SuccessfullyReconciled
ALB state = active
```

## 3. RDS Parameter Group Version Mismatch

Symptoms:

```text
mysql8.0 parameter group could not be used with a MySQL 8.4 instance
```

Fix:

```text
Engine Version = 8.0.46
Parameter Family = mysql8.0
```

---

# Security Design

The project follows several production-oriented security practices:

- EKS worker nodes run in private subnets
- RDS has no public access
- RDS credentials are managed by AWS Secrets Manager
- Pods access Secrets Manager through IRSA
- Secrets are mounted read-only through CSI
- EC2 uses IAM roles instead of static credentials
- S3 traffic can use private VPC Endpoints
- Bastion access is separated from application workloads
- Terraform state is stored remotely
- Sensitive/generated Terraform files are excluded from Git

---

# Technologies Used

```text
AWS
Terraform
Amazon EKS
Kubernetes
Amazon ECR
AWS Load Balancer Controller
Application Load Balancer
AWS Secrets Manager
Secrets Store CSI Driver
IRSA
Amazon RDS MySQL
Amazon EC2
Amazon S3
AWS Transit Gateway
VPC Endpoints
NAT Gateway
IAM
KMS
Docker
Linux
Git
GitHub
```

---

# Author

**Shubham Panwar**

AWS / DevOps Engineer
