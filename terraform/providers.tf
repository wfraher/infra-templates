terraform {
  required_version = ">= 1.5"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 2.0"
    }
  }
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

provider "vercel" {
  api_token = var.vercel_token
  team      = var.vercel_team_id
}
