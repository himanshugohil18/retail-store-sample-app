# Project Description — Retail Store Sample App

**GitOps-based Microservices Deployment on Amazon EKS Auto Mode**

> All information below is evidence-based and verified against the repository and Terraform state.

---

## 1. What We Actually Built

A production-style microservices platform with fully automated GitOps deployment on AWS. Five containerized services written in Java, Go, and Node.js are deployed on Amazon EKS v1.33 (Auto Mode) through a complete CI/CD pipeline. GitHub Actions builds Docker images for only the changed services, pushes them to private Amazon ECR with immutable SHA-based tags, updates the Helm `values.yaml` files, and commits the changes back to `main`. ArgoCD watches `main` and continuously reconciles the live Kubernetes cluster state against Git. All AWS infrastructure is managed by Terraform. Traffic reaches the application through an internet-facing ALB that routes to an ingress-nginx controller running as ClusterIP inside the cluster.

**GitHub Repository:** https://github.com/himanshugohil18/retail-store-sample-app

---

## 2. Actual Technology Stack

| Layer | Technology | Evidence |
|---|---|---|
| Cloud Provider | AWS (us-west-2) | `terraform.tfstate` |
| Infrastructure as Code | Terraform (aws, helm, kubectl, random, time providers) | `versions.tf`, `terraform.tfstate` |
| Container Orchestration | Amazon EKS v1.33, Auto Mode | `main.tf`, `terraform.tfstate` |
| Networking | VPC, NAT Gateway, Internet Gateway, Security Groups | `main.tf`, `security.tf` |
| Container Registry | Amazon ECR — 5 private repos, IMMUTABLE tags, scan_on_push, AES256 | `ecr.tf`, `terraform.tfstate` |
| Ingress | AWS Load Balancer Controller (IRSA) + ingress-nginx (ClusterIP) + ALB Ingress | `addons.tf`, `alb_ingress.tf` |
| TLS / Certificate Management | cert-manager (IRSA via OIDC) | `addons.tf`, `terraform.tfstate` |
| GitOps | ArgoCD (argo-cd Helm chart v5.51.6) | `argocd.tf`, `argocd/` |
| Kubernetes Packaging | Helm — 5 individual service charts + 1 umbrella chart | `src/*/chart/` |
| CI/CD | GitHub Actions — 1 workflow (`ci-cd.yml`) | `.github/workflows/ci-cd.yml` |
| CI/CD Authentication | IAM Access Keys stored as GitHub Secrets | `ci-cd.yml` |
| In-cluster AWS Auth | IRSA via EKS OIDC provider | `addons.tf`, `terraform.tfstate` |
| Containerization | Docker — multi-stage builds on amazonlinux:2023 | All 5 `Dockerfile`s |
| Application Services | Java 21/Spring Boot (ui, cart, orders), Go/Gin (catalog), Node.js 20/NestJS (checkout) | `src/*/Dockerfile` |
| Security Controls | KMS, non-root UID 1000, drop ALL capabilities, readOnlyRootFilesystem | `ecr.tf`, Helm `values.yaml` |

---

## 3. Architecture Diagram (Text)

