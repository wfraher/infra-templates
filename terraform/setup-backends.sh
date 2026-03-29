#!/usr/bin/env bash
#
# setup-backends.sh — Create Railway + Supabase resources via their APIs.
# Run this after `terraform apply` to complete the infrastructure setup.
#
# Usage:
#   export RAILWAY_API_TOKEN="..."
#   export SUPABASE_ACCESS_TOKEN="sbp_..."
#   ./setup-backends.sh
#
# The script will prompt for anything not set via environment variables.
# At the end it prints variable values to paste into terraform.tfvars.

set -euo pipefail

# ──────────────────────────────────────────────
# Config (override via environment)
# ──────────────────────────────────────────────

PROJECT_NAME="${PROJECT_NAME:-}"
GITHUB_REPO="${GITHUB_REPO:-}"              # e.g. wfraher/my-app
SUPABASE_ORG="${SUPABASE_ORG:-}"            # org slug
SUPABASE_REGION="${SUPABASE_REGION:-americas}"
SUPABASE_DB_PASS="${SUPABASE_DB_PASS:-}"

RAILWAY_API="https://backboard.railway.com/graphql/v2"
SUPABASE_API="https://api.supabase.com"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

bold()  { printf "\033[1m%s\033[0m" "$1"; }
green() { printf "\033[32m%s\033[0m" "$1"; }
red()   { printf "\033[31m%s\033[0m" "$1"; }

prompt() {
  local var_name="$1" prompt_text="$2" current="${!1:-}"
  if [ -z "$current" ]; then
    read -rp "$(bold "$prompt_text"): " val
    eval "$var_name=\"$val\""
  fi
}

railway_gql() {
  local query="$1"
  curl -s -X POST "$RAILWAY_API" \
    -H "Authorization: Bearer ${RAILWAY_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$query"
}

# ──────────────────────────────────────────────
# Preflight
# ──────────────────────────────────────────────

echo ""
echo "$(bold '=== Backend Infrastructure Setup ===')"
echo ""

prompt PROJECT_NAME   "Project name"
prompt GITHUB_REPO    "GitHub repo (owner/name)"
prompt RAILWAY_API_TOKEN   "Railway API token"
prompt SUPABASE_ACCESS_TOKEN "Supabase access token (sbp_...)"
prompt SUPABASE_DB_PASS  "Supabase DB password (min 6 chars)"

# ──────────────────────────────────────────────
# RAILWAY
# ──────────────────────────────────────────────

echo ""
echo "$(bold '--- Railway ---')"

# Create project with PR deploys enabled
echo "Creating Railway project..."
RAILWAY_RESULT=$(railway_gql "{
  \"query\": \"mutation { projectCreate(input: { name: \\\"${PROJECT_NAME}\\\", prDeploys: true }) { id name } }\"
}")
RAILWAY_PROJECT_ID=$(echo "$RAILWAY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['projectCreate']['id'])")
echo "  $(green '✓') Project created: $RAILWAY_PROJECT_ID"

# Create service linked to GitHub repo
echo "Creating Railway service..."
SERVICE_RESULT=$(railway_gql "{
  \"query\": \"mutation { serviceCreate(input: { projectId: \\\"${RAILWAY_PROJECT_ID}\\\", name: \\\"api\\\", source: { repo: \\\"${GITHUB_REPO}\\\" } }) { id name } }\"
}")
RAILWAY_SERVICE_ID=$(echo "$SERVICE_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['serviceCreate']['id'])")
echo "  $(green '✓') Service created: $RAILWAY_SERVICE_ID"

