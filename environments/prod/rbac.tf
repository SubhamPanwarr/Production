resource "kubernetes_service_account_v1" "production_reader" {

  metadata {
    name      = "production-reader"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }
}

resource "kubernetes_role_v1" "production_reader" {

  metadata {
    name      = "production-reader-role"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  rule {
    api_groups = [""]

    resources = [
      "pods",
      "services",
      "configmaps"
    ]

    verbs = [
      "get",
      "list",
      "watch"
    ]
  }

  rule {
    api_groups = [
      "apps"
    ]

    resources = [
      "deployments",
      "statefulsets",
      "daemonsets"
    ]

    verbs = [
      "get",
      "list",
      "watch"
    ]
  }
}

resource "kubernetes_role_binding_v1" "production_reader" {

  metadata {
    name      = "production-reader-binding"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.production_reader.metadata[0].name
  }

  subject {
    kind = "ServiceAccount"

    name = kubernetes_service_account_v1.production_reader.metadata[0].name

    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }
}
