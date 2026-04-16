# SimpleTimeService — Particle41 DevOps Challenge

A minimal Go microservice that returns the current UTC timestamp and the visitor's IP address as JSON. It is containerized with Docker and deployed to AWS using Terraform/OpenTofu.

---

## Table of Contents

- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Part 1 — Run the App Locally](#part-1--run-the-app-locally)
  - [Option A: Run with Go](#option-a-run-with-go)
  - [Option B: Run with Docker](#option-b-run-with-docker)
- [Part 2 — Deploy to AWS with Terraform](#part-2--deploy-to-aws-with-terraform)
  - [Prerequisites](#prerequisites)
  - [1. Configure AWS Credentials](#1-configure-aws-credentials)
  - [2. Deploy the Infrastructure](#2-deploy-the-infrastructure)
  - [3. Access the Application](#3-access-the-application)
  - [4. Viewing Logs with Fluent Bit](#4-viewing-logs-with-fluent-bit)
  - [5. Destroy the Infrastructure](#5-destroy-the-infrastructure)
- [CI/CD Pipeline](#cicd-pipeline)
- [Configuration Variables](#configuration-variables)

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── docker.yml  # GitHub Actions — builds and pushes Docker image
├── app/
│   ├── main.go         # Go web service
│   ├── go.mod          # Go module definition
│   └── Dockerfile      # Multi-stage Docker build
└── terraform/
    ├── main.tf         # Terraform provider configuration
    ├── variables.tf    # Input variable definitions
    ├── terraform.tfvars# Default variable values
    ├── vpc.tf          # VPC, subnets, IGW, NAT Gateway, route tables
    ├── security.tf     # Security groups
    ├── iam.tf          # ECS execution role and task role
    ├── alb.tf          # Application Load Balancer
    ├── ecs.tf          # ECS cluster, task definition (app + Fluent Bit), service
    └── outputs.tf      # Output values (e.g. ALB URL)
```

---

## Architecture

```
Internet
    │
    ▼
Internet Gateway
    │
    ▼
Application Load Balancer          ← public subnets (us-east-1a, us-east-1b)
    │
    ▼
ECS Fargate Task                   ← private subnets (us-east-1a, us-east-1b)
┌─────────────────────────────┐
│  simpletimeservice (app)    │  ← handles HTTP requests on port 8080
│  Fluent Bit (sidecar)       │  ← collects and ships logs to CloudWatch
└─────────────────────────────┘
    │
    ▼
NAT Gateway                        ← outbound traffic (e.g. pulling Docker image)
```

**Why ECS Fargate?**
Fargate is a serverless container runtime — there are no EC2 instances to manage or patch. A single `terraform apply` deploys the full stack including networking, load balancing, and the running application. It is the simplest and most cost-effective way to run a containerized workload on AWS without managing servers.

**Networking design:**
- The VPC has both **public and private subnets** across two availability zones.
- The **ALB lives in the public subnets** and is the only entry point from the internet.
- The **ECS tasks run in private subnets** and are not directly reachable from the internet.
- A **NAT Gateway** in the public subnet allows ECS tasks to make outbound calls (e.g. to pull the Docker image from DockerHub).

**Fluent Bit sidecar:**
Each ECS task runs two containers: the application and a Fluent Bit sidecar. The app's stdout logs are intercepted by Fluent Bit via AWS FireLens and forwarded to CloudWatch Logs. This keeps the application container completely decoupled from the logging infrastructure.

---

## Part 1 — Run the App Locally

The service listens on port `8080` and responds to any `GET /` request with:

```json
{
  "timestamp": "2026-04-16T15:39:32Z",
  "ip": "41.173.249.127"
}
```

### Option A: Run with Go

**Prerequisites:**
- Go 1.24 or later → https://go.dev/doc/install

```bash
cd app
go run main.go
```

Test it:

```bash
curl http://localhost:8080/
```

### Option B: Run with Docker

**Prerequisites:**
- Docker Desktop → https://www.docker.com/products/docker-desktop/

Pull and run the published image directly from DockerHub:

```bash
docker run -p 8080:8080 bruno74t/simpletimeservice:v1.0.0
```

Test it:

```bash
curl http://localhost:8080/
```

Or build and run the image locally from source:

```bash
cd app
docker build -t simpletimeservice .
docker run -p 8080:8080 simpletimeservice
```

> **Note:** The container runs as a non-root user (UID 65534) and is built on a `scratch` base image, resulting in an image size of ~8MB.

---

## Part 2 — Deploy to AWS with Terraform

### Prerequisites

Make sure the following tools are installed before continuing.

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.3.0 | https://developer.hashicorp.com/terraform/install |
| AWS CLI | >= 2.0 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |

### 1. Configure AWS Credentials

You need an AWS account with permissions to create VPCs, ECS clusters, IAM roles, ALBs, and CloudWatch log groups.

**Step 1** — Create an access key:
1. Log into the AWS Console
2. Go to **IAM → Users → Your User → Security credentials**
3. Click **Create access key** → select **CLI** → copy the key ID and secret

> If you are using the root user, go to your account name (top right) → **Security credentials** → **Access keys** → **Create access key**.

**Step 2** — Configure the AWS CLI:

```bash
aws configure
```

You will be prompted for:

```
AWS Access Key ID:     <paste your Access Key ID>
AWS Secret Access Key: <paste your Secret Access Key>
Default region name:   us-east-1
Default output format: json
```

**Step 3** — Verify the connection:

```bash
aws sts get-caller-identity
```

You should see your account ID and ARN printed. If you get an error, double-check your keys.

---

### 2. Deploy the Infrastructure

> **Remote state:** Terraform state is stored remotely in an S3 bucket (`simpletimeservice-terraform-state-328263827642`) with state locking via DynamoDB (`simpletimeservice-terraform-locks`). These resources must exist in your AWS account before running `terraform init`. If you are deploying to a **different AWS account**, create them first:
>
> ```bash
> # Create S3 bucket (replace ACCOUNT_ID with your AWS account ID)
> aws s3api create-bucket --bucket simpletimeservice-terraform-state-ACCOUNT_ID --region us-east-1
> aws s3api put-bucket-versioning --bucket simpletimeservice-terraform-state-ACCOUNT_ID --versioning-configuration Status=Enabled
> aws s3api put-bucket-encryption --bucket simpletimeservice-terraform-state-ACCOUNT_ID \
>   --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
>
> # Create DynamoDB table for state locking
> aws dynamodb create-table \
>   --table-name simpletimeservice-terraform-locks \
>   --attribute-definitions AttributeName=LockID,AttributeType=S \
>   --key-schema AttributeName=LockID,KeyType=HASH \
>   --billing-mode PAY_PER_REQUEST \
>   --region us-east-1
> ```
>
> Then update the `bucket` value in `terraform/main.tf` to match your bucket name.

```bash
cd terraform
terraform init
terraform apply
```

Terraform will show you a plan of all the resources it will create and ask for confirmation. Type `yes` and press Enter.

Deployment takes approximately **3–5 minutes**. Most of that time is the NAT Gateway and ALB being provisioned.

---

### 3. Access the Application

Once `terraform apply` completes, the ALB URL is printed as an output:

```
Outputs:

alb_dns_name = "http://<your-alb-name>.us-east-1.elb.amazonaws.com"
```

Open that URL in your browser or run:

```bash
curl http://<your-alb-name>.us-east-1.elb.amazonaws.com/
```

Expected response:

```json
{
  "timestamp": "2026-04-16T15:39:32Z",
  "ip": "YOUR.PUBLIC.IP.ADDRESS"
}
```

> **Note:** It may take up to 60 seconds after `apply` completes for the ECS tasks to pass their health checks and start receiving traffic.

---

### 4. Viewing Logs with Fluent Bit

Each ECS task runs a **Fluent Bit sidecar** that collects the application's stdout logs using AWS FireLens and ships them to **CloudWatch Logs**.

Two log groups are created automatically:

| Log Group | Contents |
|---|---|
| `/ecs/simpletimeservice` | Application logs (HTTP requests, errors) |
| `/ecs/simpletimeservice/fluent-bit` | Fluent Bit operational logs |

**Option A — AWS Console:**
1. Go to **CloudWatch → Log groups**
2. Open `/ecs/simpletimeservice`
3. Click on any log stream to view individual task logs

**Option B — AWS CLI (live tail):**

```bash
aws logs tail /ecs/simpletimeservice --follow
```

This streams new log entries in real time as requests come in. Press `Ctrl+C` to stop.

---

### 5. Destroy the Infrastructure

When you are done, tear down all resources to avoid ongoing AWS charges:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. This will remove all resources created by Terraform.

> **Cost warning:** Leaving this infrastructure running costs approximately **$13–15 per week**, mostly due to the NAT Gateway ($0.045/hr).

---

## CI/CD Pipeline

A GitHub Actions workflow (`.github/workflows/docker.yml`) automatically builds and pushes the Docker image to DockerHub whenever code in the `app/` directory is pushed to the `main` branch.

**Tags pushed on each run:**
- `bruno74t/simpletimeservice:latest`
- `bruno74t/simpletimeservice:<git-commit-sha>`

**Required GitHub repository secrets:**

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your DockerHub username |
| `DOCKERHUB_TOKEN` | Your DockerHub password or access token |

To add secrets: go to your GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**.

---

## Configuration Variables

All variables are defined in `terraform/variables.tf` with defaults set in `terraform/terraform.tfvars`. You can override any value by editing `terraform.tfvars` before running `terraform apply`.

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `project_name` | `simpletimeservice` | Prefix applied to all resource names |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the VPC |
| `public_subnet_cidrs` | `["10.0.1.0/24", "10.0.2.0/24"]` | Public subnet CIDRs (one per AZ) |
| `private_subnet_cidrs` | `["10.0.3.0/24", "10.0.4.0/24"]` | Private subnet CIDRs (one per AZ) |
| `container_image` | `bruno74t/simpletimeservice:v1.0.0` | Docker image to deploy |
| `container_port` | `8080` | Port the container listens on |
| `task_cpu` | `512` | Fargate task CPU units (512 = 0.5 vCPU, shared across both containers) |
| `task_memory` | `1024` | Fargate task memory in MB (shared across both containers) |
| `desired_count` | `2` | Number of running ECS task replicas |