```
Developer
  └─ git push to main (src/ui/**, src/catalog/**, src/cart/**, src/orders/**, src/checkout/**)
        │
        ▼
GitHub Actions (.github/workflows/ci-cd.yml)
  Job 1: detect-changes
    └─ dorny/paths-filter → JSON matrix of changed services only
  Job 2: build-and-push (parallel, one runner per changed service)
    ├─ Configure AWS credentials (Access Key → IAM User)
    ├─ Login to Amazon ECR
    ├─ docker build src/<service>/  (multi-stage, amazonlinux:2023)
    ├─ Image tagged:  sha-<GITHUB_SHA>
    ├─ docker push → private ECR repo: retail-store-<service>
    ├─ Update src/<service>/chart/values.yaml (python3 regex)
    │     image.repository = <account>.dkr.ecr.<region>.amazonaws.com/retail-store-<service>
    │     image.tag        = sha-<GITHUB_SHA>
    └─ git commit "ci: update <service> image to sha-<sha> [skip ci]"
       git push origin HEAD:main
        │
        ▼
ArgoCD (namespace: argocd, EKS cluster)
  - Watches main branch continuously
  - Detects values.yaml change
  - Applies Helm chart from src/<service>/chart/
  - Rolling update (maxUnavailable: 1)
  - prune: true  →  removes resources deleted from Git
  - selfHeal: true  →  reverts any manual kubectl changes
        │
        ▼
Amazon EKS — retail-store-svqs (v1.33, Auto Mode)
  Namespace: retail-store
    ui        (Java/Spring Boot, port 8080, ClusterIP :80)
    catalog   (Go/Gin,          port 8080, ClusterIP :80)
    cart      (Java/Spring Boot, port 8080, ClusterIP :80)
    orders    (Java/Spring Boot, port 8080, ClusterIP :80)
    checkout  (Node.js/NestJS,  port 8080, ClusterIP :80)

Internet Traffic Flow:
  Internet
    → ALB (internet-facing, port 80)          ← provisioned by AWS Load Balancer Controller
    → ingress-nginx-controller (ClusterIP)    ← target-type=ip, pod IP direct routing
    → retail-store/ui (ClusterIP)             ← nginx Ingress rules
```

---

## 4. AWS Infrastructure (Verified in terraform.tfstate)

| Category | Resource | Details |
|---|---|---|
| Networking | VPC | 10.0.0.0/16 |
| Networking | Public Subnets (3) | 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24 — us-west-2a/b/c |
| Networking | Private Subnets (3) | 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24 — us-west-2a/b/c |
| Networking | NAT Gateway | 1 (single, cost optimised) |
| Networking | Internet Gateway | 1 |
| Compute | EKS Cluster | `retail-store-svqs`, Kubernetes v1.33, Auto Mode |
| Compute | EKS Node Pool | `general-purpose` (managed by EKS Auto Mode) |
| Security | KMS Key | EKS cluster secret encryption |
| Security | OIDC Provider | For IRSA (ALB Controller + cert-manager) |
| Security | IAM Role: alb-controller | Scoped ELB permissions via IRSA |
| Security | IAM Role: cert-manager | ACME/Route53 permissions via IRSA |
| Security | IAM Role: eks-cluster | EKS control plane |
| Security | IAM Role: eks-auto-nodes | EKS Auto Mode node pool |
| Security | Security Group Rules | HTTP(80), HTTPS(443), healthcheck(10254), NodePort(30000-32767) |
| Registry | ECR Repositories (×5) | retail-store-ui, catalog, cart, orders, checkout |
| Registry | ECR Lifecycle Policies | Keep 10 tagged images; expire untagged after 1 day |
| Add-ons | ArgoCD | helm: argo-cd v5.51.6, namespace: argocd |
| Add-ons | ingress-nginx | Helm, namespace: ingress-nginx, type: ClusterIP |
| Add-ons | AWS Load Balancer Controller | Helm, namespace: kube-system, IRSA |
| Add-ons | cert-manager | Helm, namespace: cert-manager, IRSA |
| Ingress | ALB Ingress Resource | `alb-ingress-nginx`, internet-facing, target-type=ip |

**Not deployed:** Prometheus, Grafana, Filebeat, Elasticsearch, Kibana, CloudWatch Logs.
The `kube-prometheus-stack` is commented out in `addons.tf` (`# enable_kube_prometheus_stack`).

---

## 5. Containerization (All 5 Services)

All Dockerfiles use **multi-stage builds** with a separate build stage and a minimal Amazon Linux 2023 runtime stage. No build tooling is present in the final image.

| Service | Language | Build Stage | Runtime Base | Non-root User |
|---|---|---|---|---|
| ui | Java 21 / Spring Boot | amazonlinux:2023 + Maven + Corretto 21 | amazonlinux:2023 + Corretto 21 | appuser (UID 1000) |
| catalog | Go (Gin) | amazonlinux:2023 + golang | amazonlinux:2023 | appuser (UID 1000) |
| cart | Java 21 / Spring Boot | amazonlinux:2023 + Maven + Corretto 21 | amazonlinux:2023 + Corretto 21 | appuser (UID 1000) |
| orders | Java 21 / Spring Boot | amazonlinux:2023 + Maven + Corretto 21 | amazonlinux:2023 + Corretto 21 | appuser (UID 1000) |
| checkout | Node.js 20 / NestJS | node:20-alpine (build) | amazonlinux:2023 + nodejs20 | appuser (UID 1000) |

