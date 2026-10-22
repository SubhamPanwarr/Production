# =======================================================
# Kubernetes Workloads
# =======================================================

# -------------------------------------------------------
# Production Namespace
# -------------------------------------------------------

resource "kubernetes_namespace_v1" "production" {
  metadata {
    name = "production"

    labels = {
      environment = "production"
      managed-by  = "terraform"
    }
  }

  depends_on = [
    module.eks
  ]
}

# -------------------------------------------------------
# NGINX Deployment
# -------------------------------------------------------

resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.production.metadata[0].name

    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 3

    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = "1"
        max_unavailable = "1"
      }
    }

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {

        # ------------------------------------------------
        # Scheduling Rules
        # ------------------------------------------------

        affinity {

          # ----------------------------------------------
          # Node Affinity
          # Prefer worker nodes labeled workload=frontend
          # ----------------------------------------------

          node_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100

              preference {
                match_expressions {
                  key      = "workload"
                  operator = "In"
                  values   = ["frontend"]
                }
              }
            }
          }

          # ----------------------------------------------
          # Pod Anti-Affinity
          # Prefer spreading nginx Pods across nodes
          # ----------------------------------------------

          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100

              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"

                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["nginx"]
                  }
                }
              }
            }
          }
        }

        # ------------------------------------------------
        # Service Account
        # ------------------------------------------------

        service_account_name = kubernetes_service_account_v1.production_app.metadata[0].name

        # ------------------------------------------------
        # NGINX Container
        # ------------------------------------------------

        container {
          name  = "nginx"
          image = "523881172609.dkr.ecr.us-east-1.amazonaws.com/production-app:v2"

          port {
            container_port = 80
          }

          # ----------------------------------------------
          # Secrets Manager Mount
          # ----------------------------------------------

          volume_mount {
            name       = "secrets-store-inline"
            mount_path = "/mnt/secrets-store"
            read_only  = true
          }

          # ----------------------------------------------
          # Resources
          # ----------------------------------------------

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }

            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          # ----------------------------------------------
          # Readiness Probe
          # ----------------------------------------------

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }

            initial_delay_seconds = 5
            period_seconds        = 10
          }

          # ----------------------------------------------
          # Liveness Probe
          # ----------------------------------------------

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }

            initial_delay_seconds = 15
            period_seconds        = 20
          }
        }

        # ------------------------------------------------
        # Secrets Store CSI Volume
        # ------------------------------------------------

        volume {
          name = "secrets-store-inline"

          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true

            volume_attributes = {
              secretProviderClass = "production-db-secret"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace_v1.production
  ]
}

# -------------------------------------------------------
# ClusterIP Service
# -------------------------------------------------------

resource "kubernetes_service_v1" "nginx" {
  metadata {
    name      = "nginx-service"
    namespace = kubernetes_namespace_v1.production.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [
    kubernetes_deployment_v1.nginx
  ]
}
