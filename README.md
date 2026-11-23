# Commit HW – AWS ECS Fargate + RDS + OpenTelemetry/X-Ray (Terraform)

A two-tier application on AWS, built entirely with Terraform. The frontend shows
**"Hello Commit X"**. X is a counter that is read from (and incremented in) RDS PostgreSQL
by the backend on every request. Each browser request produces **one end-to-end trace**
(client → frontend → backend → PostgreSQL), and you can view it as a service map in
**CloudWatch / AWS X-Ray**.

---

## Architecture

```
                         Internet
                            │  HTTP :80
                ┌───────────▼───────────┐
 Public subnets │   Application LB      │  10.0.0.0/24, 10.0.1.0/24   (route 0.0.0.0/0 → IGW)
 (us-east-1a/b) └───────────┬───────────┘
                            │ :8080
                ┌───────────▼───────────┐        ┌──────────────────────┐
 Private        │ frontend (Fargate ×2) │──OTLP─▶│ otel-collector (ADOT)│──▶ X-Ray (traces)
 subnets        └───────────┬───────────┘        │  ECS service ×1      │──▶ CloudWatch (EMF metrics)
 10.0.10.0/24               │ backend.commit.local└──────────▲───────────┘
 10.0.11.0/24   ┌───────────▼───────────┐                   │ OTLP
 (NO internet)  │ backend  (Fargate ×2) │───────────────────┘
                └───────────┬───────────┘     VPC endpoints: ecr.api, ecr.dkr, logs,
                            │ :5432 (TLS)     xray, secretsmanager (interface) + S3 (gateway)
                ┌───────────▼───────────┐
 Data subnets   │ RDS PostgreSQL 17     │  10.0.20.0/24, 10.0.21.0/24
 (isolated)     └───────────────────────┘  route table: local only + NACL (5432 from private only)
```

### Requirement → implementation

