# Production AWS Infrastructure with Terraform & EKS

## Project Overview

This repository implements a production-style AWS platform using **Terraform** and reusable modules.

The current design includes:

- Multi-VPC networking
- Transit Gateway connectivity
- Bastion-based administrative access
- Private EC2 instances
- Amazon S3 with Gateway VPC Endpoints
- IAM roles for EC2-to-S3 access
- Amazon RDS MySQL in private subnets
- Custom RDS parameter group
- Configurable RDS backup policy
- RDS Performance Insights support
- Same-Region RDS Read Replica support
- Dedicated DR Region networking
- Cross-Region RDS Read Replica support
- Cross-Region automated backup replication support
- Cross-Region manual snapshot copy support
- Amazon EKS with managed worker nodes
- Kubernetes namespace, deployment, pods, probes, resource limits, and ClusterIP service
- Remote Terraform state stored in Amazon S3

---

# High-Level Architecture

```text id="4vbgz7"
                                  INTERNET
                                      |
                               Internet Gateway
                                      |
                         +-------------------------+
                         |   PRIMARY REGION        |
                         |      us-east-1          |
                         +-------------------------+
                                      |
                              VPC-A 10.10.0.0/16
                                      |
                 +--------------------+--------------------+
                 |                                         |
           Public Subnets                            Private Subnets
          us-east-1a / 1b                           us-east-1a / 1b
                 |                                         |
            Bastion Host                    +--------------+--------------+
                                            |                             |
                                          EC2-A                          EKS
                                            |                       Managed Nodes
                                            |                             |
                                            |                           Pods
                                            |                             |
                                            |                       ClusterIP Service
                                            |
                                            | TCP 3306
                                            v
                                  +-------------------+
                                  |  RDS MySQL        |
                                  |  Primary DB       |
                                  +-------------------+
                                      |        |
                           async read |        | automated backups
                         replication  |        |
                                      v        v
                               Same-Region   PITR / Snapshots
                               Read Replica


 VPC-A
   |
Transit Gateway
   |
 VPC-B 10.20.0.0/16
   |
 Private EC2-B
   |
 S3 VPC Endpoint
   |
 Amazon S3


                   CROSS-REGION DISASTER RECOVERY
                   ==============================

                         DR REGION: us-west-2
                                |
                       DR VPC 10.30.0.0/16
                                |
                    +-----------+-----------+
                    |                       |
              Private Subnet A        Private Subnet B
              10.30.1.0/24           10.30.2.0/24
                    |                       |
                    +-----------+-----------+
                                |
                     RDS DR Subnet Group
                                |
              +-----------------+------------------+
              |                                    |
      Cross-Region Read Replica            Cross-Region Backups
              |
        Can be promoted
        during a DR event
```

---

# AWS Network Design

## VPC-A — Primary Application VPC

```text id="34da2c"
CIDR: 10.10.0.0/16
Region: us-east-1
```

### Public Subnets

```text id="c9jssy"
10.10.1.0/24 - us-east-1a
10.10.3.0/24 - us-east-1b
```

The public subnets are used for public-facing or administrative infrastructure such as the Bastion Host.

### Private Subnets

```text id="zyjm86"
10.10.2.0/24 - us-east-1a
10.10.4.0/24 - us-east-1b
```

The private subnets are used by:

- Private EC2 instances
- Amazon EKS worker nodes
- RDS DB subnet group

---

## VPC-B — Secondary Private VPC

```text id="u01qbf"
CIDR: 10.20.0.0/16
Region: us-east-1
```

VPC-B contains private infrastructure and communicates with VPC-A through AWS Transit Gateway.

---

# Transit Gateway

AWS Transit Gateway provides centralized connectivity between VPC-A and VPC-B.

```text id="qo7xro"
VPC-A
   |
   v
Transit Gateway
   |
   v
VPC-B
```

Routes are configured in both VPCs so private resources can communicate through the Transit Gateway.

