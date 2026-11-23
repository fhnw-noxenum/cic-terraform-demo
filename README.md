# Cloud Services LE3 — Terraform Capstone Demo

A complete, runnable Terraform stack that provisions an ML-style HTTP API on AWS:

```
Internet → ALB → ECS Fargate service → (S3 bucket for model artifacts)
              ↑
            VPC (2 AZs, public + private subnets, NAT)
```

Everything is code. No clicking in the AWS console (except to demo drift).

Built so **several students can share one AWS account**: every student gets
their own state file and every resource name contains the student's name.

---

## Layout

```
.
├── bootstrap/              # one-time per account (instructor): the S3 state bucket
├── modules/
│   └── ecs-service/        # reusable: ALB + ECS task + service + IAM
├── envs/
│   ├── dev/                # the dev environment — one copy per student
│   └── prod/               # the prod environment — instructor demo only
└── app/                    # tiny FastAPI ML inference app + Dockerfile
```

---

## Prerequisites (install on your laptop)

- **Terraform ≥ 1.10** (https://developer.hashicorp.com/terraform/install)
- **AWS CLI v2**, configured with the credentials you were given (`aws configure`)
- **Docker** — only if you want to build and push your own app image. The
  default placeholder image works without it.

Install locally rather than using CloudShell: CloudShell's home folder is only
1 GB and the AWS provider download alone takes a large share of it.

```bash
# verify
terraform version
aws sts get-caller-identity
```

---

## Instructor setup (once per AWS account, before class)

1. **Bootstrap the state bucket.** Students must *not* run this.

   ```bash
   cd bootstrap
   terraform init
   terraform apply
   # note the output: state_bucket_name
   ```

   It uses local state on purpose (chicken-and-egg: the bucket that will hold
   the state doesn't exist yet). Keep `bootstrap/terraform.tfstate` somewhere
   safe — it is git-ignored.

2. **Put the bucket name into** `envs/dev/backend.tf` and `envs/prod/backend.tf`
   (replace `tfstate-ml-platform-REPLACE_WITH_ACCOUNT_ID`) and commit.

3. **Raise the account limits.** Each student stack needs 1 VPC and 1 Elastic
   IP (for the NAT gateway). Defaults are **5 VPCs and 5 Elastic IPs per
   region**, and the default VPC already uses one slot — so only 4 students
   could deploy in parallel. In *Service Quotas → Amazon VPC* (VPCs per
   Region) and *Amazon EC2* (EC2-VPC Elastic IPs), request your class size
   + 2. Do this a few days ahead; or let students work in pairs.

4. **Do one dry run yourself** with `student = "teacher"` (apply, test,
   destroy). It verifies the setup and creates the ECS / ELB service-linked
   roles once, so 20 students don't race to create them in the same minute.

---

## Student walkthrough (~45 min, matches the slide deck — Lesson 04)

### 0. Region and profile

```bash
# bash / zsh
export AWS_REGION=eu-central-1
export AWS_PROFILE=my-profile     # only if you configured a named profile
```

```powershell
# PowerShell
$env:AWS_REGION  = "eu-central-1"
$env:AWS_PROFILE = "my-profile"
```

### 1. Pick your name

Edit `envs/dev/terraform.tfvars` and set `student` to something short and
unique in the class (2–12 lowercase letters/digits), e.g. `student = "anna"`.

Terraform loads `terraform.tfvars` automatically — no `-var-file` needed.

### 2. Bring up dev

```bash
cd envs/dev

# Your OWN state file. Use the same name as in terraform.tfvars.
terraform init -backend-config="key=students/anna/dev.tfstate"

terraform plan        # ~30 resources to create — read it together
terraform apply       # ~5 minutes. Look around the AWS console while it runs.
terraform output      # prints your API URL
```

Open `api_url` in your browser. You should see the nginx welcome page (the
placeholder image). It can take a minute or two after `apply` until the load
balancer marks the task healthy — a `503` right after apply is normal.

> Everybody shares one account, so the console shows *everyone's* resources.
> Yours all contain your name (e.g. `dev-anna-api`, `anna-dev-vpc`) and carry
> the tag `Owner = anna`.

### 3. Change management

In `envs/dev/main.tf`, change `desired_count = 1` to `desired_count = 3`, then:

```bash
terraform plan    # ~ update in-place — not destroy + recreate
terraform apply
```

Watch the ECS service in the console start two more tasks. Set it back to 1
afterwards (it costs money).

### 4. Drift detection

Drift = someone changed the real infrastructure behind Terraform's back.

1. In the console go to **EC2 → Security Groups → `dev-anna-api-alb`** →
   *Edit inbound rules* → add a rule, e.g. TCP 22 from `0.0.0.0/0` → save.
2. Then:

   ```bash
   terraform plan   # Terraform notices the extra rule and proposes to remove it
   terraform apply  # puts the real world back to what the code says
   ```

(Deleting an ECS *task* does **not** show drift: ECS itself restarts it,
because the *service* — which Terraform manages — still says "run 1 task".)

### 5. (Optional) Deploy your own image

Needs Docker. From the repo root:

```bash
cd app
./build-and-push.sh v1      # bash; on Windows use Git Bash or WSL
```

Then set `image_uri` in `envs/dev/terraform.tfvars` to the printed value and
`terraform apply` in `envs/dev`. Now try `<api_url>/health` and `<api_url>/docs`.

Tags are immutable — use `v2`, `v3`, … for later pushes.

### 6. Tear down — always, at the end of the lesson

```bash
cd envs/dev
terraform destroy   # ~3 minutes, removes everything in your stack
```

Your stack costs about **$2 per day** while it runs, mostly NAT gateway and
load balancer. Don't leave it running over the weekend.

---

## Prod (instructor demo only)

`envs/prod` shows the *same module* with production inputs: 3 AZs with one NAT
each, bigger tasks, autoscaling, flow logs, alarms, Secrets Manager. It pulls
its image from the instructor's dev ECR repo (`student` in
`envs/prod/terraform.tfvars`), and its secret needs a value before tasks can
start.

```bash
cd envs/prod
terraform init
terraform plan -var "image_tag=v1"
```

Usually `plan` is enough for the lesson. Students: stay out of `envs/prod`.

---

## What you should notice during the demo

1. **The plan is the truth.** Read it line by line before applying. Terraform
   shows exactly what will change — including the diff for in-place updates.
2. **State is sacred.** Notice the `backend "s3"` block. Every student has
   their own state *key*; `use_lockfile = true` puts a lock file next to it so
   two `apply` runs on the same state can't corrupt it.
3. **Modules are functions.** `envs/dev/main.tf` is short because the
   complexity lives in `modules/ecs-service/`. Same module, different inputs
   in dev vs prod.
4. **No secrets in code.** In prod, ECS fetches the third-party API key from
   Secrets Manager at container start — no credentials in `.tf` files, none
   in the container image.
5. **Least privilege.** The task role can *read* the model bucket and nothing
   else. Whatever you grant the task role is what your code can do.
6. **Tags are mandatory.** Every resource has `Environment`, `Project` and
   `Owner` tags — applied at the provider level so you can't forget. That's
   how the instructor can see who left what running.

---

## Common gotchas

- **`student` validation error on plan** — you didn't set `student` in
  `envs/dev/terraform.tfvars`.
- **"already exists" errors** — someone else in the class uses the same
  `student` name. Pick another one, then `terraform init -reconfigure
  -backend-config="key=students/<new-name>/dev.tfstate"`.
- **"Error acquiring the state lock"** — a previous run was killed mid-flight
  (or you run two terminals). `terraform force-unlock <id>` once you're sure
  nothing else is running.
- **"NoSuchBucket" on init** — the bucket name in `backend.tf` is still the
  placeholder, or you're in the wrong region.
- **"AddressLimitExceeded" / "VpcLimitExceeded"** — the account is out of
  Elastic IPs / VPCs. Ask the instructor (see quotas above).
- **ECS task keeps restarting** — check CloudWatch Logs at
  `/ecs/dev-<student>-api`. Usually the image tag doesn't exist, or the image
  was built for ARM (use `build-and-push.sh`, which builds for `linux/amd64`).
- **`curl` on Windows PowerShell** is an alias for `Invoke-WebRequest`; use
  `curl.exe` or just the browser.

---

## What this would cost if left running 24/7

| Resource              | Dev (per student)   | Prod (3 AZs)       |
|-----------------------|---------------------|--------------------|
| NAT gateway(s)        | ~$32/mo (1×)        | ~$96/mo (3×)       |
| ALB                   | ~$17/mo             | ~$17/mo            |
| Fargate task(s)       | ~$9/mo (1× 0.25vCPU)| ~$72/mo (2× 1vCPU) |
| CloudWatch Logs       | ~$1/mo              | ~$3/mo             |
| S3 (model artifacts)  | < $1/mo             | < $1/mo            |
| **Total**             | **~$60/mo**         | **~$190/mo**       |

Always `terraform destroy` at the end of the lesson.

---

## License

MIT — use freely in your own teaching materials.
