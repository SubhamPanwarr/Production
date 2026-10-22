module "ecr" {
  source = "../../modules/ecr"

  repository_name = "production-app"

  tags = merge(
    local.common_tags,
    {
      Component = "ECR"
    }
  )
}