| Requirement | Implementation |
|---|---|
| Region us-east-1 | `aws_region` variable, validated to equal `us-east-1` |
| OIDC, no access keys in code | GitHub Actions assumes an IAM role through **GitHub OIDC** (`modules/iam-github-oidc`). It is trusted only for `repo:antonfeldman/commit-hw:ref:refs/heads/main`. No keys are stored in GitHub or in git. |
| Local Terraform credentials | `provider "aws" {}` has **no credentials**. You run `aws configure` in your terminal, so the keys stay in `~/.aws/` (outside the repo, and covered by `.gitignore`). |
| VPC + 2 public + 2 private + 2 data subnets | `modules/network`, spread over 2 AZs |
| Data subnets isolated, no 0.0.0.0 route | Their route table has **only the local route**, with no IGW or NAT. A NACL allows only 5432 in from the private subnets. |
| Routes + limited security groups | Every SG rule is a separate resource that references another SG. **No SG allows egress to everywhere.** See [Security design](#security-design). |
| ECS cluster, 2 Fargate services (front + back) | `modules/ecs-cluster`, `modules/ecs-service` (2 tasks each, one per AZ) |
| Ingress to frontend via ALB, HTTP only | `modules/alb`: internet-facing ALB, listener on :80 → frontend target group |
| RDS PostgreSQL, backend queries it | `modules/rds`. The backend runs `UPDATE hello_counter … RETURNING value`. |
| Frontend pulls the value every X seconds | The page auto-refreshes every `refresh_seconds` (default 5). Each refresh calls the backend, which queries the DB. |
| OpenTelemetry in both services | `apps/*/telemetry.py`: OTel SDK with Flask, requests and psycopg instrumentation, and X-Ray-compatible trace IDs |
| One trace: web → frontend → backend → DB | W3C trace context is passed frontend → backend, and the DB call is a client span → one X-Ray trace |
| Service map in AWS console (managed service) | ADOT collector → **AWS X-Ray** (`awsxray` exporter). No Jaeger, Tempo or Zipkin. |
| Collector service for metrics + traces | A dedicated ECS service `otel-collector` (AWS Distro for OpenTelemetry), discoverable at `otel.commit.local:4317` |
| Code in GitHub | This repository |
| Read-only credentials for the reviewer | IAM user `commit-reviewer` with `ReadOnlyAccess`, console only, **no access keys**. MFA enforcement is available through `reviewer_require_mfa`. |
| Infrastructure via Terraform | Everything under `terraform/` |
| State bucket created manually, state in S3 | `bootstrap/create-state-bucket.sh` (AWS CLI), plus the S3 backend with native locking |

---

## Repository layout

```
.
├── apps/
│   ├── frontend/            Flask app: "Hello Commit X" (calls backend)
│   └── backend/             Flask app: counter in PostgreSQL
├── bootstrap/
│   └── create-state-bucket.sh   one-time manual creation of the state bucket
├── scripts/
│   └── build-and-push.sh        build arm64 images, push to ECR (local creds)
├── terraform/
│   ├── environments/dev/    root module: wires the modules together
│   └── modules/
│       ├── network/             VPC, subnets, IGW, route tables, data NACL, flow logs
│       ├── security-groups/     all SGs + least-privilege rules
│       ├── vpc-endpoints/       PrivateLink endpoints + S3 gateway endpoint
│       ├── alb/                 public ALB (HTTP), target group, access-log bucket
│       ├── ecr/                 app repositories + ECR Public pull-through cache
│       ├── rds/                 PostgreSQL, parameter group (force SSL), managed secret
│       ├── ecs-cluster/         cluster (Container Insights) + Cloud Map namespace
│       ├── ecs-service/         reusable Fargate service (used 3×)
│       ├── iam-github-oidc/     OIDC provider + CI role (ECR push only)
│       └── iam-readonly-reviewer/  read-only IAM user (optional MFA enforcement)
├── .github/workflows/
│   ├── terraform-ci.yml     fmt, validate, tflint, Trivy (no AWS access)
│   └── build-push.yml       OIDC → build & push images
├── .tflint.hcl
└── .trivyignore             accepted findings, with justification
```

---

## Prerequisites

| Tool | Version used |
|---|---|
| Terraform | 1.17.x (>= 1.10 required for S3 native locking) |
| AWS CLI | v2 |
| Docker | with `buildx` (images are built for `linux/arm64`) |
| An AWS account | an IAM identity that is allowed to create the resources above |

---

## Deployment, step by step

### 1. Connect your terminal to AWS (keys stay local)

```bash
aws configure                 # Access key ID, secret, region us-east-1, output json
aws sts get-caller-identity   # verify
```

> The keys are written to `~/.aws/credentials`, outside the repository. The Terraform
> provider block contains no credentials. If your organization supports it, IAM Identity
> Center (`aws configure sso`) is the better option because it uses short-lived credentials.

### 2. Create the Terraform state bucket (manual, one time)

```bash
./bootstrap/create-state-bucket.sh
```

This creates `commit-hw-tfstate-<ACCOUNT_ID>` with versioning, encryption, all public
access blocked, a policy that denies non-TLS requests, and old-version expiry. It also
writes `terraform/environments/dev/backend.hcl`, which is git-ignored.

### 3. Initialize, plan and apply

```bash
cd terraform/environments/dev
export TAG=$(git rev-parse --short HEAD)

terraform init -backend-config=backend.hcl
terraform plan -var image_tag=$TAG -out=tfplan   # review the plan
terraform apply tfplan
```

The first apply takes about 10–15 minutes, mostly for RDS. The ECS services are created,
but their tasks can't start until the images exist (next step).

### 4. Build and push the images

```bash
cd ../../..
./scripts/build-and-push.sh $TAG
```

This pushes `commit-hw/frontend:$TAG` and `commit-hw/backend:$TAG`, and warms the ECR
pull-through cache with the ADOT collector image. Then restart the services so they pick
up the images:

```bash
for s in otel-collector backend frontend; do
  aws ecs update-service --cluster commit-hw-dev --service $s --force-new-deployment >/dev/null
done
aws ecs wait services-stable --cluster commit-hw-dev --services otel-collector backend frontend
```

### 5. Open the application

```bash
curl -s $(terraform -chdir=terraform/environments/dev output -raw frontend_url)
# <h1>Hello Commit 7</h1>
```

Open the `frontend_url` in a browser. The page refreshes every 5 seconds and the number
increases each time.

### 6. View the traces (CloudWatch → X-Ray)

```bash
terraform -chdir=terraform/environments/dev output -raw xray_trace_map_url
```

- **Trace Map:** shows `Client → frontend → backend → commit (PostgreSQL)`.
- **Traces:** open any trace to see the timeline with the latency of each segment:
  `GET /` (frontend) → `GET` (HTTP call) → `GET /api/value` (backend) → `UPDATE` (SQL).
- **Metrics:** CloudWatch → Metrics → namespace **`CommitHW`** (OTel metrics via EMF).
- **Logs:** `/ecs/commit-hw-dev/{frontend,backend,otel-collector}`.

### 7. Enable CI with OIDC (GitHub Actions)

```bash
terraform -chdir=terraform/environments/dev output -raw github_actions_role_arn
```

GitHub → repository **Settings → Secrets and variables → Actions → Variables** →
add `AWS_ROLE_ARN` with that value. This is a *variable*, not a secret, because it isn't
sensitive. After that, every push to `main` that changes `apps/**` builds and pushes the
images using OIDC. To deploy a new build, set `image_tag = "<sha>"` in
`terraform/environments/dev/terraform.tfvars`, commit it, then run `terraform plan -out=tfplan` and
`terraform apply tfplan`. That way git always records which image version is deployed.

### 8. Give the reviewer read-only access

The user is created by Terraform without a password, so no password ever ends up in the
Terraform state. Set a temporary one with the CLI:

```bash
aws iam create-login-profile --user-name commit-reviewer \
  --password '<temporary-strong-password>' --password-reset-required
terraform -chdir=terraform/environments/dev output -raw reviewer_console_url
```

Send the reviewer the URL, the user name `commit-reviewer` and the temporary password
through a private channel. On first sign-in they must set a new password (the
`IAMUserChangePassword` policy allows them to change only their own). After that they
have `ReadOnlyAccess` to the whole account. They can't change anything, and they can't
read secret values.

MFA is **off by default** so the interview review is quick. To require MFA before any
action, set `reviewer_require_mfa = true` and apply.

---

## Security design

**Network**
- Only the ALB is in the public subnets. ECS tasks have no public IPs and their subnets
  have no route to the internet. They reach AWS APIs only through VPC endpoints.
- The data subnets have only the local route, plus a NACL that allows only 5432 from the
  private subnets.
- The default security group of the VPC is stripped of all rules.
- VPC Flow Logs (ALL traffic) go to CloudWatch Logs.

**Security groups** (all other traffic is denied)

| SG | Inbound | Outbound |
|---|---|---|
| alb | 80 from `0.0.0.0/0` | 8080 → frontend |
| frontend | 8080 from alb | 8080 → backend, 4317 → collector, 443 → endpoints / S3 |
| backend | 8080 from frontend | 5432 → rds, 4317 → collector, 443 → endpoints / S3 |
| otel-collector | 4317 from frontend, backend | 443 → endpoints / S3 |
| rds | 5432 from backend | none |
| vpc-endpoints | 443 from frontend, backend, collector | none |

**IAM (least privilege)**
- Each service has its own **execution role**, which can pull only its own ECR repository,
  write only its own log group, and (backend only) read only the DB secret.
- **Task roles** are empty for the apps. The collector can only write to X-Ray and to its
  own metrics log group.
- The trust policies use `aws:SourceAccount` to prevent confused-deputy attacks.
- The GitHub OIDC role can only push to the two project repositories, only from `main` of
  this repository.
- The reviewer has `ReadOnlyAccess` and can change only their own password. They have no
  access keys and can't read secret values. MFA can be enforced with `reviewer_require_mfa = true`.

**Data and secrets**
- The RDS master password is generated by RDS and stored in **Secrets Manager**
  (`manage_master_user_password`). It never appears in code, tfvars or Terraform state.
  ECS injects it into the backend container at start.
- RDS storage is encrypted, TLS is enforced (`rds.force_ssl=1`), the instance is not
  publicly accessible, and logs are exported to CloudWatch.
- ECR tags are immutable, images are scanned on push, and lifecycle rules clean up old images.
- Containers run as non-root (uid 10001) with a **read-only root filesystem**. ECS Exec
  is disabled.
- Terraform state: an encrypted, versioned, private S3 bucket with TLS required and native
  locking.

**Static analysis:** `terraform validate`, `tflint` and `trivy config` (HIGH/CRITICAL)
run in CI. The three accepted findings are listed in `.trivyignore` with a reason for each
(public ALB, HTTP-only listener, and SSE-S3 for ALB logs, all required by the assignment
or by AWS).

---

## Cost and teardown

Approximate cost while running: **about $5/day**. The main items are the 5 interface
endpoints × 2 AZs (about $2.40/day), the ALB, 5 Fargate tasks and RDS `db.t4g.micro`.

```bash
cd terraform/environments/dev
terraform plan -destroy -var image_tag=$TAG -out=destroy.tfplan   # review what will be deleted
terraform apply destroy.tfplan
```

The state bucket is not managed by Terraform. Delete it manually afterwards if you no
longer need it. Because it is versioned, remove all object versions first, for example
from the S3 console using **Empty** and then **Delete**.

---

## Known trade-offs

- **HTTP only**, as the assignment requires. In production you would add an ACM
  certificate, an HTTPS listener, a redirect from :80 to :443, and AWS WAF.
- **RDS secret rotation:** the RDS-managed secret rotates every 7 days. Because ECS injects
  secrets when a task starts, run `aws ecs update-service --force-new-deployment` for the
  backend after a rotation. In production, the backend would read the secret at runtime
  or use IAM database authentication.
- **One collector task and single-AZ RDS**, to keep costs down. Set
  `otel_collector_desired_count = 2` and `multi_az = true` for high availability.
- **No NAT gateway:** the app tasks can reach only the AWS services that have a VPC
  endpoint. That is the intended design, but a new external dependency would need an
  endpoint or a NAT gateway.
