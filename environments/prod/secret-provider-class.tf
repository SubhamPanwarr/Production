resource "kubernetes_manifest" "db_secret" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"

    kind = "SecretProviderClass"

    metadata = {
      name      = "production-db-secret"
      namespace = "production"
    }

    spec = {
      provider = "aws"

      parameters = {
        objects = yamlencode([
          {
            objectName = module.rds.master_user_secret_arn
            objectType = "secretsmanager"
          }
        ])
      }
    }
  }

  depends_on = [
    aws_eks_addon.secrets_store_csi
  ]
}
