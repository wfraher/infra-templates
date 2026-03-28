# CI/CD Runbook — Next.js + FastAPI + Supabase on Vercel/Railway

Reusable setup guide for spinning up a full-stack app with isolated PR previews,
environment promotion, and automatic branch sync.

## Stack

| Layer      | Service  | Notes                                    |
|------------|----------|------------------------------------------|
| Frontend   | Vercel   | Next.js, auto-deploys from GitHub        |
| Backend    | Railway  | FastAPI (or any framework), PR deploys   |
| Database   | Supabase | Shared per environment (dev/staging/prod)|
| CI/CD      | GitHub Actions | 3 workflows (see below)            |

## Branch Strategy

```
feature/* ──PR──> dev ──PR──> staging ──PR──> main
```

- **dev / staging / main** are protected — no direct commits.
- All work happens on `feature/*` branches off `dev`.
- After a promotion merges to `main`, a cascade workflow merges back down:
  `main → staging → dev` to keep them in sync.

## 1. GitHub Setup

### Repository secrets needed

| Secret               | Where to get it                             |
|----------------------|---------------------------------------------|
| `RAILWAY_API_TOKEN`  | Railway dashboard → Account Settings → Tokens |
| `VERCEL_TOKEN`       | Vercel dashboard → Settings → Tokens         |
| `CI_DEEPSEEK_API_KEY`| (or whatever API keys your pipeline needs)   |
| `CI_BRAVE_API_KEY`   | Optional, for live integration tests         |
| `CI_XAI_API_KEY`     | Optional, for live integration tests         |

### Branch protection rules

For `dev`, `staging`, `main`:
- Require PR reviews before merging
- Require status checks to pass
- Allow `github-actions[bot]` to bypass PR requirements (needed for cascade merge)

## 2. Vercel Setup

### Project creation
1. Import the repo in Vercel, set the root directory to `web/`
2. Framework preset: Next.js

### Environment branches
In Vercel project Settings → Environments:
- **Production** → `main` branch
- **Staging** (custom environment) → `staging` branch
- **Preview** → all other branches (default)

### Environment variables per environment

| Variable              | Production            | Staging               | Preview (dev)         |
|-----------------------|-----------------------|-----------------------|-----------------------|
| `NEXT_PUBLIC_API_URL` | `https://<prod>.up.railway.app` | `https://<staging>.up.railway.app` | `https://<dev>.up.railway.app` |
| `PIGEON_API_TOKEN`    | (prod token)          | (staging token)       | (dev token)           |
| `CRON_SECRET`         | (prod secret)         | (staging secret)      | (dev secret)          |

> `NEXT_PUBLIC_*` vars are baked in at **build time**. Changing them requires a redeploy.

### Cron jobs (optional)
Add a `vercel.json` in the web directory:
```json
{
  "crons": [
    {
      "path": "/api/cron/sweep",
      "schedule": "0 9 * * *"
    }
  ]
}
```

## 3. Railway Setup

### Project creation
1. Create a new project in Railway
2. Add a service pointing to the repo, set root directory to `/` (or `api/` depending on your import path)
3. Set the start command: `uvicorn api.main:app --host 0.0.0.0 --port $PORT`

### Enable PR deploys
In Railway service Settings → Deploys:
- Enable **PR Deploys** — Railway automatically creates an isolated environment per PR

### Environment variables
Set on the Railway service for each environment (dev/staging/production):

| Variable          | Value                          |
|-------------------|--------------------------------|
| `SUPABASE_URL`    | Per-environment Supabase URL   |
| `SUPABASE_KEY`    | Per-environment Supabase key   |
| `PIGEON_API_TOKEN`| Must match Vercel's token      |
| (API keys)        | Whatever your backend needs    |

### Environments
Railway creates environments automatically. Map them to branches:
- **production** → `main`
- **staging** → `staging`
- **dev** (default) → `dev`

## 4. Supabase Setup

Create one project per environment (or share dev across PR previews):
- `myapp-dev` — used by dev and all PR previews
- `myapp-staging` — staging
- `myapp-prod` — production

Run migrations against each environment as you promote.

## 5. GitHub Actions Workflows

### Workflow 1: CI (`ci.yml`)

Runs linting, type checking, builds, and tests on every push and PR.

```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:
    branches: [dev, staging, main]

permissions:
  contents: read

env:
  NODE_VERSION: '20'
  PYTHON_VERSION: '3.12'

jobs:
  quick-checks:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '${{ env.NODE_VERSION }}' }
      - run: npm ci
        working-directory: web
      - run: npm run lint
        working-directory: web
      - run: npx tsc --noEmit
        working-directory: web
      - run: npx next build
        working-directory: web
      - uses: actions/setup-python@v5
        with: { python-version: '${{ env.PYTHON_VERSION }}' }
      - run: pip install -r requirements.txt -r api/requirements.txt ruff
      - run: ruff check .

  full-tests:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '${{ env.NODE_VERSION }}' }
      - run: npm ci
        working-directory: web
      - run: npm run lint && npx tsc --noEmit && npx next build
        working-directory: web
      - uses: actions/setup-python@v5
        with: { python-version: '${{ env.PYTHON_VERSION }}' }
      - run: pip install -r requirements.txt -r api/requirements.txt pytest ruff
      - run: ruff check .
      - run: python -m pytest tests/ api/tests/ -v
```

