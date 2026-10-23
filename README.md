# Production AWS Infrastructure with Terraform, EKS, ALB, ECR, RDS, EBS CSI & Kubernetes

## Project Overview

This repository implements a production-style AWS and Kubernetes platform using **Terraform** and reusable modules.

The project is a hands-on DevOps lab covering infrastructure provisioning, networking, Kubernetes scheduling, workload management, persistent storage, RBAC, secrets integration, ingress, disaster recovery, and operational troubleshooting.

The current implementation runs primarily in **us-east-1**, with disaster-recovery resources in **us-west-2**.

---

## Current Implementation Status

### Completed

- Multi-VPC AWS networking
- Public and private subnets across Availability Zones
- Internet Gateway and NAT Gateway
- Bastion host and private EC2 instances
- AWS Transit Gateway connectivity
- S3 Gateway VPC Endpoints
- IAM roles for EC2 and Kubernetes workloads
- Amazon RDS MySQL
- AWS Secrets Manager integration
- RDS DR/KMS configuration
- Amazon ECR
- Amazon EKS
- General-purpose EKS managed node group
- Dedicated frontend EKS managed node group
- Kubernetes node affinity
- Pod anti-affinity
- Taints and tolerations
- Kubernetes Deployment and ClusterIP Service
- StatefulSet and headless Service
- DaemonSet
- Job
- CronJob
- Horizontal Pod Autoscaler configuration
- Pod Disruption Budget
- AWS Load Balancer Controller
- Internet-facing ALB through Kubernetes Ingress
- Secrets Store CSI Driver
- AWS Secrets Manager CSI provider
- IRSA-based secret access
- Amazon EBS CSI Driver
- gp3 StorageClass
- Dynamic PVC/PV provisioning
- Kubernetes RBAC
- Amazon VPC CNI managed EKS add-on
- VPC CNI NetworkPolicy capability enabled
- CoreDNS service discovery validation
- Terraform remote state in Amazon S3

### Next Step

The VPC CNI NetworkPolicy engine is enabled, but the application-level Kubernetes **NetworkPolicy resource is not yet part of the repository**. That is the next Block 3 implementation step.

---

# High-Level Architecture

```text
                                    INTERNET
                                        |
                                        v
                               Internet Gateway
                                        |
                    +-------------------+-------------------+
                    |                                       |
                    v                                       v
            Public Subnet AZ-A                      Public Subnet AZ-B
             10.10.1.0/24                            10.10.3.0/24
                    |                                       |
                    +-------------------+-------------------+
                                        |
                               Internet-facing ALB
                                        |
                                        v
                             Kubernetes ALB Ingress
                                        |
                                        v
                              nginx-service :80
                                        |
                         +--------------+--------------+
                         |              |              |
                         v              v              v
                      nginx-1        nginx-2        nginx-3
                         |
                         +---- Secrets Store CSI ----> AWS Secrets Manager
                         |
                         +---- production-app ServiceAccount


                         Amazon EKS
                             |
             +---------------+----------------+
             |                                |
             v                                v
   General-purpose Node Group        Dedicated Frontend Node Group
       2 x t3.small                     1 x t3.small
       min=2/max=4                      min=1/max=2
             |                                |
             |                         label: workload=frontend
             |                         label: environment=production
             |                         taint: dedicated=frontend:NoSchedule
             |                                |
             |                                +-- nginx Pods
             |
             +-- stateful-web-0
             +-- stateful-web-1
             +-- system workloads

DaemonSet node-observer runs across eligible nodes.


StatefulSet persistent storage
------------------------------

stateful-web-0 ---- PVC ---- PV ---- gp3 EBS volume
stateful-web-1 ---- PVC ---- PV ---- gp3 EBS volume


VPC-A 10.10.0.0/16
        |
        v
Transit Gateway
        |
        v
VPC-B 10.20.0.0/16


Primary Region : us-east-1
DR Region      : us-west-2
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

Used for:

- Bastion Host
- NAT Gateway
- Internet-facing Application Load Balancer

Public subnets are tagged for AWS Load Balancer Controller discovery:

```text
kubernetes.io/role/elb = 1
```

### Private Subnets

```text
10.10.2.0/24 - us-east-1a
10.10.4.0/24 - us-east-1b
```

Used for:

- Private EC2 instances
- EKS managed node groups
- Stateful workloads
- RDS subnet group

Private subnet tagging:

```text
kubernetes.io/role/internal-elb = 1
```

---

# NAT Gateway

EKS worker nodes run in private subnets without public IP addresses.

Private workloads use the NAT Gateway for outbound access such as:

- EKS bootstrap
- Pulling container images
- AWS public API access
- Package downloads
- External service access

Route:

```text
Private Node
    |
    v
