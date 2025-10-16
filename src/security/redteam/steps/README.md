# Promptfoo Red Team Template

## Overview

This template runs a **Promptfoo red team evaluation** against an app’s target LLM, captures results, and publishes them as a build artifact. The template:

1. Installs Node.js and Promptfoo.
2. Installs required Python dependencies.
3. Executes `npx promptfoo redteam eval` using the promptfoo config file in the app's repo.
4. Publishes the results (JSON + HTML) as a build artifact.

> The template changes the working directory to the **folder containing your `redteam.yaml`** before running Promptfoo so that `file://…` targets (e.g., `file://inference_ai_app.py`) resolve correctly.
> It also sets `PYTHONPATH=$(System.DefaultWorkingDirectory)` so imports succeed without packaging.

## What the template runs

- **Node setup & Promptfoo:**

  - `NodeTool@0` → Node 20
  - `npm ci` (in `npmWorkingDirectory`)
  - `npm install -g promptfoo`

- **Python setup:**

  - `UsePythonVersion@0` → Python 3.12 (latest "security" status version)
  - `pip install oauthlib pydantic python-dotenv requests requests-oauthlib`

- **Red team run:**

  - `npx promptfoo redteam eval --config <file> --output <results.json> --output <report.html>`

- **Publishing:**

  - Publishes the entire `results/` folder as artifact **promptfoo-redteam-results**

---

## Usage

```yaml
resources:
  repositories:
    - repository: templates
      type: github
      endpoint: <your-gh-service-connection>
      name: audaciaconsulting/Audacia.Build

variables:
  - group: 'ai-app-redteam-eval' # your variable group with secrets

pool:
  vmImage: 'ubuntu-latest'

stages:
  - stage: run_red_team_stage
    displayName: 'Run Promptfoo Red Team'
    jobs:
      - job: run_red_team_job
        isplayName: 'Execute red team evaluation'
        steps:
          - template: /src/security/redteam/steps/redteam.steps.yaml@templates
            parameters:
              configPath: 'llm_eval/ai_red_teaming/redteam.yaml'
              npmWorkingDirectory: 'llm_eval'
              apiUrl: $(ApiUrl)
              authTokenUrl: $(AuthTokenUrl)
              authClientId: $(AuthClientId)
              authClientSecret: $(AuthClientSecret)
              authClientScope: $(AuthClientScope)
              chosenModel: $(ChosenModel)
```

**Artifacts produced**:

- `results.json` — machine-readable results from Promptfoo
- `report.html` — human-readable report

## Prerequisites & Assumptions

- The calling repo contains:

  - A valid `redteam.yaml` (pointed to by `configPath`).
  - The Python target referenced by `redteam.yaml` (e.g., `file://inference_ai_app.py`) and any local modules it imports.

- Your app can authenticate via the provided environment variables.
- Your app has a `package-lock.json` in your `npmWorkingDirectory`.

## Security

- Provide secrets (e.g., `AUTH_CLIENT_SECRET`) via Azure DevOps **Variable Groups** as secret variables.