Security enforced in every container:
- `runAsNonRoot: true` / `runAsUser: 1000`
- `capabilities.drop: [ALL]`
- `readOnlyRootFilesystem: true`
- Images tagged with full Git commit SHA (`sha-<GITHUB_SHA>`)
- Pushed to private ECR with `IMMUTABLE` tag mutability

---

## 6. CI/CD Pipeline Detail

**File:** `.github/workflows/ci-cd.yml`

**Trigger:** `push` to `main` where files under `src/ui/**`, `src/catalog/**`, `src/cart/**`, `src/orders/**`, or `src/checkout/**` changed. Also `workflow_dispatch` for manual full rebuilds.

**Authentication:** GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) → `aws-actions/configure-aws-credentials@v4` → IAM User → ECR.
*Note: OIDC is NOT used for GitHub Actions. It is used only for IRSA within the cluster.*

**Key design decisions:**
- `concurrency: group: ci-cd-${{ github.ref }}, cancel-in-progress: false` — queues concurrent runs instead of cancelling them, preventing race conditions on `values.yaml`
- `fail-fast: false` on the matrix — one failing service does not stop others
- `[skip ci]` in the auto-commit message — prevents the pipeline from re-triggering on its own Helm commit
- `permissions: contents: write` — required for the workflow to commit back to `main`

**Verified run:** `git log` confirms: `d84d347 ci: update ui image to sha-b16c58c62806bc9de749fa1b30393babc0d9ed22 [skip ci]`

---

## 7. Helm Charts

Each service has an independent Helm chart at `src/<service>/chart/`. The umbrella chart at `src/app/chart/` bundles all services as sub-charts but is **not used** in the active GitOps workflow — ArgoCD uses the individual per-service charts.

**Resources defined in each chart:**

| Resource | Details |
|---|---|
| Deployment | RollingUpdate, maxUnavailable: 1, readiness probe |
| Service | ClusterIP, port 80 |
| ServiceAccount | Per-service, dedicated |
| ConfigMap | Service-specific environment configuration |
| HPA | Template present, `autoscaling.enabled: false` |
| PodDisruptionBudget | Template present, `podDisruptionBudget.enabled: false` |

**Key values (all services):**

| Setting | Value |
|---|---|
| `image.pullPolicy` | `Always` |
| `service.type` | `ClusterIP` |
| `service.port` | `80` |
| `replicaCount` | `1` |
| `securityContext.runAsNonRoot` | `true` |
| `securityContext.runAsUser` | `1000` |
| `securityContext.readOnlyRootFilesystem` | `true` |
| `securityContext.capabilities.drop` | `[ALL]` |
| `metrics.enabled` | `true` (Prometheus scrape annotations configured) |

---

## 8. GitOps with ArgoCD

**Deployed via:** `helm_release.argocd` in `argocd.tf` (verified in `terraform.tfstate`)

**5 Applications + 1 AppProject** (all applied via `kubectl_manifest` in Terraform):

| Application | Chart Path | Branch | Sync Wave | Namespace |
|---|---|---|---|---|
| retail-store-ui | src/ui/chart | main | 2 | retail-store |
| retail-store-catalog | src/catalog/chart | main | 1 | retail-store |
| retail-store-cart | src/cart/chart | main | 1 | retail-store |
| retail-store-orders | src/orders/chart | main | 1 | retail-store |
| retail-store-checkout | src/checkout/chart | main | 1 | retail-store |

**Sync policy (all 5):**
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

**AppProject restrictions:**
- Source: `https://github.com/himanshugohil18/retail-store-sample-app` only
- Destination namespace: `retail-store` only
- Whitelisted cluster resources: `Namespace`, `ClusterRole`, `ClusterRoleBinding`, `ClusterIssuer`

---

## 9. Kubernetes / EKS Architecture

**Cluster:** `retail-store-svqs`, Kubernetes v1.33, EKS Auto Mode (`general-purpose` node pool)

**Namespaces:**

