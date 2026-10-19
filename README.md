# Production AWS Infrastructure with Terraform and Amazon EKS

## Project Overview

This project implements a production-style AWS infrastructure using **Terraform** with reusable modules and a multi-VPC architecture.

The project currently covers two layers:

1. **AWS infrastructure layer**
   - VPC
   - Subnets
   - Internet Gateway
   - NAT Gateway
   - Transit Gateway
   - Bastion Host
   - EC2
   - S3
   - VPC Endpoints
   - IAM
   - Amazon RDS

2. **Kubernetes layer**
   - Amazon EKS
   - Managed Node Groups
   - Kubernetes Namespace
   - Deployment
   - ReplicaSet
   - Pods
   - ClusterIP Service
   - Readiness and Liveness Probes
   - Resource Requests and Limits

Terraform is used to manage both the AWS infrastructure and Kubernetes resources.

---

# Architecture Overview

```text
                              INTERNET
                                  |
                           Internet Gateway
                                  |
                    +---------------------------+
                    |           VPC-A           |
                    |       10.10.0.0/16        |
                    +---------------------------+
                         |                |
                  Public Subnets     Private Subnets
                  AZ-A / AZ-B        AZ-A / AZ-B
                         |                |
                    Bastion Host          |
                                          |
                                   +------+------+
                                   |             |
                                  EC2           EKS
                                                |
                                      Managed Node Group
                                         AZ-A / AZ-B
                                                |
                                         Kubernetes Pods
                                                |
                                          ClusterIP
                                                |
                                             Service

                         Amazon RDS MySQL
                               |
                         Private Subnets
                         AZ-A / AZ-B


VPC-A
   |
   |
Transit Gateway
   |
   |
VPC-B
10.20.0.0/16
   |
Private EC2
   |
S3 VPC Endpoint
   |
Amazon S3
```

---

# AWS Network Design

## VPC-A

```text
CIDR: 10.10.0.0/16
```

VPC-A contains the main application infrastructure.

### Public Subnets

```text
10.10.1.0/24
us-east-1a

10.10.3.0/24
us-east-1b
```

These subnets are used for internet-facing infrastructure such as:

- Bastion Host
- NAT Gateway
- Future Application Load Balancer

### Private Subnets

```text
10.10.2.0/24
us-east-1a

10.10.4.0/24
us-east-1b
```

These subnets are used by:

- Private EC2 instances
- Amazon EKS worker nodes
- Amazon RDS subnet group

---

## VPC-B

```text
CIDR: 10.20.0.0/16
```

VPC-B contains private infrastructure and communicates with VPC-A through AWS Transit Gateway.

---

# Transit Gateway

AWS Transit Gateway provides centralized connectivity between VPC-A and VPC-B.

```text
VPC-A
   |
   |
Transit Gateway
   |
   |
VPC-B
```

Routes are configured in both VPCs so resources can communicate through the Transit Gateway.

This architecture is easier to scale than creating multiple individual VPC peering connections when the number of VPCs increases.

---

# Bastion Host

The Bastion Host is deployed in a public subnet in VPC-A.

It provides administrative SSH access to resources located in private subnets.

```text
Administrator Laptop
        |
        | SSH 22
        v
    Bastion Host
        |
        | SSH 22
        v
    Private EC2
```

Private EC2 instances do not need direct SSH access from the internet.

---

# Amazon EC2

Private EC2 instances are deployed inside VPC-A and VPC-B.

Example:

```text
EC2-A
VPC-A
Private IP: 10.10.2.x

EC2-B
VPC-B
Private IP: 10.20.2.x
```

The instances can communicate between VPCs using Transit Gateway routing.

---

# Amazon S3

Amazon S3 is used for application and infrastructure-related object storage.

Example bucket:

```text
subhampanwarr-production-app-data-2026
```

Private infrastructure accesses S3 through an S3 Gateway VPC Endpoint.

```text
Private EC2
     |
     v
S3 VPC Endpoint
     |
     v
Amazon S3
```

Benefits include:

- Private S3 communication
- Reduced dependency on public internet access
- No NAT Gateway requirement for S3 traffic
- Better security
- Potential NAT Gateway cost reduction

---

# IAM for EC2 and S3

EC2 instances use IAM roles instead of storing AWS access keys directly on the server.

```text
EC2
 |
 v
IAM Role
 |
 v
Amazon S3
```

This follows the AWS principle of using temporary credentials and least-privilege access.

---

# Amazon RDS MySQL

Amazon RDS provides the managed relational database layer.

Current configuration:

```text
Engine            : MySQL
Port              : 3306
Storage           : GP3
Allocated Storage : 20 GB
Public Access     : Disabled
Encryption        : Enabled
Backup Retention  : 1 day
Multi-AZ          : Disabled for lab environment
```

For a real production environment, backup retention and Multi-AZ configuration should be selected according to business RTO, RPO, compliance, and availability requirements.

---

# RDS DB Subnet Group

