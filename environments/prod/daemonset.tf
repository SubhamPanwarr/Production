# =======================================================
# BLOCK 2 - DAEMONSET
# =======================================================

resource "kubernetes_daemon_set_v1" "node_observer" {

  metadata {

    name      = "node-observer"
    namespace = kubernetes_namespace_v1.production.metadata[0].name

    labels = {
      app = "node-observer"
    }
  }

  spec {

    selector {
      match_labels = {
        app = "node-observer"
      }
    }

    template {

      metadata {
        labels = {
          app = "node-observer"
        }
      }

      spec {

        # Allows DaemonSet to also run on our
        # dedicated frontend nodes.
        toleration {
          key      = "dedicated"
          operator = "Equal"
          value    = "frontend"
          effect   = "NoSchedule"
        }

        container {

          name  = "node-observer"
          image = "busybox:1.36"

          command = [
            "sh",
            "-c",
            "while true; do echo Node observer running on $(hostname); sleep 60; done"
          ]

          resources {

            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }

            limits = {
              cpu    = "50m"
              memory = "32Mi"
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