| Namespace | Contents |
|---|---|
| `argocd` | ArgoCD server, repo-server, application-controller, redis |
| `ingress-nginx` | ingress-nginx-controller (ClusterIP) |
| `cert-manager` | cert-manager, cainjector, webhook |
| `kube-system` | AWS Load Balancer Controller |
| `retail-store` | 5 Deployments, 5 Services, 5 ServiceAccounts, 5 ConfigMaps |

**Ingress flow:**
```
Internet → ALB (port 80, internet-facing, target-type=ip)
         → ingress-nginx-controller (ClusterIP, pod IP)
         → retail-store/ui (ClusterIP :80)
```

The ingress-nginx controller runs as ClusterIP (not LoadBalancer). The ALB is provisioned by the AWS Load Balancer Controller via a Kubernetes Ingress resource (`alb-ingress-nginx` in `ingress-nginx` namespace).

---

## 10. Security Controls (Verified)

| Control | Evidence |
|---|---|
| Non-root execution | All Dockerfiles: `useradd appuser UID 1000`; all Helm charts: `runAsNonRoot: true`, `runAsUser: 1000` |
| Drop all Linux capabilities | All Helm charts: `capabilities.drop: [ALL]` |
| Read-only root filesystem | All Helm charts: `readOnlyRootFilesystem: true` |
| Immutable ECR image tags | `ecr.tf`: `image_tag_mutability = "IMMUTABLE"` |
| ECR vulnerability scanning | `ecr.tf`: `scan_on_push = true` |
| ECR encryption at rest | `ecr.tf`: `encryption_type = "AES256"` |
| EKS secret encryption | KMS key created and attached to EKS cluster (`terraform.tfstate`) |
| IRSA for ALB Controller | OIDC provider + scoped IAM role — no EC2 instance profile |
| IRSA for cert-manager | OIDC provider + scoped IAM role |
| Private node networking | EKS nodes in private subnets; only ALB in public subnets |
| ArgoCD RBAC | AppProject restricts source repo and destination namespace |
| Per-service ServiceAccounts | Each service has its own dedicated ServiceAccount |

---

## 11. Engineering Challenges Solved

### Challenge 1 — NLB OperationNotPermitted
**Problem:** The AWS account blocked NLB creation. The original plan used `ingress-nginx` with a `LoadBalancer` type service to get a Network Load Balancer.
**Evidence:** Comment in `addons.tf`: *"NLB creation is not supported in this AWS account."*
**Solution:** Changed ingress-nginx service type to `ClusterIP`. Added `alb_ingress.tf` — the AWS Load Balancer Controller provisions an internet-facing ALB with `target-type=ip`, routing traffic directly to ingress-nginx pod IP without a NodePort.

### Challenge 2 — EKS Auto Mode IMDSv2 Hop Limit
**Problem:** EKS Auto Mode enforces IMDSv2 with a hop limit of 1. The AWS Load Balancer Controller pod could not read the VPC ID from EC2 instance metadata.
**Evidence:** Comment in `addons.tf`: *"EKS Auto Mode nodes use IMDSv2 hop limit = 1, which means the LBC pod cannot introspect VPC ID from EC2 metadata."*
**Solution:** VPC ID passed explicitly as a Helm value: `vpcId = module.vpc.vpc_id`.

### Challenge 3 — CI/CD Infinite Loop on Helm Commit
**Problem:** The pipeline updates `values.yaml` and commits back to `main`, which would re-trigger the workflow indefinitely.
**Evidence:** `ci-cd.yml` commit message includes `[skip ci]`.
**Solution:** `[skip ci]` in the commit message causes GitHub Actions to skip execution. `concurrency: cancel-in-progress: false` queues concurrent service builds safely.

### Challenge 4 — ArgoCD SharedResourceWarning
**Problem:** Running both the umbrella chart Application and the individual per-service Applications simultaneously caused `SharedResourceWarning` — the same `ClusterIssuer` was owned by two ArgoCD apps.
**Evidence:** `BRANCHING_STRATEGY.md` documents this error explicitly.
**Solution:** Exclusive use of one strategy per branch. Active branch (`main`) uses only individual Applications.

