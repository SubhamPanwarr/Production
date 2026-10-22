resource "kubernetes_pod_disruption_budget_v1" "nginx" {
  metadata {
    name      = "nginx-pdb"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  spec {
    min_available = "2"

    selector {
      match_labels = {
        app = "nginx"
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.nginx
  ]
}