Private Route Table
    |
    | 0.0.0.0/0
    v
NAT Gateway
    |
    v
Internet Gateway
    |
    v
Internet
```

A practical issue solved during the project was an EKS `NodeCreationFailure` caused by missing outbound connectivity from private subnets. Adding the NAT Gateway and default private route allowed worker nodes to join the EKS cluster successfully.

---

# VPC-B — Secondary Private VPC

```text
CIDR   : 10.20.0.0/16
Region : us-east-1
```

VPC-B contains private infrastructure and communicates with VPC-A through AWS Transit Gateway.

---

# AWS Transit Gateway

Transit Gateway provides centralized communication between VPC-A and VPC-B.

```text
VPC-A
  |
  v
Transit Gateway
  |
  v
VPC-B
```

Routes are configured in both directions so resources can communicate across the VPCs.

---

# Bastion Host

The Bastion Host is deployed in the VPC-A public subnet.

```text
Administrator
     |
     | SSH
     v
Bastion Host
     |
     | private routing
     v
Private Resources
```

This prevents application EC2 instances from requiring public SSH exposure.

---

# Amazon S3 and VPC Endpoints

The project uses an S3 bucket for application/infrastructure data.

Both VPC-A and VPC-B include S3 Gateway VPC Endpoints.

```text
Private Resource
      |
      v
S3 Gateway Endpoint
      |
      v
Amazon S3
```

Benefits:

- Private S3 connectivity
- Reduced NAT usage
- Better security
- Lower potential NAT data-processing cost

---

# Amazon RDS MySQL

The primary RDS database runs in private VPC-A subnets.

Current design includes:

```text
Engine             : MySQL 8.0
Instance Class     : db.t3.micro
Storage            : GP3
Initial Storage    : 20 GB
Maximum Storage    : 100 GB
Port               : 3306
Public Access      : Disabled
Storage Encryption : Enabled
Multi-AZ           : Disabled for lab
```

The project also uses:

- Custom DB parameter group
- Slow-query logging configuration
- Performance Insights option
- Automated backups
- Optional same-Region read replica
- DR-related resources in us-west-2

RDS master credentials are managed by AWS rather than hardcoded:

```hcl
manage_master_user_password = true
```

---

# AWS Secrets Manager + IRSA

RDS credentials are consumed by Kubernetes through AWS Secrets Manager and the Secrets Store CSI Driver.

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
/mnt/secrets-store
```

The password is not stored directly in:

- Git
- Docker images
- Kubernetes Deployment source
- plain-text Terraform variables

---

# Amazon EKS

AWS manages the Kubernetes control plane while worker nodes run inside VPC-A private subnets.

The cluster has two managed node-group types.

## General-purpose Node Group

```text
Instance Type : t3.small
Capacity Type : ON_DEMAND
Minimum       : 2
Desired       : 2
Maximum       : 4
```

This node group runs general and stateful workloads.

## Dedicated Frontend Node Group

```text
Instance Type : t3.small
Capacity Type : ON_DEMAND
Minimum       : 1
Desired       : 1
Maximum       : 2
```

Labels:

```text
workload=frontend
environment=production
```

Taint:

```text
dedicated=frontend:NoSchedule
```

This separates frontend application workloads from general workloads.

---

# Kubernetes Deployment

The main application is deployed as an NGINX-based workload using the ECR image:

```text
production-app:v2
```

Deployment configuration:

```text
Replicas : 3

Requests:
CPU      : 100m
Memory   : 128Mi

Limits:
CPU      : 250m
Memory   : 256Mi
```

The Deployment also uses:

- RollingUpdate strategy
- Readiness probe
- Liveness probe
- ServiceAccount
- Secrets Store CSI volume
- Node affinity
- Pod anti-affinity
- Toleration

---

# Node Affinity

The NGINX Deployment uses required node affinity:

