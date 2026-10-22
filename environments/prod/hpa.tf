resource "kubernetes_horizontal_pod_autoscaler_v2" "nginx" {
  metadata {
    name      = "nginx-hpa"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  spec {
    min_replicas = 3
    max_replicas = 6

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.nginx.metadata[0].name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = 60
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.nginx
  ]
}