This design is easier to scale than creating individual VPC peering relationships as the number of VPCs increases.

---

# Bastion Host

The Bastion Host is deployed in the public subnet of VPC-A.

It provides administrative SSH access to EC2 instances running in private subnets.

```text id="9bi9jg"
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

Private EC2 instances do not require direct SSH access from the internet.

---

# Amazon EC2

Private EC2 instances are deployed in VPC-A and VPC-B.

Example architecture:

```text id="tc5p8e"
EC2-A
VPC-A
Private Subnet

EC2-B
VPC-B
Private Subnet
```

The EC2 instances can communicate between VPCs using Transit Gateway routing.

---

# Amazon S3

Amazon S3 is used for application and infrastructure-related object storage.

Private infrastructure accesses S3 through S3 Gateway VPC Endpoints.

```text id="djpvoj"
Private EC2
    |
    v
S3 Gateway VPC Endpoint
    |
    v
Amazon S3
```

Benefits include:

- Private S3 communication
- Reduced dependency on NAT Gateway
- No public internet route required for S3 traffic
- Better network security
- Potential NAT Gateway cost savings

---

# IAM for EC2 and S3

EC2 instances use IAM roles instead of storing AWS access keys directly on the servers.

```text id="2exm51"
EC2
 |
 v
IAM Role
 |
 v
Amazon S3
```

This allows temporary AWS credentials to be used through the EC2 instance profile.

---

# Amazon RDS MySQL

Amazon RDS provides the managed relational database layer.

The primary database is deployed in private subnets inside VPC-A.

Current Terraform configuration:

```text id="hsu06k"
Engine                  : MySQL
Port                    : 3306
Storage                 : GP3
Initial Storage         : 20 GB
Maximum Storage         : 100 GB
Public Access           : Disabled
Storage Encryption      : Enabled
Backup Retention        : 1 day
Multi-AZ                : Disabled for lab
```

Application-to-database connectivity:

```text id="hyj4q2"
EC2-A Security Group
        |
        | TCP 3306
        v
RDS Security Group
        |
        v
RDS MySQL
```

The RDS database is not directly accessible from the internet.

---

# RDS DB Subnet Group

The RDS subnet group contains private subnets from two Availability Zones.

```text id="wb6jy0"
Private Subnet
10.10.2.0/24
us-east-1a

Private Subnet
10.10.4.0/24
us-east-1b
```

Architecture:

```text id="neicjd"
RDS DB Subnet Group
        |
        +---- us-east-1a
        |
        +---- us-east-1b
```

This provides the network foundation required for RDS high-availability capabilities.

---

# RDS Endpoint

Applications connect to RDS using the RDS DNS endpoint.

Example:

```text id="d718om"
prod-mysql.xxxxxxxxx.us-east-1.rds.amazonaws.com
```

MySQL port:

```text id="jx8h0e"
3306
```

Applications should use the endpoint instead of relying on the underlying RDS private IP address.

---

# RDS Custom Parameter Group

The RDS module creates a custom MySQL parameter group.

Configured parameters include:

```text id="o7oqw2"
slow_query_log = 1
long_query_time = 2
```

This helps identify long-running SQL queries for troubleshooting and performance analysis.

The current Terraform configuration uses:

```text id="sk3eyq"
mysql8.0
```

as the parameter group family.

The parameter group family should always match the major MySQL engine version used by the RDS instance.

---

# RDS Backup Policy

The RDS module supports configurable backup settings including:

- Backup retention period
- Preferred backup window
- Maintenance window
- Snapshot tagging
- Automated backup deletion behavior
- Final snapshot behavior
- Deletion protection

Current lab configuration:

```text id="v10r8e"
Backup Retention : 1 day
Backup Window    : 03:00-04:00
Maintenance      : Sun:04:00-Sun:05:00
```

For production environments, backup retention should be selected according to:

- Recovery Point Objective
- Compliance requirements
- Data-retention requirements
- Business requirements

---

# Point-in-Time Recovery

Automated backups provide the foundation for Point-in-Time Recovery.

Example:

```text id="eg6u3i"
Database healthy
      |
      |
