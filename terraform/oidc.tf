# =============================================================================
# GITHUB ACTIONS OIDC — Keyless AWS authentication for CI/CD
#
# How it works:
#   1. GitHub Actions generates a short-lived OIDC token for every workflow run.
#   2. The workflow calls aws-actions/configure-aws-credentials with role-to-assume.
#   3. AWS STS validates the token against the GitHub OIDC provider registered here.
#   4. AWS issues temporary credentials scoped to this IAM role (max 1 hour).
#   5. No static AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY ever exist.
#
# The trust policy is locked down to:
#   - A specific GitHub repository (var.github_repo)
#   - Only the main branch (sub condition on token subject)
#
# References:
#   https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
# =============================================================================

# ---------------------------------------------------------------------------
# Variables — set these before running terraform apply
# ---------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organisation or user name that owns the repository"
  type        = string
  default     = "himanshugohil18"
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
  default     = "retail-store-sample-app"
}

variable "github_branch" {
  description = "Branch that is allowed to assume the CI/CD role (typically main)"
  type        = string
  default     = "main"
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC provider
#
# AWS requires the thumbprint of the OIDC issuer certificate. GitHub's
# thumbprint is stable and published in their documentation. The value below
# is the current SHA-1 thumbprint for token.actions.githubusercontent.com.
# If it ever rotates, re-run: openssl s_client -connect token.actions.githubusercontent.com:443
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com", # audience used by aws-actions/configure-aws-credentials
  ]

  # SHA-1 thumbprint of the GitHub OIDC TLS certificate leaf.
  # This is the value published by GitHub and verified by AWS.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd", # secondary (rotated 2023)
  ]

  tags = merge(local.common_tags, {
    Name = "github-actions-oidc-provider"
  })
}

# ---------------------------------------------------------------------------
# IAM Role — assumed by GitHub Actions workflows in the target repo/branch
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Lock down to the specific repo AND the main branch only.
    # Format: repo:<org>/<repo>:ref:refs/heads/<branch>
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # StringLike with wildcard allows both branch pushes and PR merges.
      # Change to StringEquals with exact branch ref for stricter control.
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_cicd" {
  name                 = "github-actions-retail-store-cicd"
  description          = "Assumed by GitHub Actions to build and push Docker images to ECR"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600 # 1 hour — enough for a full build matrix

  tags = merge(local.common_tags, {
    Name = "github-actions-retail-store-cicd"
  })
}

# ---------------------------------------------------------------------------
# IAM Policy — least-privilege ECR push permissions
#
# Permissions breakdown:
#   ecr:GetAuthorizationToken          — obtain the docker login token (account-level)
#   ecr:BatchCheckLayerAvailability    — check if a layer already exists (avoids re-upload)
#   ecr:GetDownloadUrlForLayer         — pull existing base/cache layers
#   ecr:BatchGetImage                  — pull existing images (for layer caching)
#   ecr:PutImage                       — write the final image manifest
#   ecr:InitiateLayerUpload            — start a layer upload session
#   ecr:UploadLayerPart                — upload layer chunks
#   ecr:CompleteLayerUpload            — finalise a layer upload
#   ecr:DescribeRepositories           — confirm repos exist before pushing
#
# GetAuthorizationToken is account-level (no resource ARN restriction).
# All push/pull operations are restricted to only the retail-store-* repos.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken must be on "*" — it is an account-level API call
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push / pull operations scoped to only the retail-store-* repositories
  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
    ]
    resources = [
      for repo in aws_ecr_repository.services : repo.arn
    ]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "github-actions-retail-store-ecr-push"
  description = "Allows GitHub Actions to push Docker images to retail-store ECR repositories"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions_cicd.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# ---------------------------------------------------------------------------
# Outputs — the role ARN is what you put in the GitHub Actions workflow
# ---------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "IAM Role ARN to set as the AWS_ROLE_TO_ASSUME GitHub Actions secret"
  value       = aws_iam_role.github_actions_cicd.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider registered in this AWS account"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
