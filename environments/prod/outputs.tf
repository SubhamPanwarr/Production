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
