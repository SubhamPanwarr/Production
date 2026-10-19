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

## Amazon EKS – Day 1 Implementation

The production infrastructure has been extended with Amazon EKS to provide a Kubernetes-based application orchestration layer.

### EKS Architecture

The EKS cluster reuses the existing private subnets in VPC-A across multiple Availability Zones.

```text
                    Amazon EKS Control Plane
                       Managed by AWS
                              |
                   -----------------------
                   |                     |
            Private Subnet        Private Subnet
              us-east-1a            us-east-1b
                   |                     |
            Worker Node-1         Worker Node-2
                   |                     |
                  Pods                  Pods

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


---

# Amazon EKS - Day 2 Kubernetes Workloads

Day 2 introduces the first Kubernetes application workloads on top of the EKS cluster created on Day 1.

## Day 2 Goal

The objective is to learn how Terraform can manage Kubernetes resources inside Amazon EKS.

The following Kubernetes resources are created:

- Terraform Kubernetes provider
- `production` Namespace
- NGINX Deployment
- 3 Pod replicas
- Labels and selectors
- ClusterIP Service
- CPU and memory requests
- CPU and memory limits
- Readiness probe
- Liveness probe

Ingress, ALB, ECR, HPA, persistent storage, and monitoring are intentionally reserved for later phases.

## Day 2 Architecture

```text
                    Amazon EKS
                        |
                 production Namespace
                        |
                    Deployment
                    nginx
                        |
                    ReplicaSet
                        |
             +----------+----------+
             |          |          |
           Pod-1      Pod-2      Pod-3
             \          |          /
              \         |         /
                 nginx-service
                   ClusterIP
```

The Kubernetes Service provides one stable internal endpoint for the three NGINX Pods.

## Terraform Kubernetes Provider

Terraform now includes the HashiCorp Kubernetes provider.

```hcl
kubernetes = {
  source  = "hashicorp/kubernetes"
  version = "~> 2.0"
}
```

Terraform authenticates to the EKS API server using the existing EKS cluster outputs.

```text
Terraform
   |
   +-- AWS Provider
   |      |
   |      +-- VPC
   |      +-- EKS
   |      +-- IAM
   |      +-- RDS
   |
   +-- Kubernetes Provider
          |
          +-- Namespace
          +-- Deployment
          +-- Pods
          +-- Service
```

## Production Namespace

The namespace separates production Kubernetes resources logically from system workloads.

```text
EKS Cluster
|
+-- kube-system
|
+-- production
     |
     +-- nginx Deployment
     +-- nginx-service
```

Validation:

```bash
kubectl get namespaces
kubectl get pods -n production
```

## NGINX Deployment

The Deployment maintains three replicas.

```text
Desired replicas = 3

Deployment
   |
ReplicaSet
   |
+-- Pod-1
+-- Pod-2
+-- Pod-3
```

If one Pod fails, Kubernetes attempts to restore the desired replica count.

Validation:

```bash
kubectl get deployment -n production
kubectl get replicasets -n production
kubectl get pods -n production
kubectl get pods -n production -o wide
```

## Labels and Selectors

The Pods use:

```text
app = nginx
```

The Service uses the same label selector.

```text
nginx-service
      |
 selector
 app=nginx
      |
+-----+-----+
|     |     |
Pod   Pod   Pod
```

This is how the Service identifies which Pods should receive traffic.

## ClusterIP Service

The service is internal to the Kubernetes cluster.

```text
Service Type = ClusterIP

nginx-service
      |
      | TCP 80
      |
+-----+-----+
|     |     |
Pod-1 Pod-2 Pod-3
```

Validation:

```bash
kubectl get svc -n production
kubectl describe svc nginx-service -n production
kubectl get endpoints -n production
```

The application is intentionally not exposed to the public internet on Day 2.

## Resource Requests and Limits

Each NGINX container includes CPU and memory resource controls.

```text
Requests
CPU    = 100m
Memory = 128Mi

Limits
CPU    = 250m
Memory = 256Mi
```

Requests help Kubernetes decide where the Pod can be scheduled.

Limits define the maximum resources available to the container.

## Readiness Probe

The readiness probe checks whether the application is ready to receive traffic.

```text
Pod starts
   |
Readiness Probe
   |
GET /
   |
Ready
   |
Service sends traffic
```

## Liveness Probe

The liveness probe checks whether the application remains healthy.

```text
Application unhealthy
       |
Liveness fails
       |
Kubernetes restarts container
```

## Day 2 Terraform File

The Kubernetes resources are defined in:

```text
environments/prod/kubernetes.tf
```

The Day 2 flow is:

```text
Terraform
   |
   v
Kubernetes Provider
   |
   v
production Namespace
   |
   v
NGINX Deployment
   |
   v
ReplicaSet
   |
   v
