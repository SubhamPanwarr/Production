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
