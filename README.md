# Commit HW – AWS ECS Fargate + RDS + OpenTelemetry/X-Ray (Terraform)

A two-tier application on AWS, built entirely with Terraform. The frontend shows
**"Hello Commit X"**. X is a counter that is read from (and incremented in) RDS PostgreSQL
by the backend on every request. Each browser request produces **one end-to-end trace**
(client → frontend → backend → PostgreSQL), and you can view it as a service map in
**CloudWatch / AWS X-Ray**.

**Phase 2** adds HTTPS with a self-signed certificate (`anton.com`, created by Terraform,
private key in Secrets Manager, imported into ACM), **blue/green deployments with AWS
CodeDeploy** for both services, and a GitHub Actions pipeline whose deploy step is a single
SSM parameter change: **SSM → EventBridge → Lambda → CodeDeploy**.

---

## Architecture

```
                    Internet  (https://anton.com → /etc/hosts → ALB IPs)
                            │  HTTPS :443 (self-signed cert from ACM)   HTTP :80 → 301 to HTTPS
                ┌───────────▼───────────┐
 Public subnets │   Application LB      │  10.0.0.0/24, 10.0.1.0/24   (route 0.0.0.0/0 → IGW)
 (us-east-1a/b) └───────────┬───────────┘
                            │ :8080  target groups frontend (blue) / frontend-green
                ┌───────────▼───────────┐        ┌──────────────────────┐
 Private        │ frontend (Fargate ×2) │──OTLP─▶│ otel-collector (ADOT)│──▶ X-Ray (traces)
 subnets        └───────────┬───────────┘        │  ECS service ×1      │──▶ CloudWatch (EMF metrics)
 10.0.10.0/24               │ HTTP :80           └──────────▲───────────┘
 10.0.11.0/24   ┌───────────▼───────────┐                   │
 (NO internet)  │ internal ALB          │                   │
                └───────────┬───────────┘                   │
                            │ :8080  target groups backend (blue) / backend-green
                ┌───────────▼───────────┐                   │ OTLP
                │ backend  (Fargate ×2) │───────────────────┘
                └───────────┬───────────┘     VPC endpoints: ecr.api, ecr.dkr, logs,
                            │ :5432 (TLS)     xray, secretsmanager (interface) + S3 (gateway)
                ┌───────────▼───────────┐
 Data subnets   │ RDS PostgreSQL 17     │  10.0.20.0/24, 10.0.21.0/24
 (isolated)     └───────────────────────┘  route table: local only + NACL (5432 from private only)
```

**Delivery (Phase 2)**