3 Pods
   |
   v
ClusterIP Service
```

## Day 2 Deployment Steps

First synchronize the feature branch locally:

```bash
cd ~/Production

git fetch origin

git checkout feature/day2-kubernetes-workloads

git pull origin feature/day2-kubernetes-workloads
```

Move to the Terraform production environment:

```bash
cd environments/prod
```

Initialize the new Kubernetes provider:

```bash
terraform init -upgrade
```

Format and validate:

```bash
terraform fmt -recursive
terraform validate
```

Create a Terraform plan:

```bash
terraform plan
```

Review the plan carefully before applying.

After the Day 1 EKS cluster exists and is reachable, apply:

```bash
terraform apply
```

## Kubernetes Validation

Configure local kubectl access if required:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name production-eks-cluster
```

Then run:

```bash
kubectl get namespaces

kubectl get deployment -n production

kubectl get replicasets -n production

kubectl get pods -n production

kubectl get pods -n production -o wide

kubectl get svc -n production

kubectl get endpoints -n production
```

Expected high-level result:

```text
production namespace
        |
        +-- nginx Deployment
               |
               +-- 3 Running Pods
        |
        +-- nginx-service
               |
               +-- ClusterIP
```

## Day 2 Success Criteria

Day 2 is complete when:

```text
Terraform validation succeeds
+
production Namespace exists
+
NGINX Deployment exists
+
3 Pods are Running
+
nginx-service exists
+
Service endpoints point to the NGINX Pods
```

## Next Phase

Day 3 can introduce the container-image and external-access layer:

```text
Application
   |
Docker Image
   |
Amazon ECR
   |
EKS Deployment
   |
ClusterIP Service
   |
AWS Load Balancer Controller
   |
Ingress
   |
Application Load Balancer
```


---

# Amazon EKS - Day 3 Container Image and External Access Plan

Day 3 introduces the container-image and external-access layer for the application.

The target flow is:

```text
Application Source Code
        |
        v
Dockerfile
        |
        v
Docker Image
        |
        v
Amazon ECR
        |
        v
EKS Deployment
        |
        v
ClusterIP Service
        |
        v
AWS Load Balancer Controller
        |
        v
Ingress
        |
        v
Application Load Balancer
        |
        v
Internet User
```

## Day 3 Objective

The goal is to replace the public NGINX image with an application image stored in Amazon ECR and then expose the application externally through an AWS Application Load Balancer.

The main concepts introduced are:

- Docker image build
- Amazon ECR
- Private container image
- EKS image pull
- AWS Load Balancer Controller
- IAM for the controller
- Kubernetes Ingress
- Application Load Balancer
- Public subnet discovery
- ALB health checks
- External application access

## Recommended Implementation Sequence

### Step 1 - Create an Amazon ECR Repository

Create an ECR repository using Terraform.

Example logical flow:

```text
Terraform
   |
   v
Amazon ECR
   |
   v
production-app
```

Validation:

```bash
aws ecr describe-repositories --region us-east-1
```

### Step 2 - Create the Application Dockerfile

Add a Dockerfile for the application.

Example:

```dockerfile
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
```

The application flow becomes:

```text
Application Source
      |
      v
Dockerfile
      |
      v
Docker Image
```

### Step 3 - Build the Docker Image

Build the image locally.

```bash
docker build -t production-app:v1 .
```

Verify:

```bash
docker images
```

### Step 4 - Authenticate Docker to Amazon ECR

Authenticate using AWS CLI.

```bash
aws ecr get-login-password \
  --region us-east-1 \
| docker login \
  --username AWS \
  --password-stdin <ACCOUNT-ID>.dkr.ecr.us-east-1.amazonaws.com
```

### Step 5 - Tag the Docker Image

Tag the local image with the ECR repository URI.

```bash
docker tag production-app:v1 \
<ACCOUNT-ID>.dkr.ecr.us-east-1.amazonaws.com/production-app:v1
```

### Step 6 - Push the Image to Amazon ECR

Push the image:

```bash
docker push \
<ACCOUNT-ID>.dkr.ecr.us-east-1.amazonaws.com/production-app:v1
```

Verify:

```bash
aws ecr list-images \
  --repository-name production-app \
  --region us-east-1
```

### Step 7 - Update the EKS Deployment

Replace the public NGINX image:

```text
nginx:1.27-alpine
```

with the private ECR image:

```text
<ACCOUNT-ID>.dkr.ecr.us-east-1.amazonaws.com/production-app:v1
```

The new flow becomes:

```text
Amazon ECR
    |
    v
EKS Worker Nodes
    |
    v
Deployment
    |
    v
Pods
```

Validate:

```bash
kubectl get pods -n production
kubectl describe pod <pod-name> -n production
```

### Step 8 - Keep the ClusterIP Service