10:00
      |
10:20
      |
10:29   <-- Restore here
      |
10:30   Data accidentally deleted
```

A new RDS instance can be restored to a point before the unwanted database change.

---

# Same-Region Read Replica

The RDS module supports a configurable same-Region Read Replica.

```text id="n3o1t1"
                 Application
                    |
          +---------+---------+
          |                   |
        WRITE               READ
          |                   |
          v                   v
     Primary RDS ------> Read Replica
```

The primary database processes:

```text id="bc8jsb"
INSERT
UPDATE
DELETE
```

The Read Replica can be used for:

```text id="2jhvgg"
SELECT
Reports
Dashboards
Read-heavy API requests
```

This helps reduce read load on the primary database.

The Terraform module allows this capability to be enabled as required:

```hcl id="vz8bwg"
create_rds_read_replica = true
```

The default value is:

```hcl id="vyvdm0"
false
```

This gives the environment control over when an additional Read Replica should be created.

---

# RDS Performance Insights

The Terraform module includes support for RDS Performance Insights.

It can be enabled as required:

```hcl id="tdvdke"
enable_performance_insights = true
```

Performance Insights helps investigate:

- DB load
- Expensive SQL queries
- Wait events
- Database users
- Database performance bottlenecks

Conceptually:

```text id="hcsqbx"
Application Slow
       |
       v
Performance Insights
       |
       +---- DB Load
       |
       +---- Top SQL
       |
       +---- Wait Events
       |
       +---- Database Users
```

---

# Disaster Recovery Region

The architecture contains a second AWS provider for disaster recovery.

```text id="1i4ay2"
Primary Region
us-east-1

DR Region
us-west-2
```

Terraform provider design:

```text id="msx9w3"
aws
    |
    +---- us-east-1

aws.dr
    |
    +---- us-west-2
```

Resources that belong to the DR Region use the aliased `aws.dr` provider.

---

# DR VPC

Terraform creates a separate VPC in the DR Region.

```text id="rnqs87"
CIDR: 10.30.0.0/16
Region: us-west-2
```

Private subnets:

```text id="b6epcj"
10.30.1.0/24
us-west-2a

10.30.2.0/24
us-west-2b
```

Architecture:

```text id="8o01to"
DR VPC
10.30.0.0/16
      |
      +---- Private Subnet A
      |
      +---- Private Subnet B
```

These subnets form the DR RDS DB subnet group.

---

# DR KMS Encryption

The DR module creates a dedicated AWS KMS key.

```text id="w1fq51"
RDS DR Resources
       |
       v
DR KMS Key
```

The KMS key can be used for encrypted cross-Region database resources and backup copies.

---

# Cross-Region Read Replica

The RDS DR module supports a configurable cross-Region Read Replica.

Architecture:

```text id="ykb9j8"
Primary Region
us-east-1

Primary RDS
     |
     | Asynchronous replication
     |
     v

DR Region
us-west-2

Cross-Region Read Replica
```

If a regional disaster occurs, the replica can be promoted to a standalone database.

```text id="f31imv"
Cross-Region Replica
         |
         | Promote
         v
New Standalone Primary
```

The capability can be enabled through:

```hcl id="90bq9z"
create_cross_region_replica = true
```

The default value is:

```hcl id="xq7btm"
false
```

This allows the same Terraform codebase to support both lower-cost lab deployments and more complete DR configurations.

---

# Cross-Region Automated Backups

The DR module supports configurable automated backup replication to the DR Region.

```text id="w9mhjj"
Primary RDS
    |
    | Snapshots
    | Transaction Logs
    v
DR Region
    |