```text
workload In [frontend]
```

This forces NGINX Pods onto nodes belonging to the dedicated frontend node group.

```text
nginx Pod
   |
   | required node affinity
   v
Node with workload=frontend
```

---

# Pod Anti-Affinity

NGINX uses preferred Pod anti-affinity with:

```text
topologyKey = kubernetes.io/hostname
```

This tells Kubernetes to prefer spreading replicas across different nodes when multiple suitable frontend nodes are available.

Because the current frontend node group has a desired capacity of one, all three replicas can currently run on the same frontend node. If the node group scales out, the scheduler can prefer spreading the replicas.

---

# Taints and Tolerations

Frontend nodes are protected with:

```text
dedicated=frontend:NoSchedule
```

The NGINX workload includes a matching toleration.

Conceptually:

```text
Frontend Node
taint = dedicated=frontend:NoSchedule
          |
          +-- ordinary Pod --------X blocked
          |
          +-- nginx Pod -----------✓ tolerated
```

---

# StatefulSet

The project includes a two-replica StatefulSet:

```text
stateful-web-0
stateful-web-1
```

It uses a headless Service:

```text
stateful-web
clusterIP = None
```

The StatefulSet demonstrates:

- Stable Pod identity
- Ordered StatefulSet naming
- Per-replica persistent storage
- EBS-backed PVC provisioning

---

# Amazon EBS CSI Driver

The EKS cluster uses the Amazon EBS CSI Driver as an EKS add-on.

IAM access is provided through an OIDC/IRSA role using:

```text
AmazonEBSCSIDriverPolicyV2
```

The driver dynamically creates and attaches EBS volumes for Kubernetes PVCs.

---

# StorageClass, PVC and PV

The project defines:

```text
StorageClass : ebs-gp3
Provisioner  : ebs.csi.aws.com
Type         : gp3
Encrypted    : true
Binding Mode : WaitForFirstConsumer
Expansion    : enabled
```

Each StatefulSet replica requests:

```text
2Gi
ReadWriteOnce
```

Result:

```text
stateful-web-0
      |
      v
web-data-stateful-web-0
      |
      v
PersistentVolume
      |
      v
gp3 EBS volume


stateful-web-1
      |
      v
web-data-stateful-web-1
      |
      v
PersistentVolume
      |
      v
gp3 EBS volume
```

The EBS volumes are created in the Availability Zone where the consuming Pod is scheduled.

---

# DaemonSet

The project includes:

```text
node-observer
```

The DaemonSet runs one BusyBox observer Pod per eligible node.

It includes the frontend toleration so it can also run on the dedicated tainted frontend node.

This demonstrates node-level agents such as:

- monitoring agents
- log collectors
- security agents
- networking agents

---

# Kubernetes Job

A one-time smoke-test Job validates the NGINX ClusterIP Service.

```text
nginx-smoke-test
```

It performs:

```bash
wget -qO- http://nginx-service
```

The Job was validated successfully against the application service.

---

# Kubernetes CronJob

The project runs a scheduled health check every 15 minutes.

```text
nginx-health-check
Schedule: */15 * * * *
ConcurrencyPolicy: Forbid
```

The CronJob performs an HTTP request against `nginx-service` and records whether the scheduled check succeeded.

---

# Kubernetes RBAC

The project includes namespace-scoped read-only RBAC.

ServiceAccount:

```text
production-reader
```

Role:

```text
production-reader-role
```

RoleBinding:

```text
production-reader-binding
```

Allowed actions:

```text
get
list
watch
```

Allowed resources include:

```text
pods
services
configmaps
deployments
statefulsets
daemonsets
```

Example validation:

```bash
kubectl auth can-i get pods   --as=system:serviceaccount:production:production-reader   -n production
```

Expected:

```text
yes
```

Deletion remains denied:

```bash
kubectl auth can-i delete pods   --as=system:serviceaccount:production:production-reader   -n production
```

Expected:

```text
no
```

This demonstrates Kubernetes least-privilege access.

---

# Amazon VPC CNI

The project now manages the Amazon VPC CNI as an EKS managed add-on.

NetworkPolicy support is enabled through:

```hcl
configuration_values = jsonencode({
  enableNetworkPolicy = "true"
})
```

The VPC CNI assigns VPC-routable IP addresses directly to Pods.

