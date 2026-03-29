# infra-templates

Reusable CI/CD templates for spinning up full-stack apps on Vercel + Railway + Supabase.

## Contents

- **[runbook-cicd.md](runbook-cicd.md)** — Step-by-step manual setup guide
- **[terraform/](terraform/)** — Terraform scripts to automate most of the setup

## Stack

| Layer    | Service  | Terraform support |
|----------|----------|-------------------|
| Frontend | Vercel (Next.js) | Full (project, env vars) |
| Backend  | Railway (FastAPI or similar) | Manual (no provider) |
| Database | Supabase | Manual |
| CI/CD    | GitHub Actions | Full (repo, branches, protection, secrets, workflow files) |

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

### What you still set up manually

1. **Railway** — create project, enable PR deploys, set env vars, note the project/service IDs
2. **Re-run Terraform** with the Railway IDs to wire up the PR preview workflow
3. **Vercel staging environment** — add via dashboard (custom environments not yet in the provider)
4. **Supabase** — create projects per environment, run migrations

## Workflow files

Three GitHub Actions workflows are included:

1. **CI** (`ci.yml`) — lint, type-check, build, test on every push/PR
2. **PR Preview Wiring** (`pr-preview-wire.yml`) — connects Vercel frontend preview to Railway PR backend
3. **Cascade Merge** (`cascade-merge.yml`) — auto-merges main → staging → dev after promotions

## Future

- [ ] Parameterized workflow templates (cookiecutter or similar)
- [ ] Railway automation via API script when a provider becomes available
- [ ] Supabase project creation via provider