RDS uses private subnets across two Availability Zones.

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
RDS DB Subnet Group
        |
        +---- us-east-1a
        |
        +---- us-east-1b
```

The database remains private.

---

# RDS Security

RDS does not allow direct internet access.

The database security group allows MySQL traffic only from the approved application security group.

```text
Application Security Group
          |
          | TCP 3306
          v
     RDS Security Group
```

Opening MySQL directly to:

```text
0.0.0.0/0
```

should not be used for a production database.

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

Applications should use the RDS DNS endpoint instead of a database IP address because the underlying IP may change.

---

# Testing RDS Connectivity

Because RDS is private, connectivity should be tested from a resource inside the VPC.

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

Test connectivity:

```bash
nc -zv <RDS-ENDPOINT> 3306
```

Connect using MySQL:

```bash
mysql \
  -h <RDS-ENDPOINT> \
  -P 3306 \
  -u <DB_USERNAME> \
  -p
```

---

# Amazon EKS

Amazon EKS provides the Kubernetes orchestration layer for the project.

AWS manages the Kubernetes control plane while worker nodes run inside the existing private subnets in VPC-A.

```text
                  AWS Managed EKS Control Plane
                              |
                    +---------+---------+
                    |                   |
              Private Subnet       Private Subnet
               us-east-1a           us-east-1b
                    |                   |
              Worker Node-1       Worker Node-2
                    |                   |
                  Pods                Pods
```

---

# EKS Managed Node Group

The EKS worker nodes are managed through an EKS Managed Node Group.

Current configuration:

```text
Instance Type : t3.medium
Capacity Type : ON_DEMAND

Minimum Nodes : 2
Desired Nodes : 2
Maximum Nodes : 4
```

Worker nodes are deployed in:

```text
10.10.2.0/24
us-east-1a

10.10.4.0/24
us-east-1b
```

This provides worker-node capacity across multiple Availability Zones.

---

# EKS IAM Configuration

## EKS Control Plane Role

The EKS control plane uses:

```text
AmazonEKSClusterPolicy
```

## Worker Node Role

Managed worker nodes use:

```text
AmazonEKSWorkerNodePolicy
AmazonEC2ContainerRegistryPullOnly
AmazonEKS_CNI_Policy
```

The current implementation attaches VPC CNI permissions to the worker-node role.

This can later be improved by using dedicated workload identity or add-on-specific IAM permissions.

---

# Kubernetes Provider

Terraform also manages Kubernetes resources through the HashiCorp Kubernetes provider.

```text
Terraform
   |
   +---- AWS Provider
   |       |
   |       +---- VPC
   |       +---- IAM
   |       +---- EC2
   |       +---- RDS
   |       +---- EKS
   |
   +---- Kubernetes Provider
           |
           +---- Namespace
           +---- Deployment
           +---- Pods
           +---- Service
```

Terraform authenticates to the EKS API server using the EKS cluster endpoint and certificate authority information.

---

# Kubernetes Namespace

Application workloads are deployed inside the:

```text
production
```

namespace.

```text
EKS Cluster
|
+-- kube-system
|
+-- production
     |
     +-- nginx Deployment
     |
     +-- nginx-service
```

Namespaces provide logical separation of Kubernetes resources.

---

# Kubernetes Deployment

The current Kubernetes workload uses an NGINX Deployment.

```text
Deployment
    |
    v
ReplicaSet
    |
    +---- Pod-1
    +---- Pod-2
    +---- Pod-3
```

Current replica count:

```text
3
```

The Deployment maintains the desired number of Pods.

If a Pod fails, Kubernetes creates a replacement Pod to restore the desired state.

---

# Labels and Selectors

The application Pods use:

```text
app = nginx
```

The Kubernetes Service uses the same selector.

```text
nginx-service
      |
      | selector: app=nginx
      |
   +--+--+
   |  |  |
 Pod Pod Pod
```

Labels and selectors allow Kubernetes resources to identify and communicate with the correct workloads.

---

# ClusterIP Service

The application is currently exposed internally using a ClusterIP Service.

```text
nginx-service
      |
      | TCP 80
      |
+-----+-----+
|     |     |
Pod-1 Pod-2 Pod-3
```

The ClusterIP provides a stable internal endpoint even when individual Pod IP addresses change.

The application is not currently exposed directly to the public internet through Kubernetes.

---

# Resource Requests and Limits

Each NGINX container defines CPU and memory requests and limits.

```text
Requests
CPU    : 100m
Memory : 128Mi

Limits
CPU    : 250m
Memory : 256Mi
```

Requests help Kubernetes decide which node has enough capacity to schedule the Pod.

Limits define the maximum resources that the container can consume.

---

# Readiness Probe

The readiness probe determines whether a Pod is ready to receive application traffic.

```text
Pod Starts
    |
    v
Readiness Probe
    |
 GET /
    |
    v
Ready
    |
    v
Service sends traffic
```

If readiness fails, Kubernetes keeps the Pod out of the Service endpoints until it becomes ready.

---

# Liveness Probe

The liveness probe determines whether the application is still healthy.

```text
Application becomes unhealthy
            |
            v
      Liveness fails
            |
            v