Example concept:

```text
VPC Private Subnet
      |
      +-- Node IP
      |
      +-- Pod IP
      |
      +-- Pod IP
```

The NetworkPolicy engine is enabled, but an application-level `network-policy.tf` resource is intentionally left for the next implementation step.

---

# CoreDNS

CoreDNS provides Kubernetes internal DNS and service discovery.

Example:

```text
Pod
 |
 | requests nginx-service
 v
CoreDNS
 |
 v
nginx-service.production.svc.cluster.local
 |
 v
ClusterIP
 |
 v
NGINX Pods
```

The cluster DNS service is:

```text
kube-dns
ClusterIP: 172.20.0.10
```

CoreDNS was validated by successfully resolving:

```text
nginx-service.production.svc.cluster.local
kubernetes.default.svc.cluster.local
```

---

# AWS Load Balancer Controller

The AWS Load Balancer Controller watches Kubernetes Ingress resources and provisions an Application Load Balancer.

Current Ingress design:

```text
Scheme       : internet-facing
Target Type  : ip
Listener     : HTTP 80
Health Path  : /
IngressClass : alb
```

Request flow:

```text
Internet
   |
   v
Application Load Balancer
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

With target type `ip`, the ALB registers Kubernetes Pod IP addresses directly.

---

# Amazon ECR

Amazon ECR stores the application container image.

Repository:

```text
production-app
```

Current Kubernetes workloads use:

```text
523881172609.dkr.ecr.us-east-1.amazonaws.com/production-app:v2
```

Image flow:

```text
Dockerfile
    |
    v
docker build
    |
    v
Amazon ECR
    |
    v
EKS
```

---

# Disaster Recovery

A secondary AWS provider is configured for:

```text
Primary Region : us-east-1
DR Region      : us-west-2
```

The DR design includes:

- DR VPC
- Private DR subnets
- RDS subnet group
- KMS key
- RDS disaster-recovery configuration
- Cross-Region recovery preparation

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
|       |-- cronjob.tf
|       |-- daemonset.tf
|       |-- ebs-csi.tf
|       |-- ecr.tf
|       |-- eks-access.tf
|       |-- hpa.tf
|       |-- ingress.tf
|       |-- job.tf
|       |-- kubernetes.tf
|       |-- load-balancer-controller.tf
|       |-- main.tf
|       |-- outputs.tf
|       |-- pdb.tf
|       |-- providers.tf
|       |-- rbac.tf
|       |-- rds-dr.tf
|       |-- secret-provider-class.tf
|       |-- secrets-csi.tf
|       |-- secrets.tf
|       |-- statefulset.tf
|       |-- storage.tf
|       |-- variables.tf
|       `-- vpc-cni.tf
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
- Persistent storage
- Team collaboration
- Reduced risk of local state loss

Sensitive/generated Terraform files should not be committed.

Examples:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
tfplan*
plan*.txt
backend.hcl
tfstate-backup-*.json
```

---

# Deployment

From the production environment:

```bash
cd environments/prod

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Configure kubectl:

```bash
aws eks update-kubeconfig   --region us-east-1   --name production-eks-cluster
```

---

# Validation Commands

## EKS Nodes

```bash
kubectl get nodes -L workload,environment
```

Current design:

```text
2 general-purpose nodes
1 dedicated frontend node
```

## Application Pods

```bash
kubectl get pods -n production -o wide
```

Validate:

- 3 NGINX Pods Running
- 2 StatefulSet Pods Running
- node-observer DaemonSet Pods Running
- completed Jobs/CronJobs visible

## StatefulSet

```bash
kubectl get statefulset -n production
```

Expected:

```text
stateful-web   2/2
```

## DaemonSet

```bash
kubectl get daemonset -n production
```

## Jobs

```bash
kubectl get jobs -n production
```

## CronJobs

```bash
kubectl get cronjobs -n production
```

## StorageClass

```bash
kubectl get storageclass
```

Expected:

```text
ebs-gp3   ebs.csi.aws.com
```

## PVCs

```bash
kubectl get pvc -n production
```

Expected:

```text
web-data-stateful-web-0   Bound   2Gi
web-data-stateful-web-1   Bound   2Gi
```

## PVs

```bash
kubectl get pv
```

## EBS CSI

