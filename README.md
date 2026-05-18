# Cloud Services LE3 — Terraform Capstone Demo

A complete, runnable Terraform stack that provisions an ML-style HTTPS API on AWS:

```
Internet → ALB → ECS Fargate service → (S3 bucket for model artifacts)
              ↑
            VPC (2 AZs, public + private subnets, NAT)
```

Everything is code. No clicking in the AWS console.

---

## Layout

```
.
├── bootstrap/              # one-time: creates the S3 state bucket + DynamoDB lock table
├── modules/
│   └── ecs-service/        # reusable: ALB + ECS task + service + IAM
├── envs/
│   ├── dev/                # the dev environment (small, cheap)
│   └── prod/               # the prod environment (multi-AZ, autoscaling)
└── app/                    # tiny FastAPI ML inference app + Dockerfile
```

---

## Prerequisites

- AWS account with admin credentials (for the demo). For production, use a
  dedicated CI role with least privilege.
- Terraform CLI (https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- AWS CLI v2
- Docker (only if you want to build and push the app image)

```bash
# verify
terraform version
aws sts get-caller-identity
```

---

## Demo order (matches the slide deck — Lesson 04, ~45 min)

### 0. Set your AWS region and profile

```bash
export AWS_REGION=eu-central-1   # Frankfurt; pick something near you
export AWS_PROFILE=my-profile
```

### 1. Bootstrap the state backend (one-time, chicken-and-egg)

The state for everything else lives in S3 + DynamoDB. But you can't store
Terraform state in resources Terraform itself manages — unless you bootstrap
them with local state first.

```bash
cd bootstrap
terraform init
terraform apply
# note the outputs: state_bucket_name and lock_table_name
cd ..
```

You only ever run this once per AWS account.

### 2. Bring up dev

```bash
cd envs/dev
terraform init        # downloads providers + modules, configures S3 backend
terraform plan        # shows ~25 resources to create — read it together
terraform apply       # ~5-6 minutes. Switch to the AWS console while it runs.
terraform output      # prints the ALB URL
```

Test it:

```bash
curl $(terraform output -raw api_url)/health
# {"status":"ok"}
```

### 3. Show change management

```bash
# bump replicas from 1 to 3
sed -i 's/desired_count = 1/desired_count = 3/' main.tf
terraform plan   # shows ~ in-place update, not destroy+recreate
terraform apply
```

### 4. Show drift detection

```bash
# manually delete a task in the AWS console
terraform plan   # Terraform notices and proposes to recreate it
```

### 5. Bring up prod (optional, costs more)

```bash
cd ../prod
terraform init
terraform plan   # bigger: 2 AZs of NAT, multi-AZ DB, larger tasks
# terraform apply  # comment in only if you really mean it
```

### 6. Tear everything down

```bash
cd ../dev
terraform destroy   # ~3 minutes, removes everything tagged with this stack
cd ../prod
terraform destroy   # if you brought it up
# (leave bootstrap intact — destroying the state bucket would lock you out)
```

---

## What you should notice during the demo

1. **The plan is the truth.** Read it line by line before applying. Terraform
   shows exactly what will change — including the diff for in-place updates.
2. **State is sacred.** Notice the `backend "s3"` block. Two engineers running
   `apply` at the same time would corrupt state without the DynamoDB lock.
3. **Modules are functions.** `envs/dev/main.tf` is ~30 lines because the
   complexity lives in `modules/ecs-service/`. Same module, different inputs
   in dev vs prod.
4. **No secrets in code.** The ECS task fetches its DB password from Secrets
   Manager at startup via its IAM task role — no credentials in `.tf` files,
   no credentials in the container image.
5. **Tags are mandatory.** Every resource has `Environment`, `Project`, and
   `Owner` tags — applied at the provider level so you can't forget. This is
   how cost allocation actually works at scale.

---

## Common gotchas

- **"Error acquiring state lock"** — someone else is running apply, OR a
  previous run was killed mid-flight. `terraform force-unlock <id>` (read the
  error message for the lock ID) once you've confirmed nobody else is running.
- **"NoSuchBucket" on init** — you skipped step 1, or you're pointing at the
  wrong region.
- **ECS task keeps restarting** — check CloudWatch Logs at
  `/ecs/<env>-inference-api`. Usually the image tag doesn't exist or the health check is failing.
- **NAT gateway costs** — dev uses 1 NAT to save money (~$32/mo). Prod uses 2
  (one per AZ) for HA. Don't leave dev running over the weekend.

---

## What this would cost if left running 24/7

| Resource              | Dev                 | Prod (multi-AZ)    |
|-----------------------|---------------------|--------------------|
| NAT gateway(s)        | ~$32/mo (1×)        | ~$64/mo (2×)       |
| ALB                   | ~$17/mo             | ~$17/mo            |
| Fargate task(s)       | ~$9/mo (1× 0.25vCPU)| ~$72/mo (2× 1vCPU) |
| CloudWatch Logs       | ~$1/mo              | ~$3/mo             |
| S3 (model artifacts)  | < $1/mo             | < $1/mo            |
| **Total**             | **~$60/mo**         | **~$160/mo**       |

Always `terraform destroy` at the end of the lesson.

---

## License

MIT — use freely in your own teaching materials.
