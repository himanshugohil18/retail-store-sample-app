# =============================================================================
# ECR REPOSITORIES — one per microservice
#
# These repositories store the private Docker images built by GitHub Actions.
# ArgoCD deploys from these images after the CI/CD pipeline updates the
# corresponding Helm chart values.yaml with the new image tag.
#
# Naming convention: retail-store-<service>
# =============================================================================

locals {
  ecr_services = ["ui", "catalog", "cart", "orders", "checkout"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_services)

  name                 = "retail-store-${each.key}"
  image_tag_mutability = "IMMUTABLE" # git-SHA tags must never be overwritten

  image_scanning_configuration {
    scan_on_push = true # free basic scanning; catches known CVEs on every push
  }

  encryption_configuration {
    encryption_type = "AES256" # SSE-S3 managed key (no extra cost)
  }

  tags = merge(local.common_tags, {
    Service = each.key
  })
}

# ---------------------------------------------------------------------------
# Lifecycle policy — keep the 10 most recent tagged images per repo.
# Untagged (dangling) layers are pruned after 1 day.
# ---------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Outputs — used by the OIDC role policy and referenced in CI/CD docs
# ---------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "ECR repository URLs for each service (use these in Helm values.yaml)"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "ecr_registry" {
  description = "ECR registry hostname (account.dkr.ecr.region.amazonaws.com)"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
