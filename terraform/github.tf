# ──────────────────────────────────────────────
# Repository
# ──────────────────────────────────────────────

resource "github_repository" "app" {
  name        = var.project_name
  description = var.github_repo_description
  visibility  = var.github_repo_visibility

  auto_init      = true
  has_issues     = true
  has_projects   = false
  has_wiki       = false

  allow_merge_commit = true
  allow_squash_merge = true
  allow_rebase_merge = true
  delete_branch_on_merge = true
}

# ──────────────────────────────────────────────
# Branches (dev, staging off main)
# ──────────────────────────────────────────────

resource "github_branch" "dev" {
  repository    = github_repository.app.name
  branch        = "dev"
  source_branch = "main"
}

resource "github_branch" "staging" {
  repository    = github_repository.app.name
  branch        = "staging"
  source_branch = "main"
}

# ──────────────────────────────────────────────
# Branch protection
# ──────────────────────────────────────────────

resource "github_branch_protection" "protected" {
  for_each = toset(var.protected_branches)

  repository_id = github_repository.app.node_id
  pattern       = each.value

  required_pull_request_reviews {
    required_approving_review_count = var.require_pr_reviews
    dismiss_stale_reviews           = true
  }

  enforce_admins = false

  # Allow github-actions[bot] to push (needed for cascade merge)
  allows_force_pushes = false

  depends_on = [github_branch.dev, github_branch.staging]
}

# ──────────────────────────────────────────────
# Secrets
# ──────────────────────────────────────────────

resource "github_actions_secret" "railway_token" {
  repository      = github_repository.app.name
  secret_name     = "RAILWAY_API_TOKEN"
  plaintext_value = var.railway_api_token
}

resource "github_actions_secret" "vercel_token" {
  repository      = github_repository.app.name
  secret_name     = "VERCEL_TOKEN"
  plaintext_value = var.vercel_token
}

resource "github_actions_secret" "extra" {
  for_each = var.extra_github_secrets

  repository      = github_repository.app.name
  secret_name     = each.key
  plaintext_value = each.value
}

# ──────────────────────────────────────────────
# Workflow files (pushed to repo)
# ──────────────────────────────────────────────

resource "github_repository_file" "ci_workflow" {
  repository = github_repository.app.name
  branch     = "main"
  file       = ".github/workflows/ci.yml"
  content    = file("${path.module}/workflows/ci.yml")

  commit_message      = "ci: add CI workflow [terraform]"
  overwrite_on_create = true

  depends_on = [github_branch_protection.protected]

  lifecycle {
    ignore_changes = [content]
  }
}

resource "github_repository_file" "cascade_merge_workflow" {
  repository = github_repository.app.name
  branch     = "main"
  file       = ".github/workflows/cascade-merge.yml"
  content    = file("${path.module}/workflows/cascade-merge.yml")

  commit_message      = "ci: add cascade merge workflow [terraform]"
  overwrite_on_create = true

  depends_on = [github_repository_file.ci_workflow]

  lifecycle {
    ignore_changes = [content]
  }
}

resource "github_repository_file" "pr_preview_wire_workflow" {
  repository = github_repository.app.name
  branch     = "main"
  file       = ".github/workflows/pr-preview-wire.yml"
  content = templatefile("${path.module}/workflows/pr-preview-wire.yml.tftpl", {
    railway_project_id     = var.railway_project_id
    railway_dev_service_id = var.railway_dev_service_id
    vercel_project_id      = vercel_project.app.id
  })

  commit_message      = "ci: add PR preview wiring workflow [terraform]"
  overwrite_on_create = true

  depends_on = [github_repository_file.cascade_merge_workflow]

  lifecycle {
    ignore_changes = [content]
  }
}

# ──────────────────────────────────────────────
# Default branch
# ──────────────────────────────────────────────

resource "github_branch_default" "main" {
  repository = github_repository.app.name
  branch     = "main"
}
