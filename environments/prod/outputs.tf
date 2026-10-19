output "transit_gateway_id" {
  value = module.transit_gateway.transit_gateway_id
}

output "vpc_a_id" {
  value = module.vpc_a.vpc_id
}

output "vpc_b_id" {
  value = module.vpc_b.vpc_id
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "ec2_a_private_ip" {
  value = module.ec2_a.private_ip
}

output "ec2_b_private_ip" {
  value = module.ec2_b.private_ip
}

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "s3_bucket_arn" {
  value = module.s3.bucket_arn
}

output "vpc_a_s3_endpoint_id" {
  value = module.s3_endpoint_vpc_a.vpc_endpoint_id
}

output "vpc_b_s3_endpoint_id" {
  value = module.s3_endpoint_vpc_b.vpc_endpoint_id
}


output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_node_group_name" {
  value = module.eks.node_group_name
}


output "kubernetes_namespace" {
  value = kubernetes_namespace_v1.production.metadata[0].name
}

output "nginx_service_name" {
  value = kubernetes_service_v1.nginx.metadata[0].name
}

# =======================================================
# RDS Outputs
# =======================================================

output "rds_primary_endpoint" {
  description = "Primary RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_primary_arn" {
  description = "Primary RDS ARN"
  value       = module.rds.db_instance_arn
}

output "rds_parameter_group" {
  value = module.rds.parameter_group_name
}

output "rds_read_replica_endpoint" {
  description = "Same-region read replica endpoint"
  value       = module.rds.read_replica_endpoint
}

output "rds_cross_region_replica_endpoint" {
  description = "Cross-region DR replica endpoint"
  value       = module.rds_dr.cross_region_replica_endpoint
}

output "rds_dr_kms_key_arn" {
  value = module.rds_dr.dr_kms_key_arn
}