```bash
kubectl get pods -n kube-system | grep ebs
```

## RBAC

```bash
kubectl auth can-i get pods   --as=system:serviceaccount:production:production-reader   -n production

kubectl auth can-i delete pods   --as=system:serviceaccount:production:production-reader   -n production
```

Expected:

```text
get pods    -> yes
delete pods -> no
```

## VPC CNI Add-on

```bash
aws eks list-addons   --cluster-name production-eks-cluster   --region us-east-1
```

## CoreDNS

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get service kube-dns -n kube-system
```

DNS test:

```bash
kubectl run dns-test   -n production   --image=busybox:1.36   --restart=Never   --rm -it   -- nslookup nginx-service
```

## Ingress

```bash
kubectl get ingress -n production
```

## ALB

```bash
curl -I http://<ALB-DNS-NAME>
```

Expected:

```text
HTTP/1.1 200 OK
```

---

# Practical Troubleshooting Covered

## EKS NodeCreationFailure

Problem:

```text
NodeCreationFailure
Instances failed to join the kubernetes cluster
```

Root cause:

```text
Private EKS nodes had no outbound NAT path
```

Fix:

```text
Elastic IP
+
NAT Gateway
+
0.0.0.0/0 private route
```

---

## ALB Subnet Discovery

Problem:

```text
subnets count less than minimal required count: 1 < 2
```

Fix:

- Added ELB discovery tag to second public subnet
- Configured both public subnet IDs for the Ingress

---

## EKS vCPU Quota During Dedicated Node Creation

During creation of the dedicated frontend node group, Auto Scaling initially failed with:

```text
VcpuLimitExceeded
```

The account Standard On-Demand vCPU quota was reached.

The lab was adjusted so the dedicated frontend node group uses:

```text
min     = 1
desired = 1
max     = 2
```

This allowed the frontend node to launch while remaining within the available quota.

---

## Pod Scheduling — Too Many Pods

When the first dedicated frontend node used a smaller instance type, NGINX Pods remained Pending because the node reached its Pod capacity.

The workload node was moved to:

```text
t3.small
```

The resulting frontend node had sufficient Pod capacity for the application and supporting DaemonSets.

---

## Terraform StatefulSet Identity Repair

A Kubernetes provider state identity mismatch occurred while managing the StatefulSet.

The recovery process included:

```bash
terraform state pull
terraform state rm kubernetes_stateful_set_v1.stateful_web
terraform import kubernetes_stateful_set_v1.stateful_web production/stateful-web
```

After re-importing the existing StatefulSet, Terraform could manage it normally again.

---

## StatefulSet Persistent Storage Migration

Adding `volume_claim_template` required replacement of the existing lab StatefulSet.

The replacement created:

- 2 PVCs
- 2 PVs
- 2 encrypted gp3 EBS volumes

The new StatefulSet completed successfully at:

```text
2/2 Ready
```

---

# Security Design

Current security controls include:

- EKS worker nodes in private subnets
- RDS without public access
- RDS credentials managed in AWS Secrets Manager
- IRSA for Pod-to-AWS authorization
- Secrets mounted read-only through CSI
- EC2 IAM roles instead of embedded AWS keys
- S3 Gateway VPC Endpoints
- Bastion-separated administrative access
- Terraform remote state
- Namespace-scoped Kubernetes RBAC
- EBS encryption
- Dedicated workload node taints
- VPC CNI NetworkPolicy capability enabled
- Sensitive/generated Terraform artifacts excluded from Git

---

# Kubernetes Concepts Demonstrated

```text
Namespaces
Deployments
ReplicaSets
Pods
Services
Ingress
Readiness Probes
Liveness Probes
Resource Requests and Limits
Rolling Updates
Node Affinity
Pod Anti-Affinity
Taints
Tolerations
StatefulSets
Headless Services
DaemonSets
Jobs
CronJobs
StorageClasses
PersistentVolumeClaims
PersistentVolumes
EBS CSI
ServiceAccounts
Roles
RoleBindings
RBAC
CoreDNS
VPC CNI
Pod Disruption Budgets
Horizontal Pod Autoscaling
```

---

# Technologies Used

```text
AWS
Terraform
Amazon EKS
Kubernetes
Amazon VPC CNI
CoreDNS
Amazon EBS CSI Driver
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