Kubernetes restarts container
```

This helps recover from applications that are running but no longer functioning correctly.

---

# Terraform Project Structure

```text
Production/
│
├── environments/
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── kubernetes.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── variables.tf
│       └── terraform.tfvars
│
├── modules/
│   │
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
│   ├── rds/
│   │
│   └── eks/
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

Benefits include:

- Centralized state storage
- State persistence
- Team collaboration
- Protection against accidental loss of local state

Sensitive and generated Terraform files should not be committed to GitHub.

Examples:

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

Move to the production Terraform environment:

```bash
cd ~/Production/environments/prod
```

Initialize Terraform:

```bash
terraform init
```

When a new provider has been introduced:

```bash
terraform init -upgrade
```

Format:

```bash
terraform fmt -recursive
```

Validate:

```bash
terraform validate
```

Create a plan:

```bash
terraform plan -out=tfplan
```

Generate a readable plan:

```bash
terraform show -no-color tfplan > plan.txt
```

Review:

```bash
less plan.txt
```

Apply only after reviewing the plan:

```bash
terraform apply tfplan
```

---

# EKS and Kubernetes Validation

Configure `kubectl`:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name production-eks-cluster
```

Check the cluster:

```bash
kubectl cluster-info
```

Check worker nodes:

```bash
kubectl get nodes
kubectl get nodes -o wide
```

Check system Pods:

```bash
kubectl get pods -n kube-system
```

Check namespaces:

```bash
kubectl get namespaces
```

Check production workload:

```bash
kubectl get deployment -n production
kubectl get replicasets -n production
kubectl get pods -n production
kubectl get pods -n production -o wide
```

Check the Kubernetes Service:

```bash
kubectl get svc -n production
kubectl describe svc nginx-service -n production
```

Check Service endpoints:

```bash
kubectl get endpoints -n production
```

Expected application structure:

```text
production Namespace
        |
        +---- nginx Deployment
        |        |
        |        +---- 3 Pods
        |
        +---- nginx-service
                 |
                 +---- ClusterIP
```

---

# Terraform State Validation

List all Terraform-managed resources:

```bash
terraform state list
```

Check EKS resources:

```bash
terraform state list | grep eks
```

Check RDS resources:

```bash
terraform state list | grep rds
```

Inspect a resource:

```bash
terraform state show <RESOURCE-ADDRESS>
```

---

# Security Practices

The project currently demonstrates several security practices.

## Private Application Infrastructure

Application infrastructure and EKS worker nodes are deployed in private subnets.

## Private RDS

Amazon RDS is not publicly accessible.

## Security Group Referencing

Database access is controlled using security group references rather than exposing database ports publicly.

## Bastion Access

Administrative SSH connectivity is routed through a Bastion Host.

## IAM Roles

AWS services use IAM roles rather than hard-coded AWS access keys.

## S3 VPC Endpoint

Private resources can access S3 through an AWS Gateway VPC Endpoint.

## Encryption

RDS storage encryption is enabled.

## Multi-AZ Network Design

The architecture contains subnets across multiple Availability Zones to support highly available services such as EKS and RDS.

---

# High Availability

The EKS worker-node layer spans:

```text
us-east-1a
us-east-1b
```

with multiple worker nodes.

The RDS lab currently uses:

```text
Multi-AZ = false
```

to reduce cost.

For a production environment:

```hcl
multi_az = true
```

can be enabled according to availability requirements.

---

# Key Concepts Demonstrated

This project demonstrates practical experience with:

- Infrastructure as Code
- Terraform Modules
- Terraform Remote State
- AWS Provider
- Kubernetes Provider
- Amazon VPC
- Public and Private Subnets
- Multi-AZ design
- Route Tables
- Internet Gateway
- NAT Gateway
- Transit Gateway
- Bastion Host
- Amazon EC2
- IAM Roles
- Amazon S3
- VPC Endpoints
- Amazon RDS
- RDS DB Subnet Groups
- Amazon EKS
- EKS Managed Node Groups
- Kubernetes Namespaces
- Deployments
- ReplicaSets
- Pods
- Labels and Selectors
- ClusterIP Services
- Resource Requests and Limits
- Readiness Probes
- Liveness Probes
- Kubernetes self-healing
- AWS networking
- Private infrastructure design

---

# Current Implementation Flow

```text
Terraform
    |
    +---------------- AWS Infrastructure ----------------+
    |                                                   |
    |                                                   v
    |                                          VPC / IAM / RDS / EKS
    |
    +------------- Kubernetes Provider -----------------+
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
                                             +----------+----------+
                                             |          |          |
                                           Pod-1      Pod-2      Pod-3
                                             \          |          /
                                              \         |         /
                                                ClusterIP Service
```

---

# Author

**Shubham Panwar**

AWS / DevOps Engineer

Technologies used in this project:

```text
AWS
Terraform
Amazon EKS
Kubernetes
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