# Get the default environment ID (production)
echo "Fetching environments..."
ENV_RESULT=$(railway_gql "{
  \"query\": \"query { project(id: \\\"${RAILWAY_PROJECT_ID}\\\") { environments { edges { node { id name } } } } }\"
}")
PROD_ENV_ID=$(echo "$ENV_RESULT" | python3 -c "
import sys, json
edges = json.load(sys.stdin)['data']['project']['environments']['edges']
for e in edges:
    print(e['node']['id'])
    break
")
echo "  $(green '✓') Production environment: $PROD_ENV_ID"

# Create staging environment
echo "Creating staging environment..."
STAGING_RESULT=$(railway_gql "{
  \"query\": \"mutation { environmentCreate(input: { projectId: \\\"${RAILWAY_PROJECT_ID}\\\", name: \\\"staging\\\" }) { id name } }\"
}")
STAGING_ENV_ID=$(echo "$STAGING_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['environmentCreate']['id'])")
echo "  $(green '✓') Staging environment: $STAGING_ENV_ID"

# Create dev environment
echo "Creating dev environment..."
DEV_RESULT=$(railway_gql "{
  \"query\": \"mutation { environmentCreate(input: { projectId: \\\"${RAILWAY_PROJECT_ID}\\\", name: \\\"dev\\\" }) { id name } }\"
}")
DEV_ENV_ID=$(echo "$DEV_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['environmentCreate']['id'])")
echo "  $(green '✓') Dev environment: $DEV_ENV_ID"

# Generate service domains for each environment
echo "Generating service domains..."
for env_name in production staging dev; do
  eval env_id=\$"$(echo "${env_name^^}_ENV_ID" | sed 's/PRODUCTION/PROD/')"
  # Handle the variable name mapping
  case "$env_name" in
    production) env_id="$PROD_ENV_ID" ;;
    staging)    env_id="$STAGING_ENV_ID" ;;
    dev)        env_id="$DEV_ENV_ID" ;;
  esac

  DOMAIN_RESULT=$(railway_gql "{
    \"query\": \"mutation { serviceDomainCreate(input: { serviceId: \\\"${RAILWAY_SERVICE_ID}\\\", environmentId: \\\"${env_id}\\\" }) { domain } }\"
  }")
  DOMAIN=$(echo "$DOMAIN_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['serviceDomainCreate']['domain'])" 2>/dev/null || echo "pending")
  echo "  $(green '✓') ${env_name}: https://${DOMAIN}"

  case "$env_name" in
    production) RAILWAY_PROD_URL="https://${DOMAIN}" ;;
    staging)    RAILWAY_STAGING_URL="https://${DOMAIN}" ;;
    dev)        RAILWAY_DEV_URL="https://${DOMAIN}" ;;
  esac
done

echo ""
echo "$(green '✓ Railway setup complete')"

# ──────────────────────────────────────────────
# SUPABASE
# ──────────────────────────────────────────────

echo ""
echo "$(bold '--- Supabase ---')"