### Challenge 5 — Terraform Plan Drift from Timestamp Tags
**Problem:** `timestamp()` in Terraform `common_tags` caused every `terraform plan` to show all tagged resources as changed, even when nothing had actually changed.
**Evidence:** Comment in `locals.tf`: *"CreatedDate removed — timestamp() re-evaluates on every plan."*
**Solution:** Removed `CreatedDate` from `common_tags`.

---

## 12. Monitoring (Prepared, Not Deployed)

A `monitoring-values.yaml` file is present in the repository root with a ready-to-use `kube-prometheus-stack` configuration:

- Prometheus: 1 replica, 2-day retention
- Grafana: 1 replica
- kube-state-metrics: enabled
- node-exporter: enabled
- alertmanager: disabled

The stack is **not currently deployed**. In `addons.tf`, the relevant block is commented out:
```hcl
# enable_kube_prometheus_stack = var.enable_monitoring
```

`terraform.tfstate` contains zero Prometheus or Grafana resources.

All 5 service Helm charts have `prometheus.io/scrape: "true"` annotations pre-configured — ready for when the monitoring stack is deployed.

**Filebeat, Elasticsearch, Kibana:** Not present anywhere in the repository. Not implemented.

---

## 13. Verified Metrics

| Metric | Value | Classification | Evidence |
|---|---|---|---|
| Application microservices | 5 | VERIFIED STATIC FACT | `src/{ui,catalog,cart,orders,checkout}/` |
| Multi-stage Dockerfiles | 5 | VERIFIED STATIC FACT | One per service directory |
| Individual Helm charts | 5 | VERIFIED STATIC FACT | `src/*/chart/` |
| ArgoCD Applications | 5 | VERIFIED STATIC FACT | `argocd/applications/` + `terraform.tfstate` |
| ArgoCD AppProjects | 1 | VERIFIED STATIC FACT | `argocd/projects/retail-store-project.yaml` |
| Private ECR repositories | 5 | VERIFIED STATIC FACT | `terraform.tfstate` |
| GitHub Actions workflows | 1 | VERIFIED STATIC FACT | `.github/workflows/ci-cd.yml` |
| CI/CD pipeline jobs | 2 | VERIFIED STATIC FACT | `ci-cd.yml` |
| EKS cluster name | retail-store-svqs | VERIFIED STATIC FACT | `terraform.tfstate` |
| Kubernetes version | 1.33 | VERIFIED STATIC FACT | `terraform.tfstate` |
| VPC CIDR | 10.0.0.0/16 | VERIFIED STATIC FACT | `main.tf` + `terraform.tfstate` |
| Availability zones | 3 (us-west-2a/b/c) | VERIFIED STATIC FACT | `terraform.tfstate` subnet resources |
| Successful CI/CD run | 1 confirmed | ACTUAL MEASURED RESULT | `d84d347` in git log |
| Deployment time | Not measured | NOT MEASURED | No pipeline run logs |
| Uptime / availability | Not measured | NOT MEASURED | No monitoring data |
| Cost savings | Not measured | NOT MEASURED | No baseline data |
| Request throughput | Not measured | NOT MEASURED | No load test data |

---

## 14. Resume Bullets (Exactly 4)

- **Architected and deployed a GitOps-driven microservices platform on Amazon EKS Auto Mode** using Terraform to provision the complete AWS infrastructure (VPC across 3 availability zones, EKS v1.33, 5 private ECR repositories, internet-facing ALB, OIDC-based IAM roles) and ArgoCD to continuously reconcile 5 independent Helm-based application deployments from a single Git repository with automated prune and self-heal enabled.

- **Implemented a path-aware GitHub Actions CI/CD pipeline** that detects code changes per service directory using `dorny/paths-filter`, runs parallel matrix Docker builds only for changed services, tags each image with the full Git commit SHA, pushes to private Amazon ECR with immutable tags and scan-on-push enabled, and automatically commits updated Helm `values.yaml` files back to `main` — triggering ArgoCD reconciliation without manual intervention.

- **Engineered a two-tier Kubernetes ingress architecture** to work within AWS account constraints: AWS Load Balancer Controller (deployed via IRSA using the EKS OIDC provider) provisions an internet-facing ALB that forwards traffic directly to pod IPs, fronting an ingress-nginx controller running as ClusterIP — resolving an `OperationNotPermitted` error that blocked direct NLB provisioning.

