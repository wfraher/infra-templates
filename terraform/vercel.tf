# ──────────────────────────────────────────────
# Vercel project linked to GitHub repo
# ──────────────────────────────────────────────

resource "vercel_project" "app" {
  name      = var.project_name
  framework = var.vercel_framework

  git_repository {
    type = "github"
    repo = "${var.github_owner}/${github_repository.app.name}"
  }

  root_directory = var.vercel_root_directory

  # Build & dev settings
  build_command   = null # use framework default
  output_directory = null

  # Auto-deploy all branches
  automatically_expose_system_environment_variables = true
}

# ──────────────────────────────────────────────
# Environment variables — production
# ──────────────────────────────────────────────

resource "vercel_project_environment_variable" "api_url_production" {
  project_id = vercel_project.app.id
  key        = "NEXT_PUBLIC_API_URL"
  value      = var.env_config["production"].api_url
  target     = ["production"]
}

resource "vercel_project_environment_variable" "api_token_production" {
  project_id = vercel_project.app.id
  key        = "PIGEON_API_TOKEN"
  value      = var.env_config["production"].api_token
  target     = ["production"]
}

# ──────────────────────────────────────────────
# Environment variables — preview (dev + PRs)
# ──────────────────────────────────────────────

resource "vercel_project_environment_variable" "api_url_preview" {
  project_id = vercel_project.app.id
  key        = "NEXT_PUBLIC_API_URL"
  value      = var.env_config["preview"].api_url
  target     = ["preview"]
}

resource "vercel_project_environment_variable" "api_token_preview" {
  project_id = vercel_project.app.id
  key        = "PIGEON_API_TOKEN"
  value      = var.env_config["preview"].api_token
  target     = ["preview"]
}

# ──────────────────────────────────────────────
# Note: Staging environment
# ──────────────────────────────────────────────
# Vercel custom environments (like "staging" with a specific branch)
# must be created in the Vercel dashboard first. The Terraform
# provider doesn't yet support creating custom environments.
#
# After creating the staging environment in the dashboard:
# 1. Go to Settings → Environments → Add Environment
# 2. Name: "Staging", Branch: "staging"
# 3. Then set env vars for it via the dashboard or API
#
# The PR preview wiring workflow handles per-PR env var overrides
# automatically via the Vercel API.
