# =======================================================
# BLOCK 2 - CRONJOB
# =======================================================

resource "kubernetes_cron_job_v1" "nginx_health_check" {

  metadata {

    name      = "nginx-health-check"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  spec {

    schedule = "*/15 * * * *"

    concurrency_policy = "Forbid"

    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {

      metadata {}

      spec {

        backoff_limit = 2

        template {

          metadata {
            labels = {
              app = "nginx-health-check"
            }
          }

          spec {

            restart_policy = "Never"

            container {

              name  = "health-check"
              image = "busybox:1.36"

              command = [
                "sh",
                "-c",
                <<-EOT
                  echo "Starting scheduled health check"
                  date

                  wget -qO- http://nginx-service

                  echo ""
                  echo "Health check completed successfully"
                EOT
              ]
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_v1.nginx
  ]
}
