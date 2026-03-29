# infra-templates

Reusable CI/CD templates for spinning up full-stack apps on Vercel + Railway + Supabase.

## Contents

- **[runbook-cicd.md](runbook-cicd.md)** — Step-by-step manual setup guide
- **[terraform/](terraform/)** — Terraform scripts to automate most of the setup

## Stack

| Layer    | Service  | Automation |
|----------|----------|------------|
| Frontend | Vercel (Next.js) | Terraform (project, env vars) |
| Backend  | Railway (FastAPI or similar) | `setup-backends.sh` (project, service, environments, domains) |
| Database | Supabase | `setup-backends.sh` (projects, API keys, Railway env var wiring) |
| CI/CD    | GitHub Actions | Terraform (repo, branches, protection, secrets, workflow files) |

## Quick Start (Terraform)

```bash
cd terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your tokens and config

# Or use environment variables for secrets
export TF_VAR_github_token="ghp_..."
export TF_VAR_vercel_token="..."
export TF_VAR_railway_api_token="..."

terraform init
terraform plan
terraform apply
```

### What Terraform creates

- GitHub repo with `dev`, `staging`, `main` branches
- Branch protection rules (require PR reviews)
- GitHub Actions secrets (Railway + Vercel tokens)
- All 3 workflow files pushed to the repo
- Vercel project linked to the repo with env vars per environment

### Then run the backend setup script

The setup script creates Railway and Supabase resources via their APIs:

```bash
export RAILWAY_API_TOKEN="..."
export SUPABASE_ACCESS_TOKEN="sbp_..."

./setup-backends.sh
```

This creates:
- Railway project with PR deploys, service linked to GitHub, dev/staging/production environments with domains
- Supabase projects per environment, waits for provisioning, grabs API keys
- Wires Supabase credentials into Railway env vars automatically
- Prints `terraform.tfvars` values to paste and re-apply

### What you still set up manually

1. **Re-run Terraform** with the Railway IDs (output by the script) to wire up the PR preview workflow
2. **Vercel staging environment** — add via dashboard (custom environments not yet in the Terraform provider)
3. **Supabase migrations** — run against each environment

## Workflow files

Three GitHub Actions workflows are included:

1. **CI** (`ci.yml`) — lint, type-check, build, test on every push/PR
2. **PR Preview Wiring** (`pr-preview-wire.yml`) — connects Vercel frontend preview to Railway PR backend
3. **Cascade Merge** (`cascade-merge.yml`) — auto-merges main → staging → dev after promotions

## Future

- [ ] Parameterized workflow templates (cookiecutter or similar)
- [ ] Migrate to Terraform providers as Railway/Supabase providers mature
