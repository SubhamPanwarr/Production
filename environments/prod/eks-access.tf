# ======================================================
# EKS Access Entry for DevOps Admin
# ======================================================

resource "aws_eks_access_entry" "devops_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::523881172609:user/devops-admin"
  type          = "STANDARD"

  tags = {
    Environment = "prod"
    Component   = "EKS-Access"
  }

  depends_on = [
    module.eks
  ]
}

resource "aws_eks_access_policy_association" "devops_admin_cluster_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.devops_admin.principal_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.devops_admin
  ]
}
