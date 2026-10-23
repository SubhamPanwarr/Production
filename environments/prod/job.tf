# =======================================================
# BLOCK 2 - ONE-TIME JOB
# =======================================================

resource "kubernetes_job_v1" "nginx_smoke_test" {

  metadata {

    name      = "nginx-smoke-test"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  spec {

    backoff_limit = 3

    template {

      metadata {
        labels = {
          app = "nginx-smoke-test"
        }
      }

      spec {

        restart_policy = "Never"

        container {

          name  = "smoke-test"
          image = "busybox:1.36"

          command = [
            "sh",
            "-c",
            <<-EOT
              echo "Testing nginx-service..."
              wget -qO- http://nginx-service
              echo ""
              echo "Smoke test passed"
            EOT
          ]
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_v1.nginx
  ]
}