```
 git push (apps/**) ──▶ GitHub Actions (OIDC) ──▶ build arm64 image ──▶ ECR (immutable tag = git SHA)
                                   │
                                   └─ aws ssm put-parameter /commit-hw/dev/<app>/image-tag = <sha>
                                                      │  "Parameter Store Change" event
                                                      ▼
                       EventBridge rule ──▶ Lambda commit-hw-dev-ecs-deployer
                                              1. verify the image exists in ECR
                                              2. register a task-definition revision with the new image
                                              3. CodeDeploy CreateDeployment (inline AppSpec)
                                                      ▼
                       CodeDeploy blue/green: green task set in the idle target group
                         → canary 10% of traffic for 5 min → 100% → blue kept 5 min → terminated
                         → automatic rollback on failure or on the target-5XX alarm
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
| Ingress to frontend via ALB, HTTP only (Phase 1) | `modules/alb`: internet-facing ALB. Phase 2 moved the app to HTTPS :443 and turned :80 into a 301 redirect. |
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

### Phase 2 requirement → implementation

| Requirement | Implementation |
|---|---|
| Self-signed TLS cert, created in Terraform | `modules/tls-certificate`: `tls_private_key` (RSA-2048) + `tls_self_signed_cert` for `anton.com`, 1 year, renewed by Terraform 30 days before expiry |
| Private key in Secrets Manager | Secret `commit-hw-dev/tls/anton.com-…` (cert + key, JSON), encrypted with a **dedicated KMS key** with rotation |
| Upload to ACM | `aws_acm_certificate` (imported) → ALB HTTPS listener, policy `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` |
| Domain in /etc/hosts with the ALB IPs | `sudo ./scripts/update-hosts.sh` resolves the ALB's current IPs and writes a managed block for `anton.com` |
| GitHub Actions pipeline deploys the new frontend | `.github/workflows/deploy.yml`: build → push → publish tag to SSM → wait for the CodeDeploy result |
| ECS update strategy blue/green | Frontend **and** backend use the `CODE_DEPLOY` controller with two target groups each (`modules/codedeploy-ecs`); the backend got an internal ALB for it |
| SSM parameter change → CodeDeploy | `modules/deploy-automation`: EventBridge rule on `/commit-hw/dev/{frontend,backend}/image-tag` → Lambda → CodeDeploy |
| Repo read-only for others | Only the owner has write access; `scripts/protect-github-repo.sh` adds a `main` ruleset (PR + CI required, no force-push/deletion, owner bypass), fork-PR workflow approval, read-only `GITHUB_TOKEN`; `.github/CODEOWNERS` |

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
│   ├── build-and-push.sh        build arm64 images, push to ECR (local creds)
│   ├── update-hosts.sh          point anton.com at the ALB IPs in /etc/hosts
│   └── protect-github-repo.sh   GitHub ruleset + Actions hardening (idempotent)
├── terraform/
│   ├── environments/dev/    root module: wires the modules together
│   └── modules/
│       ├── network/             VPC, subnets, IGW, route tables, data NACL, flow logs
│       ├── security-groups/     all SGs + least-privilege rules
│       ├── vpc-endpoints/       PrivateLink endpoints + S3 gateway endpoint
│       ├── alb/                 ALB (public or internal), blue/green TGs, HTTPS, access logs
│       ├── tls-certificate/     self-signed cert → ACM + Secrets Manager (KMS)
│       ├── codedeploy-ecs/      CodeDeploy app, deployment groups, rollback alarms, role
│       ├── deploy-automation/   SSM-change → EventBridge → Lambda (src/handler.py)
│       ├── ecr/                 app repositories + ECR Public pull-through cache
│       ├── rds/                 PostgreSQL, parameter group (force SSL), managed secret
│       ├── ecs-cluster/         cluster (Container Insights) + Cloud Map namespace
│       ├── ecs-service/         reusable Fargate service (used 3×)
│       ├── iam-github-oidc/     OIDC provider + CI role (ECR push, image-tag SSM write)
│       └── iam-readonly-reviewer/  read-only IAM user (optional MFA enforcement)
├── .github/workflows/
│   ├── terraform-ci.yml     fmt, validate, tflint, Trivy (no AWS access)
│   └── deploy.yml           OIDC → build, push, publish tag to SSM, watch CodeDeploy
├── .github/CODEOWNERS
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

`image_tag` only **seeds** the SSM image-tag parameters on the first apply. After that the
parameters (written by the pipeline) are the source of truth for the deployed version,
and Terraform reads them back.

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

### 5. Open the application (https://anton.com)

The certificate is for `anton.com`, which is not in public DNS for this ALB, so map it
locally to the ALB's current IP addresses:

```bash
./scripts/update-hosts.sh                 # shows the IPs it would write
sudo ./scripts/update-hosts.sh anton.com "$(terraform -chdir=terraform/environments/dev output -raw alb_dns_name)"
curl -k https://anton.com/                # -k: the certificate is self-signed
# <h1>Hello Commit 7</h1>
curl -sI http://anton.com/ | head -2      # 301 → https://anton.com:443/
```

In a browser, open **https://anton.com** and accept the self-signed-certificate warning
(or trust it: `terraform output -raw tls_certificate_pem > anton.pem`, then add it to the
macOS Keychain as trusted). The page refreshes every 5 seconds and the number increases.
ALB IPs can change; re-run the script if the site stops answering.
`sudo ./scripts/update-hosts.sh --remove` cleans `/etc/hosts` up.

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
sensitive.

After that, every push to `main` that changes `apps/frontend` or `apps/backend` runs
`deploy.yml` for the changed app(s):

1. build the arm64 image and push `commit-hw/<app>:<git-sha>` (skipped if the tag exists),
2. `aws ssm put-parameter /commit-hw/dev/<app>/image-tag = <git-sha>`,
3. wait for the CodeDeploy deployment that the Lambda starts, and fail if it fails.

**Manual deploy / rollback:** *Actions → build-and-deploy → Run workflow*, choose the app
and optionally an existing `image_tag`. Without GitHub, the same trigger is one command:

```bash
aws ssm put-parameter --overwrite --type String \
  --name /commit-hw/dev/frontend/image-tag --value <tag>