# Get org slug if not provided
if [ -z "$SUPABASE_ORG" ]; then
  echo "Fetching organizations..."
  ORGS=$(curl -s "$SUPABASE_API/v1/organizations" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")
  echo "$ORGS" | python3 -c "
import sys, json
orgs = json.load(sys.stdin)
for i, org in enumerate(orgs):
    print(f'  [{i}] {org[\"name\"]} ({org[\"slug\"]})')
"
  read -rp "$(bold 'Select org number'): " ORG_NUM
  SUPABASE_ORG=$(echo "$ORGS" | python3 -c "import sys,json; print(json.load(sys.stdin)[${ORG_NUM}]['slug'])")
fi
echo "  Using org: $SUPABASE_ORG"

# Create Supabase projects for each environment
declare -A SUPABASE_URLS SUPABASE_KEYS

for env_name in dev staging prod; do
  sb_name="${PROJECT_NAME}-${env_name}"
  echo "Creating Supabase project: ${sb_name}..."

  SB_RESULT=$(curl -s -X POST "$SUPABASE_API/v1/projects" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${sb_name}\",
      \"organization_slug\": \"${SUPABASE_ORG}\",
      \"db_pass\": \"${SUPABASE_DB_PASS}\",
      \"region_selection\": { \"type\": \"smartGroup\", \"code\": \"${SUPABASE_REGION}\" }
    }")

  SB_REF=$(echo "$SB_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo "  $(green '✓') Created: $SB_REF"

  SUPABASE_URLS[$env_name]="https://${SB_REF}.supabase.co"

  # Wait for project to be ready
  echo "  Waiting for project to provision..."
  for i in $(seq 1 30); do
    HEALTH=$(curl -s "$SUPABASE_API/v1/projects/${SB_REF}/health" \
      -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")
    ALL_HEALTHY=$(echo "$HEALTH" | python3 -c "
import sys, json
services = json.load(sys.stdin).get('services', [])
print('yes' if all(s.get('status') == 'ACTIVE_HEALTHY' for s in services) and services else 'no')
" 2>/dev/null || echo "no")

    if [ "$ALL_HEALTHY" = "yes" ]; then
      echo "  $(green '✓') Project ready"
      break
    fi
    sleep 10
  done

  # Get API keys
  KEYS=$(curl -s "$SUPABASE_API/v1/projects/${SB_REF}/api-keys?reveal=true" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")
  SB_KEY=$(echo "$KEYS" | python3 -c "
import sys, json
keys = json.load(sys.stdin)
# Handle both new format (api_keys) and legacy format (array)
if isinstance(keys, dict):
    keys = keys.get('api_keys', [])
for k in keys:
    t = k.get('type', k.get('name', ''))
    if 'secret' in t or 'service_role' in t:
        print(k['key']); sys.exit(0)
# Fallback to anon key
for k in keys:
    print(k.get('api_key', k.get('key', ''))); sys.exit(0)
" 2>/dev/null || echo "")
  SUPABASE_KEYS[$env_name]="$SB_KEY"
done

echo ""
echo "$(green '✓ Supabase setup complete')"

# ──────────────────────────────────────────────
# Set Railway env vars with Supabase details
# ──────────────────────────────────────────────

echo ""
echo "$(bold '--- Setting Railway environment variables ---')"

declare -A ENV_ID_MAP
ENV_ID_MAP[prod]="$PROD_ENV_ID"
ENV_ID_MAP[staging]="$STAGING_ENV_ID"
ENV_ID_MAP[dev]="$DEV_ENV_ID"

for env_name in dev staging prod; do
  env_id="${ENV_ID_MAP[$env_name]}"
  sb_url="${SUPABASE_URLS[$env_name]}"
  sb_key="${SUPABASE_KEYS[$env_name]}"

  for var_name in SUPABASE_URL SUPABASE_KEY; do
    case "$var_name" in
      SUPABASE_URL) val="$sb_url" ;;
      SUPABASE_KEY) val="$sb_key" ;;
    esac

    railway_gql "{
      \"query\": \"mutation { variableUpsert(input: { projectId: \\\"${RAILWAY_PROJECT_ID}\\\", environmentId: \\\"${env_id}\\\", name: \\\"${var_name}\\\", value: \\\"${val}\\\" }) }\"
    }" > /dev/null
  done
  echo "  $(green '✓') ${env_name}: SUPABASE_URL + SUPABASE_KEY set"
done

# ──────────────────────────────────────────────
# Output summary
# ──────────────────────────────────────────────

echo ""
echo "$(bold '===========================================')"
echo "$(bold '  Setup Complete — Copy to terraform.tfvars')"
echo "$(bold '===========================================')"
echo ""
cat <<TFVARS
railway_project_id     = "${RAILWAY_PROJECT_ID}"
railway_dev_service_id = "${RAILWAY_SERVICE_ID}"

env_config = {
  production = {
    api_url   = "${RAILWAY_PROD_URL}"
    api_token = "CHANGE_ME"
  }
  staging = {
    api_url   = "${RAILWAY_STAGING_URL}"
    api_token = "CHANGE_ME"
  }
  preview = {
    api_url   = "${RAILWAY_DEV_URL}"
    api_token = "CHANGE_ME"
  }
}
TFVARS
echo ""
echo "$(bold 'Supabase URLs:')"
for env_name in dev staging prod; do
  echo "  ${env_name}: ${SUPABASE_URLS[$env_name]}"
done
echo ""
echo "Next steps:"
echo "  1. Paste the above into terraform.tfvars"
echo "  2. Set the api_token values per environment"
echo "  3. Run: terraform apply"
echo "  4. Create Vercel staging environment in the dashboard"
echo ""
