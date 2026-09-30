# =============================================================================
# EKS ADD-ONS AND EXTENSIONS
# =============================================================================

module "eks_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  # Cluster information
  cluster_name      = module.retail_app_eks.cluster_name
  cluster_endpoint  = module.retail_app_eks.cluster_endpoint
  cluster_version   = module.retail_app_eks.cluster_version
  oidc_provider_arn = module.retail_app_eks.oidc_provider_arn

  # =============================================================================
  # CERT-MANAGER - SSL Certificate Management
  # =============================================================================
  enable_cert_manager = true
  cert_manager = {
    most_recent = true
    namespace   = "cert-manager"
  }

  # =============================================================================
  # NGINX INGRESS CONTROLLER - L7 proxy (ClusterIP only, ALB fronts it)
  # NLB creation is not supported in this AWS account. The ingress-nginx
  # controller now runs as ClusterIP. An ALB (provisioned by AWS Load Balancer
  # Controller) acts as the external-facing load balancer and forwards traffic
  # to the nginx controller via NodePort.
  # =============================================================================
  enable_ingress_nginx = true
  ingress_nginx = {
    most_recent = true
    namespace   = "ingress-nginx"

    set = [
      # Switch from LoadBalancer to ClusterIP — the ALB Ingress resource below
      # will front nginx instead. This removes the NLB annotation that was
      # causing the OperationNotPermitted error.
      {
        name  = "controller.service.type"
        value = "ClusterIP"
      },
      {
        name  = "controller.resources.requests.cpu"
        value = "100m"
      },
      {
        name  = "controller.resources.requests.memory"
        value = "128Mi"
      },
      {
        name  = "controller.resources.limits.cpu"
        value = "200m"
      },
      {
        name  = "controller.resources.limits.memory"
        value = "256Mi"
      }
    ]
  }

  # =============================================================================
  # AWS LOAD BALANCER CONTROLLER
  # Provisions an internet-facing ALB via a Kubernetes Ingress resource.
  # Uses IRSA (OIDC) for IAM authentication — the cluster's OIDC provider is
  # already configured by the retail_app_eks module.
  # =============================================================================
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    most_recent = true
    namespace   = "kube-system"
    set = [
      {
        name  = "replicaCount"
        value = "1"
      },
      # EKS Auto Mode nodes use IMDSv2 hop limit = 1, which means the LBC pod
      # cannot introspect VPC ID from EC2 metadata. Pass it explicitly instead.
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      }
    ]
  }

  # =============================================================================
  # OPTIONAL: MONITORING STACK
  # =============================================================================
  # Uncomment below to enable monitoring (increases costs)

  # enable_kube_prometheus_stack = var.enable_monitoring
  # kube_prometheus_stack = {
  #   most_recent = true
  #   namespace   = "monitoring"
  # }

  depends_on = [module.retail_app_eks]
}
