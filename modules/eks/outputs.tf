output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "node_group_name" {
  description = "EKS managed node group name"
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "IAM role used by EKS worker nodes"
  value       = aws_iam_role.eks_node_role.arn
}


output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}