### Workflow 2: PR Preview Wiring (`pr-preview-wire.yml`)

Connects the Vercel frontend preview to the Railway PR backend so each PR is fully isolated.

```yaml
name: Wire PR Preview Deploys

on:
  pull_request:
    types: [opened, synchronize, reopened]
    branches: [dev]

permissions:
  contents: read
  pull-requests: write

env:
  RAILWAY_PROJECT_ID: "<your-railway-project-id>"
  RAILWAY_DEV_SERVICE_ID: "<your-railway-service-id>"
  VERCEL_PROJECT_ID: "<your-vercel-project-id>"

jobs:
  wire-preview:
    runs-on: ubuntu-latest
    steps:
      - name: Wait for Railway PR deploy
        id: railway
        env:
          RAILWAY_API_TOKEN: ${{ secrets.RAILWAY_API_TOKEN }}
          PR_NUM: ${{ github.event.pull_request.number }}
        run: |
          # Poll Railway GraphQL API for the PR environment (up to 5 min)
          for i in $(seq 1 30); do
            RESULT=$(curl -s -X POST https://backboard.railway.com/graphql/v2 \
              -H "Authorization: Bearer ${RAILWAY_API_TOKEN}" \
              -H "Content-Type: application/json" \
              -d "{\"query\": \"query { project(id: \\\"${RAILWAY_PROJECT_ID}\\\") { environments { edges { node { id name serviceInstances { edges { node { domains { serviceDomains { domain } } serviceId } } } } } } } }\"}")

            PR_DOMAIN=$(echo "$RESULT" | python3 -c "
          import sys, json, os
          data = json.load(sys.stdin)
          envs = data.get('data', {}).get('project', {}).get('environments', {}).get('edges', [])
          svc_id = os.environ.get('RAILWAY_DEV_SERVICE_ID', '')
          pr = os.environ.get('PR_NUM', '')
          for env in envs:
              node = env['node']
              if ('pr-' + pr) in node.get('name', '').lower():
                  for inst in node.get('serviceInstances', {}).get('edges', []):
                      svc = inst['node']
                      if svc.get('serviceId') == svc_id:
                          domains = svc.get('domains', {}).get('serviceDomains', [])
                          if domains:
                              print(domains[0]['domain']); sys.exit(0)
          sys.exit(1)" || true)

            if [ -n "$PR_DOMAIN" ]; then
              echo "railway_url=https://${PR_DOMAIN}" >> $GITHUB_OUTPUT
              break
            fi
            echo "Attempt ${i}/30 — waiting 10s..."
            sleep 10
          done

          if [ -z "$PR_DOMAIN" ]; then
            echo "::warning::Railway PR deploy not found after 5 minutes"
            echo "railway_url=" >> $GITHUB_OUTPUT
          fi

      - name: Set Vercel env var and redeploy
        if: steps.railway.outputs.railway_url != ''
        env:
          VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
          RAILWAY_URL: ${{ steps.railway.outputs.railway_url }}
          BRANCH: ${{ github.head_ref }}
        run: |
          # Set branch-specific NEXT_PUBLIC_API_URL on Vercel
          RESULT=$(curl -s -w "\n%{http_code}" -X POST \
            "https://api.vercel.com/v10/projects/${VERCEL_PROJECT_ID}/env" \
            -H "Authorization: Bearer ${VERCEL_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
              \"key\": \"NEXT_PUBLIC_API_URL\",
              \"value\": \"${RAILWAY_URL}\",
              \"type\": \"plain\",
              \"target\": [\"preview\"],
              \"gitBranch\": \"${BRANCH}\"
            }")

          HTTP_CODE=$(echo "$RESULT" | tail -1)
          BODY=$(echo "$RESULT" | sed '$d')

          if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
            # Already exists — update it
            ENV_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error',{}).get('envVarId',''))" 2>/dev/null || true)
            if [ -n "$ENV_ID" ]; then
              curl -s -X PATCH \
                "https://api.vercel.com/v10/projects/${VERCEL_PROJECT_ID}/env/${ENV_ID}" \
                -H "Authorization: Bearer ${VERCEL_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"value\": \"${RAILWAY_URL}\"}" > /dev/null
            fi
          fi

          # Trigger a redeploy so the new env var is baked in
          DEPLOYMENT=$(curl -s -H "Authorization: Bearer ${VERCEL_TOKEN}" \
            "https://api.vercel.com/v6/deployments?projectId=${VERCEL_PROJECT_ID}&limit=10" \
            | python3 -c "
          import sys, json, os
          branch = os.environ['BRANCH']
          for d in json.load(sys.stdin).get('deployments', []):
              if d.get('meta', {}).get('githubCommitRef') == branch:
                  print(d['uid']); sys.exit(0)
          sys.exit(1)" 2>/dev/null || true)

          if [ -n "$DEPLOYMENT" ]; then
            DEPLOY_NAME=$(curl -s -H "Authorization: Bearer ${VERCEL_TOKEN}" \
              "https://api.vercel.com/v13/deployments/${DEPLOYMENT}" \
              | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','app'))" 2>/dev/null || echo "app")
            curl -s -X POST "https://api.vercel.com/v13/deployments" \
              -H "Authorization: Bearer ${VERCEL_TOKEN}" \
              -H "Content-Type: application/json" \
              -d "{\"name\": \"${DEPLOY_NAME}\", \"deploymentId\": \"${DEPLOYMENT}\", \"target\": \"preview\"}"
          fi

      - name: Comment PR with preview URLs
        if: steps.railway.outputs.railway_url != ''
        env:
          GH_TOKEN: ${{ github.token }}
          RAILWAY_URL: ${{ steps.railway.outputs.railway_url }}
        run: |
          BRANCH_SLUG=$(echo "${{ github.head_ref }}" | sed 's|/|-|g')
          gh pr comment ${{ github.event.pull_request.number }} \
            --repo ${{ github.repository }} \
            --body "## Preview Deploys
          | Layer | URL |
          |---|---|
          | **Frontend** | https://<app>-git-${BRANCH_SLUG}-<team>.vercel.app |
          | **Backend** | ${RAILWAY_URL} |
          | **Health** | ${RAILWAY_URL}/health |

          > Frontend redeployed to point at PR-specific backend."
```