Automated Backup Copies
```

This provides another disaster-recovery method in addition to the cross-Region Read Replica.

It can be enabled through:

```hcl id="fp3was"
enable_cross_region_backups = true
```

---

# Cross-Region Snapshot Copy

The DR module includes support for manual cross-Region snapshot copy.

Architecture:

```text id="gs4jl9"
Primary RDS
    |
    v
Manual Snapshot
    |
    | Cross-Region Copy
    v
DR Region Snapshot
```

This capability can be used for:

- DR testing
- Pre-deployment recovery points
- Database migration
- Manual backup exercises

---

# Amazon EKS

Amazon EKS provides the Kubernetes orchestration layer.

AWS manages the Kubernetes control plane while worker nodes run inside private VPC-A subnets.

```text id="v28ht2"
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

---

# EKS Managed Node Group

Current node group configuration:

```text id="nlh57b"
Instance Type : t3.medium
Capacity Type : ON_DEMAND

Minimum Nodes : 2
Desired Nodes : 2
Maximum Nodes : 4
```

The nodes are distributed across two private subnets.

---

# Kubernetes Workload

The Kubernetes layer includes:

- Namespace
- Deployment
- ReplicaSet
- Pods
- ClusterIP Service
- Resource requests
- Resource limits
- Readiness probe
- Liveness probe

Application flow:

```text id="fyyl9g"
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
    ClusterIP Service
```

The application is currently exposed internally using a ClusterIP Service.

---

# Readiness Probe

The readiness probe checks whether a Pod is ready to receive traffic.

```text id="39bq3l"
Pod starts
    |
    v
Readiness Probe
    |
    v
Application Ready
    |
    v
Service sends traffic
```

If the readiness check fails, Kubernetes does not send Service traffic to that Pod.

---

# Liveness Probe

The liveness probe checks whether the application is still functioning.

```text id="krwmbn"
Application becomes unhealthy
          |
          v
     Liveness fails
          |
          v
Container restarted
```

---

# Resource Requests and Limits

Application containers define CPU and memory requests and limits.

Example:

```text id="6o606u"
Requests
CPU    : 100m
Memory : 128Mi

Limits
CPU    : 250m
Memory : 256Mi
```

Requests help Kubernetes schedule Pods.

Limits prevent containers from consuming resources beyond their configured maximum.

---

# Terraform Project Structure

```text id="h7mi03"
Production/
│
├── environments/
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── rds-dr.tf
│       ├── kubernetes.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── variables.tf
│       └── terraform.tfvars
│
├── modules/
│   ├── vpc/
│   ├── ec2/
│   ├── bastion/
│   ├── transit-gateway/
│   ├── s3/
│   ├── vpc-endpoint/
│   ├── iam-ec2-s3/
│   ├── rds/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── rds-dr/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
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

Benefits:

- Centralized state storage
- State persistence
- Team collaboration
- Protection from accidental loss of local state

Generated and sensitive Terraform files should not be committed to GitHub.

Examples:

```text id="3fj6gv"
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
*.tfvars
tfplan
plan.txt
```

---

# EKS Validation

Configure `kubectl`:

```bash id="5hf0vv"
aws eks update-kubeconfig \
  --region us-east-1 \
  --name production-eks-cluster
```

Check the cluster:

```bash id="up7uc0"
kubectl cluster-info
```

Check nodes:

```bash id="t31arh"
kubectl get nodes
kubectl get nodes -o wide
```

Check application Pods:

```bash id="jumh3r"
kubectl get pods -n production
```

Check deployment:

```bash id="um0pe6"
kubectl get deployment -n production
```

Check Service:

```bash id="7jo9ma"
kubectl get svc -n production
```

Check Service endpoints:

```bash id="fe445y"
kubectl get endpoints -n production
```

---

# Author

**Shubham Panwar**

AWS / DevOps Engineer

Technologies used in this project:

```text id="2oo3rh"
AWS
Terraform
Amazon EKS
Kubernetes
EC2
VPC
RDS
S3
Transit Gateway
IAM
KMS
Linux
Git
GitHub
Networking
```
