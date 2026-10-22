module "aws_load_balancer_controller" {
  source = "../../modules/aws-load-balancer-controller"

  cluster_name = module.eks.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.vpc_a.vpc_id

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  tags = local.common_tags

  depends_on = [
    module.eks
  ]
}