### Workflow 3: Cascade Merge (`cascade-merge.yml`)

After a promotion lands on `main`, merges back down to keep branches in sync.

```yaml
name: Cascade Merge

on:
  push:
    branches: [main]

permissions:
  contents: write
  issues: write

jobs:
  cascade:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Merge main -> staging
        id: staging
        run: |
          git checkout staging
          git merge origin/main --no-edit
          git push origin staging
          echo "status=ok" >> $GITHUB_OUTPUT

      - name: Merge staging -> dev
        if: steps.staging.outputs.status == 'ok'
        run: |
          git checkout dev
          git merge origin/staging --no-edit
          git push origin dev

      - name: Open issue on conflict
        if: failure()
        run: |
          gh issue create \
            --title "Cascade merge conflict — manual resolution needed" \
            --body "Automatic merge-back from main -> staging -> dev hit a conflict.
          Triggered by: ${{ github.sha }}
          Resolve manually and push."
        env:
          GH_TOKEN: ${{ github.token }}
```

## 6. Frontend API Proxy Pattern

The Next.js app proxies API requests server-side so the backend URL isn't exposed to the browser.

**`web/src/lib/api.ts`** — shared proxy utility:
```typescript
const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
const API_TOKEN = process.env.PIGEON_API_TOKEN || "";

function defaultHeaders(extra?: HeadersInit): HeadersInit {
  return { Authorization: `Bearer ${API_TOKEN}`, "Content-Type": "application/json", ...extra };
}

export async function proxyRequest(request: Request, path: string): Promise<Response> {
  const upstream = new URL(`${API_URL}${path}`);
  upstream.search = new URL(request.url).search;
  const body = ["GET", "HEAD"].includes(request.method) ? undefined : await request.text();
  const res = await fetch(upstream, { method: request.method, body, headers: defaultHeaders(), cache: "no-store" });
  return new Response(res.body, { status: res.status, headers: { "Content-Type": res.headers.get("content-type") || "application/json" } });
}
```

Each API route is a thin handler:
```typescript
// web/src/app/api/version/route.ts
import { proxyRequest } from "@/lib/api";
export async function GET(request: Request) { return proxyRequest(request, "/version"); }
```

## 7. Local Development

```bash
# Backend
uvicorn api.main:app --reload --port 8000

# Frontend (in web/)
npm run dev

# Tests
python -m pytest tests/ api/tests/ -v
```

## 8. Checklist for New Projects

- [ ] Create GitHub repo with `dev`, `staging`, `main` branches
- [ ] Set up branch protection rules (require PR, require checks, allow github-actions bot bypass)
- [ ] Create Railway project, enable PR deploys, set env vars per environment
- [ ] Create Vercel project, set root to `web/`, configure environment branches (staging, production)
- [ ] Set `NEXT_PUBLIC_API_URL` per Vercel environment pointing to the correct Railway backend
- [ ] Add GitHub secrets: `RAILWAY_API_TOKEN`, `VERCEL_TOKEN`
- [ ] Copy the 3 workflow files, update project/service IDs
- [ ] Create Supabase projects per environment, run migrations
- [ ] Verify: push a feature branch, open PR to dev, confirm preview URLs in PR comment
- [ ] Verify: merge to dev, promote to staging, confirm cascade merge runs