The application remains internally exposed through the existing ClusterIP Service.

```text
nginx-service
      |
      | TCP 80
      |
+-----+-----+
|     |     |
Pod-1 Pod-2 Pod-3
```

The Service remains the stable internal endpoint used by Ingress.

### Step 9 - Configure IAM for AWS Load Balancer Controller

The AWS Load Balancer Controller requires permission to create and manage resources such as:

- Application Load Balancers
- Target Groups
- Listeners
- Listener Rules
- Security Groups
- Resource Tags

Use a dedicated IAM role for the controller rather than granting broad application permissions to the worker-node role.

Conceptually:

```text
AWS Load Balancer Controller
          |
          v
Service Account / Pod Identity
          |
          v
IAM Role
          |
          v
AWS Load Balancing APIs
```

### Step 10 - Add the Helm Provider

Terraform will use the Helm provider to install the AWS Load Balancer Controller into the EKS cluster.

Provider responsibility:

```text
Terraform
|
+-- AWS Provider
|     +-- ECR
|     +-- IAM
|     +-- Subnet Tags
|
+-- Kubernetes Provider
|     +-- Deployment
|     +-- Service
|     +-- Ingress
|
+-- Helm Provider
      +-- AWS Load Balancer Controller
```

### Step 11 - Install AWS Load Balancer Controller

Install the controller into the `kube-system` namespace.

Validate:

```bash
kubectl get deployment \
  -n kube-system \
  aws-load-balancer-controller
```

Also check:

```bash
kubectl get pods -n kube-system
```

### Step 12 - Tag the Public Subnets

The internet-facing ALB needs public subnets in multiple Availability Zones.

The current project already has:

```text
10.10.1.0/24 - us-east-1a
10.10.3.0/24 - us-east-1b
```

The public subnets should be discoverable for external load balancers.

Typical Kubernetes subnet role tag:

```text
kubernetes.io/role/elb = 1
```

Private subnets can use:

```text
kubernetes.io/role/internal-elb = 1
```

### Step 13 - Create Kubernetes Ingress

Create an Ingress resource that routes HTTP traffic to the ClusterIP Service.

Initial routing can remain simple:

```text
/
 |
 v
nginx-service
```

Architecture:

```text
Ingress
   |
   v
nginx-service
   |
+--+--+
|  |  |
Pod Pod Pod
```

### Step 14 - Let the Controller Create the ALB

The AWS Load Balancer Controller watches the Ingress resource.

```text
Kubernetes Ingress
       |
       v
AWS Load Balancer Controller
       |
       v
AWS API
       |
       v
Application Load Balancer
```

The controller creates the required AWS load-balancing resources.

### Step 15 - Validate the Ingress

Run:

```bash
kubectl get ingress -n production
```

Then:

```bash
kubectl describe ingress -n production
```

Expected result:

```text
ADDRESS
k8s-production-xxxx.us-east-1.elb.amazonaws.com
```

### Step 16 - Validate ALB Target Health

Check the target group in AWS and verify the application targets become healthy.

Also validate from Kubernetes:

```bash
kubectl get pods -n production
kubectl get svc -n production
kubectl get ingress -n production
```

If targets are unhealthy, check:

- application port
- Service port
- target port
- readiness probe
- Ingress annotations
- subnet tags
- security groups
- ALB health-check path

### Step 17 - Test External Access

Test using the ALB DNS name.

```bash
curl http://<ALB-DNS-NAME>
```

Or open:

```text
http://<ALB-DNS-NAME>
```

in a browser.

## Day 3 End-to-End Flow

```text
Developer
   |
   v
Application Source
   |
   v
Docker Build
   |
   v
Docker Image
   |
   v
Amazon ECR
   |
   v
EKS Deployment
   |
   v
Application Pods
   |
   v
ClusterIP Service
   |
   v
Ingress
   |
   v
AWS Load Balancer Controller
   |
   v
Application Load Balancer
   |
   v
Internet User
```

## Day 3 Validation Checklist

Day 3 should be considered complete when:

```text
ECR repository exists
+
Application image is pushed to ECR
+
EKS Deployment uses the ECR image
+
Pods are Running and Ready
+
ClusterIP Service has healthy endpoints
+
AWS Load Balancer Controller is Running
+
Public subnets are tagged correctly
+
Ingress is created
+
ALB is provisioned
+
ALB targets are healthy
+
Application is reachable using ALB DNS
```

## Deferred to Later Phases

The following are intentionally not part of the first Day 3 implementation:

- Route 53 custom domain
- ACM HTTPS certificate
- AWS WAF
- HPA
- Karpenter
- EBS CSI / PV / PVC
- Prometheus and Grafana
- Jenkins deployment pipeline

These can be introduced after the basic ECR-to-EKS-to-ALB flow is working correctly.