```

Writing the **same** tag again is a "refresh": it redeploys the latest task definition
(for example after Terraform changed an environment variable).

### 7a. Watch a blue/green deployment

- **CodeDeploy console** → Applications → `commit-hw-dev` → deployment: traffic shifts
  10% → 100%, then the original task set is terminated after 5 minutes.
- **ALB listener** :443 shows the weights of `commit-hw-dev-frontend` / `-frontend-green`.
- **Lambda logs:** `/aws/lambda/commit-hw-dev-ecs-deployer`.
- A target-5XX alarm (`commit-hw-dev-<app>-target-5xx`) or any failure rolls back
  automatically: traffic returns to the original task set, which is still running.

### 7b. Protect the GitHub repository

```bash
./scripts/protect-github-repo.sh
```

Only the owner has write access (no collaborators), so others can read, fork and open
PRs but cannot push. The script adds a ruleset on `main` (no deletion, no force-push,
changes via PR with passing `validate` and `security-scan` checks; the repository admin
may bypass), requires approval before workflows run for any outside contributor's PR,
and makes the default `GITHUB_TOKEN` read-only. `.github/CODEOWNERS` assigns every path
to the owner.

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
| alb | 443, 80 (redirect) from `0.0.0.0/0` | 8080 → frontend |
| frontend | 8080 from alb | 80 → backend-alb, 4317 → collector, 443 → endpoints / S3 |
| backend-alb (internal) | 80 from frontend | 8080 → backend |
| backend | 8080 from backend-alb | 5432 → rds, 4317 → collector, 443 → endpoints / S3 |
| otel-collector | 4317 from frontend, backend | 443 → endpoints / S3 |
| rds | 5432 from backend | none |
| vpc-endpoints | 443 from frontend, backend, collector | none |

**IAM (least privilege)**
- Each service has its own **execution role**, which can pull only its own ECR repository,
  write only its own log group, and (backend only) read only the DB secret.
- **Task roles** are empty for the apps. The collector can only write to X-Ray and to its
  own metrics log group.
- The trust policies use `aws:SourceAccount` to prevent confused-deputy attacks.
- The GitHub OIDC role can only push to the two project repositories, write the two
  image-tag parameters and read CodeDeploy deployment status - only from `main` of this
  repository. It cannot change ECS, IAM or the load balancers itself.
- The **deployer Lambda** may read only the image-tag parameters, describe images in the
  two repositories, register task definitions, pass only the two services' task/execution
  roles to ECS, and start deployments only in the two deployment groups.
- The **CodeDeploy role** is a scoped replacement for `AWSCodeDeployRoleForECS`: task
  sets of the two services only, `ModifyListener`/`ModifyRule` on the two production
  listeners only, `PassRole` only for the services' roles.
- The reviewer has `ReadOnlyAccess` and can change only their own password. They have no
  access keys and can't read secret values. MFA can be enforced with `reviewer_require_mfa = true`.

**TLS**
- Clients connect over TLS 1.2/1.3 with forward-secret ciphers only; :80 only redirects.
- The private key is stored in Secrets Manager encrypted with a customer-managed KMS key
  (rotation on). The reviewer's `ReadOnlyAccess` cannot read secret values.
- Frontend → backend stays plain HTTP **inside the VPC** (private subnets, SG-to-SG
  rules only). End-to-end TLS would need a private CA (ACM PCA) - see trade-offs.

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
(public ALB, the internal ALB's in-VPC HTTP listener, and SSE-S3 for ALB logs).

---

## Cost and teardown

Approximate cost while running: **about $5.70/day**. The main items are the 5 interface
endpoints × 2 AZs (about $2.40/day), the two ALBs, 5 Fargate tasks and RDS `db.t4g.micro`.
CodeDeploy for ECS, EventBridge and the Lambda are free or cents; the KMS key is $1/month.

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

- **Self-signed certificate**, as Phase 2 requires: browsers warn until it is trusted
  locally. In production: a real domain in Route 53 with an ACM-issued (auto-renewed)
  certificate, plus AWS WAF.
- **The private key is also in the Terraform state** (the `tls` provider generates it).
  The state bucket is private, encrypted, versioned and TLS-only. Generating the key
  outside Terraform would keep it out of state, but the assignment asks for Terraform.
- **CodeDeploy shifts one production listener**, so HTTP :80 redirects to HTTPS instead
  of serving the app too (a forwarding :80 would stay on the old target group).
- **Internal ALB for the backend** (~$16/month): CodeDeploy blue/green needs a load
  balancer, and Cloud Map service discovery is not supported with the CODE_DEPLOY
  controller. The backend's `backend.commit.local` record was removed.
- **Task definitions have two writers**: Terraform registers a revision when you change
  its settings, the Lambda registers one per deployment (latest revision + new image).
  The running revision changes only through CodeDeploy; publish the same tag again to
  roll out a Terraform-only change.
- **RDS secret rotation:** the RDS-managed secret rotates every 7 days. Because ECS injects
  secrets when a task starts, run `aws ecs update-service --force-new-deployment` for the
  backend after a rotation. In production, the backend would read the secret at runtime
  or use IAM database authentication.
- **One collector task and single-AZ RDS**, to keep costs down. Set
  `otel_collector_desired_count = 2` and `multi_az = true` for high availability.
- **No NAT gateway (cost optimization):** the private subnets have no outgoing internet
  traffic, so a NAT gateway would be paid for (about $33/month per AZ, plus data
  processing) without being used. The app tasks reach only the AWS services that have a
  VPC endpoint. A new external dependency would need an endpoint or a NAT gateway.
