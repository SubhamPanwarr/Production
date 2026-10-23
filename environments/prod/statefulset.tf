# =======================================================
# STATEFULSET + HEADLESS SERVICE
# =======================================================

# -------------------------------------------------------
# Headless Service
# Required for StatefulSet stable network identity
# -------------------------------------------------------

resource "kubernetes_service_v1" "stateful_web" {
  metadata {
    name      = "stateful-web"
    namespace = kubernetes_namespace_v1.production.metadata[0].name

    labels = {
      app = "stateful-web"
    }
  }

  spec {
    cluster_ip = "None"

    selector = {
      app = "stateful-web"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }

  depends_on = [
    kubernetes_namespace_v1.production
  ]
}

# -------------------------------------------------------
# StatefulSet
# -------------------------------------------------------

resource "kubernetes_stateful_set_v1" "stateful_web" {
  metadata {
    name      = "stateful-web"
    namespace = kubernetes_namespace_v1.production.metadata[0].name

    labels = {
      app = "stateful-web"
    }
  }

  spec {
    service_name = kubernetes_service_v1.stateful_web.metadata[0].name

    replicas = 2

    selector {
      match_labels = {
        app = "stateful-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "stateful-web"
        }
      }

      spec {
        container {
          name  = "stateful-web"
          image = "523881172609.dkr.ecr.us-east-1.amazonaws.com/production-app:v2"

          port {
            container_port = 80
          }

          # ------------------------------------------------
          # Persistent EBS-backed volume
          # ------------------------------------------------

          volume_mount {
            name       = "web-data"
            mount_path = "/usr/share/nginx/html/data"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }

            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }

    # -----------------------------------------------------
    # One PVC per StatefulSet replica
    # -----------------------------------------------------

    volume_claim_template {
      metadata {
        name      = "web-data"
        namespace = kubernetes_namespace_v1.production.metadata[0].name
      }

      spec {
        access_modes = [
          "ReadWriteOnce"
        ]

        storage_class_name = kubernetes_storage_class_v1.ebs_gp3.metadata[0].name

        resources {
          requests = {
            storage = "2Gi"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_v1.stateful_web,
    kubernetes_storage_class_v1.ebs_gp3
  ]
}