- **Applied container security hardening across all 5 services**: every Dockerfile uses multi-stage builds on Amazon Linux 2023, creates a dedicated non-root user (UID 1000), and every Helm chart enforces `runAsNonRoot: true`, drops all Linux capabilities, enables read-only root filesystem, and uses immutable ECR image tags — reducing the container attack surface without requiring privileged access.

---

## 15. Interview-Ready Q&A

**What did you build?**
A production-style microservices platform with automated GitOps deployment on AWS. Five containerized services (Java, Go, Node.js) on Amazon EKS, with GitHub Actions building images and ArgoCD keeping the cluster in sync with Git.

**What is the architecture?**
Developer pushes code → GitHub Actions detects the changed service → Docker build → ECR push → Helm `values.yaml` update committed to `main` → ArgoCD detects change → Kubernetes rolling update. Traffic: Internet → ALB → ingress-nginx (ClusterIP) → retail-store services.

**How does code move from GitHub to Kubernetes?**
Push to `main` triggers GitHub Actions. It builds only the changed service, tags the image `sha-<commit>`, pushes to private ECR, updates `values.yaml` with Python regex, commits `[skip ci]` back to `main`. ArgoCD picks up the change and applies the updated Helm chart to the cluster.

**How are Docker images built?**
Multi-stage builds. A builder stage (Maven for Java, Go compiler, Node.js yarn) compiles the app. A minimal Amazon Linux 2023 runtime stage copies only the compiled artifact. No build tools in the final image.

**Where are images stored?**
Five private Amazon ECR repositories (`retail-store-{ui,catalog,cart,orders,checkout}`). Tags are immutable SHA-based strings. Lifecycle policies retain 10 tagged images and expire untagged layers after 1 day.

**How does Helm fit in?**
Each service has its own Helm chart at `src/<service>/chart/`. The CI/CD pipeline updates `image.repository` and `image.tag` in `values.yaml` after each build. ArgoCD deploys from the updated chart. No manual `helm upgrade` is ever run.

**How does ArgoCD fit in?**
ArgoCD is deployed via Terraform. Five Application resources point to individual Helm chart paths on `main`. `selfHeal: true` reverts manual cluster changes. `prune: true` removes resources deleted from Git. Sync waves ensure backends deploy before the UI.

**Why GitOps?**
Git is the single source of truth. Every deployment is a git commit — auditable, reproducible, rollback-able. No direct `kubectl apply` in production. ArgoCD prevents config drift automatically.

**How are metrics collected?**
Not currently collected. Prometheus scrape annotations are configured on all service pods, and `monitoring-values.yaml` contains a ready configuration, but the `kube-prometheus-stack` is commented out in `addons.tf` and not deployed.

**How are logs collected?**
Not currently collected. No Filebeat, Elasticsearch, or Kibana configuration exists anywhere in the repository.

**What does Terraform manage?**
VPC (subnets, NAT, IGW, routing), EKS cluster (Auto Mode, KMS encryption, OIDC provider), IAM roles (cluster, nodes, ALB controller, cert-manager), ECR repositories with lifecycle policies, security group rules, and all Kubernetes add-ons via Helm (ArgoCD, ingress-nginx, AWS LBC, cert-manager), plus ArgoCD Application and AppProject manifests via `kubectl_manifest`.

**What were the hardest problems?**
(1) NLB blocked by the AWS account — switched to ALB + ClusterIP ingress-nginx architecture. (2) EKS Auto Mode IMDSv2 hop limit preventing VPC metadata reads — passed `vpcId` explicitly. (3) CI/CD commit loop — solved with `[skip ci]` and concurrency controls.

**What can you prove with metrics?**
5 services, 5 ECR repos, 5 Helm charts, 5 ArgoCD Applications, 1 confirmed successful CI/CD run (`d84d347` in git history), Kubernetes v1.33, VPC across 3 AZs. No performance or timing metrics were measured.

---

*Document generated from repository forensic analysis — October 2026*
*All claims verified against: source files, Helm values, Terraform .tf files, and terraform.tfstate*
