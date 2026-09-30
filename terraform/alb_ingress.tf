# =============================================================================
# ALB INGRESS - Internet-facing Application Load Balancer
# =============================================================================
#
# Architecture:
#   Internet → ALB (this Ingress) → ingress-nginx-controller (ClusterIP)
#                                         ↓
#                              retail-store apps (nginx Ingresses)
#
# The AWS Load Balancer Controller (enabled in addons.tf) watches for Ingress
# resources with ingressClassName: alb and provisions an ALB for them.
#
# The ingress-nginx-controller service type is ClusterIP. The ALB routes
# traffic to it via IP target type using the pod's private IP directly.
# This avoids the need for NodePort and works well with EKS Auto Mode.
# =============================================================================

resource "kubectl_manifest" "alb_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "alb-ingress-nginx"
      namespace = "ingress-nginx"
      annotations = {
        # AWS Load Balancer Controller annotations
        "kubernetes.io/ingress.class"                    = "alb"
        "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"          = "ip"
        "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ HTTP = 80 }])
        "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz"
        "alb.ingress.kubernetes.io/healthcheck-port"     = "10254"
        "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
        "alb.ingress.kubernetes.io/success-codes"        = "200"
        "alb.ingress.kubernetes.io/load-balancer-name"   = "retail-store-nginx"
        "alb.ingress.kubernetes.io/subnets"              = join(",", module.vpc.public_subnets)
        "alb.ingress.kubernetes.io/tags"                 = "Project=retail-store,Environment=${var.environment},ManagedBy=terraform"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [
        {
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "ingress-nginx-controller"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })

  depends_on = [module.eks_addons]
}
