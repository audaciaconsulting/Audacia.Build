# Promptfoo Red Team Template

## Overview

This template runs a **Promptfoo red team evaluation** against an app’s target LLM, captures results, and publishes them as a build artifact. The template:

1. Installs Node.js and installs npm dependencies.
1. Verifies promptfoo is installed.
2. Installs required Python dependencies.
3. Executes `promptfoo` via Audacia's LLM Eval package using the promptfoo config file(s) in the app's repo.
4. Publishes the results (JSON + HTML) as a build artifact.

> The template changes the working directory to the **folder containing your `redteam.yaml`** before running Promptfoo so that `file://…` targets (e.g., `file://inference_ai_app.py`) resolve correctly.
> It also sets `PYTHONPATH=$(System.DefaultWorkingDirectory)` so imports succeed without packaging.

## What the template runs

- **Node setup & Promptfoo:**

  - `NodeTool@0` → Node 20
  - `npm ci` (in `npmWorkingDirectory`)

- **Python setup:**

  - `UsePythonVersion@0` → Python 3.12 (latest "security" status version)
  - `uv sync` → installs dependencies from `PyProject.toml` in the working directory

- **Red team run:**

  - `python -m llm_eval.red_teaming.promptfoo_evaluate <config_file> --output <results.json> --output <report.html>`

- **Publishing:**

  - Publishes the entire `results/` folder as artifact **promptfoo-redteam-results**

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
              workingDirectory: 'llm_eval' # optional, defaults to repo root
              config: 'ai_red_teaming/redteam.yaml'
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

## Parameters

| Name                  | Required | Description                                                                                                                                                                                               |
| --------------------- | -------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `workingDirectory` |      Yes | Path (in the **calling repo**) to where all commands should be executed relative to. This should include the `package.json` referencing `promptfoo` |
| `config`          |      Yes | Path (in the **calling repo**) to your red team config (e.g. `llm_eval/ai_red_teaming/redteam.yaml`). This is where the python script that runs the tests is called from, and any plugins are configured. Can provide multiple paths as an array. This needs to be relative to the working directory. |
| `apiUrl`              |      Yes | The API url for the target LLM (e.g. https://ai-app.audacia.systems/api).                                                                                                                                 |
| `authTokenUrl`        |      Yes | The url for authenticating with Entra Id in order to test the LLM (e.g. https://login.microsoftonline.com/{{TenantId}}/oauth2/v2.0/token). TenantId can be found in the App Registration in Azure.        |
| `authClientId`        |      Yes | The Entra Id Client Id for the App Registration, in order to be authenticated to test the LLM. Client Id can be found in the App Registration in Azure.                                                   |
| `authClientSecret`    |      Yes | The Entra Id Client Secret for the App Registration, in order to be authenticated to test the LLM. Client Secret can be created in the App Registration in Azure, and should be stored in Keeper.         |
| `authClientScope`     |      Yes | The Entra Id Client Scope for the App Registration, in order to be authenticated to test the LLM (e.g. api://{{ClientId}}/.default).                                                                      |
| `chosenModel`         |       Yes | Model of LLM for test, usually stored as an enum in the app.                                                                                                                           |
| `promptfooAzureApiKey` |      Yes  | The API key for Azure OpenAI, used by Promptfoo to authenticate requests.                                                                                                        |
| `promptfooAzureApiHost` |     Yes  | The API host for Azure OpenAI, used by Promptfoo to send requests (e.g. `https://your-resource-name.openai.azure.com/`).                                                        |
| `promptfooAzureDeployment` |  Yes  | The deployment name for the Azure OpenAI model, used by Promptfoo.                                                                                                  |

## Prerequisites & Assumptions

- The calling repo contains:
  - A valid `redteam.yaml` (pointed to by `config`).
  - The Python target referenced by `redteam.yaml` (e.g., `file://inference_ai_app.py`) and any local modules it imports.
  - A valid `pyproject.toml` in the `workingDirectory` with `llm_eval` as a dependency.
- Your app can authenticate via the provided environment variables.
- Your app has a `package-lock.json` in your `workingDirectory`.

## Security

- Provide secrets (e.g., `AUTH_CLIENT_SECRET`) via Azure DevOps **Variable Groups** as secret variables.
