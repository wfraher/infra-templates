# ──────────────────────────────────────────────
# Required
# ──────────────────────────────────────────────

variable "project_name" {
  description = "Name for the project (used in repo name, Vercel project, etc.)"
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repo"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token with repo and workflow scopes"
  type        = string
  sensitive   = true
}

variable "vercel_token" {
  description = "Vercel API token"
  type        = string
  sensitive   = true
}

variable "railway_api_token" {
  description = "Railway API token (stored as GitHub secret for CI workflows)"
  type        = string
  sensitive   = true
}

# ──────────────────────────────────────────────
# Optional
# ──────────────────────────────────────────────

variable "vercel_team_id" {
  description = "Vercel team ID (null for personal account)"
  type        = string
  default     = null
}

variable "vercel_root_directory" {
  description = "Root directory of the frontend app in the repo"
  type        = string
  default     = "web"
}

variable "vercel_framework" {
  description = "Framework preset for Vercel"
  type        = string
  default     = "nextjs"
}

variable "github_repo_visibility" {
  description = "Repo visibility: public or private"
  type        = string
  default     = "private"
}

variable "github_repo_description" {
  description = "Repo description"
  type        = string
  default     = ""
}

variable "protected_branches" {
  description = "Branches to protect with PR requirements"
  type        = list(string)
  default     = ["dev", "staging", "main"]
}

variable "require_pr_reviews" {
  description = "Number of required PR reviews on protected branches"
  type        = number
  default     = 1
}

# ──────────────────────────────────────────────
# Per-environment config
# ──────────────────────────────────────────────

variable "env_config" {
  description = "Per-environment configuration for Vercel env vars"
  type = map(object({
    api_url   = string # Railway backend URL for this environment
    api_token = string # API auth token
  }))
  default = {
    production = { api_url = "", api_token = "" }
    staging    = { api_url = "", api_token = "" }
    preview    = { api_url = "", api_token = "" }
  }
  sensitive = true
}

variable "extra_github_secrets" {
  description = "Additional GitHub Actions secrets (e.g., CI API keys)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ──────────────────────────────────────────────
# Railway IDs (set after manual Railway setup)
# ──────────────────────────────────────────────

variable "railway_project_id" {
  description = "Railway project ID (from Railway dashboard after creating the project)"
  type        = string
  default     = ""
}

variable "railway_dev_service_id" {
  description = "Railway service ID for the dev environment"
  type        = string
  default     = ""
}
