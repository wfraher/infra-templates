# infra-templates

Reusable CI/CD templates for spinning up full-stack apps on Vercel + Railway + Supabase.

## Contents

- **[runbook-cicd.md](runbook-cicd.md)** — Step-by-step setup guide covering branch strategy, environment wiring, GitHub Actions workflows, and a new-project checklist.

## Stack

| Layer    | Service  |
|----------|----------|
| Frontend | Vercel (Next.js) |
| Backend  | Railway (FastAPI or similar) |
| Database | Supabase |
| CI/CD    | GitHub Actions |

## Workflow files

The runbook includes 3 GitHub Actions workflows ready to copy into any new project:

1. **CI** — lint, type-check, build, test on every push/PR
2. **PR Preview Wiring** — connects Vercel frontend preview to Railway PR backend
3. **Cascade Merge** — auto-merges main → staging → dev after promotions

## Future

- [ ] Terraform/OpenTofu modules to automate the setup checklist
- [ ] Parameterized workflow templates (cookiecutter or similar)
