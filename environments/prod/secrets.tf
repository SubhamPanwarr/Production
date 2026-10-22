module "eks_secrets_access" {
  source = "../../modules/eks-secrets-access"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace            = kubernetes_namespace_v1.production.metadata[0].name
  service_account_name = "production-app"

  secret_arn = module.rds.master_user_secret_arn

  tags = local.common_tags
}

resource "kubernetes_service_account_v1" "production_app" {
  metadata {
    name      = "production-app"
    namespace = kubernetes_namespace_v1.production.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = module.eks_secrets_access.role_arn
    }
  }
}
