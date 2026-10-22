resource "aws_eks_addon" "secrets_store_csi" {
  cluster_name = module.eks.cluster_name

  addon_name = "aws-secrets-store-csi-driver-provider"

  depends_on = [
    module.eks
  ]

  tags = merge(
    local.common_tags,
    {
      Component = "Secrets-Store-CSI"
    }
  )
}
