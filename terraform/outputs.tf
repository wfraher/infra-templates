output "github_repo_url" {
  description = "GitHub repository URL"
  value       = github_repository.app.html_url
}

output "github_clone_url" {
  description = "Git clone URL (SSH)"
  value       = github_repository.app.ssh_clone_url
}

output "vercel_project_id" {
  description = "Vercel project ID (needed for pr-preview-wire workflow)"
  value       = vercel_project.app.id
}

output "vercel_project_name" {
  description = "Vercel project name"
  value       = vercel_project.app.name
}

output "next_steps" {
  description = "Manual steps to complete after terraform apply"
  value       = <<-EOT

    ✓ GitHub repo created: ${github_repository.app.html_url}
    ✓ Branches created: dev, staging, main
    ✓ Branch protection enabled
    ✓ GitHub secrets set
    ✓ Vercel project created and linked
    ✓ Vercel env vars set (production + preview)
    ✓ Workflow files pushed

    MANUAL STEPS REMAINING:

    1. Railway:
       - Create project at https://railway.app/new
       - Link to ${github_repository.app.html_url}
       - Enable PR deploys in service settings
       - Set env vars (SUPABASE_URL, SUPABASE_KEY, PIGEON_API_TOKEN)
       - Note the project ID and service ID

    2. Re-run with Railway IDs:
       - Set railway_project_id and railway_dev_service_id variables
       - Run: terraform apply
       - This updates the pr-preview-wire workflow with the correct IDs

    3. Vercel staging environment:
       - Go to Vercel → Settings → Environments
       - Add "Staging" environment mapped to "staging" branch
       - Set NEXT_PUBLIC_API_URL to the Railway staging URL
       - Set PIGEON_API_TOKEN for staging

    4. Supabase:
       - Create projects for each environment at https://supabase.com
       - Run migrations against each project
       - Set SUPABASE_URL and SUPABASE_KEY on Railway per environment

  EOT
}
