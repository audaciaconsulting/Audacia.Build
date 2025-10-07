# Dependency-Track SBOM Pipelines (Azure DevOps)

This folder contains reusable Azure DevOps templates for generating CycloneDX SBOMs for all deployables in a repository, uploading them to **OWASP Dependency-Track**, and (optionally) deactivating older project versions after a successful upload.

There are two ways to run the workflow:

* **E2E (single job):** one template that does Generate → Upload → Deactivate in one go.
* **Staged (more control):** split into stages so you can run/skip parts independently and gate later stages on earlier results.

> **Who is this for?**
> A software engineer who wants to add automated SBOM generation + upload to Dependency-Track with minimal infrastructure setup.

---

## What is Dependency-Track (in 30 seconds)?

[OWASP Dependency-Track](https://dependencytrack.org/) ingests SBOMs, analyzes your dependencies (vulnerabilities, licenses, policy violations), and tracks risk over time. You upload a CycloneDX SBOM per deployable (e.g., API, UI, Functions). Dependency-Track creates or updates a “Project” for each deployable and a “Version” per release you upload.
Official docs: [https://docs.dependencytrack.org/](https://docs.dependencytrack.org/) (projects, SBOM upload endpoint, API auth, etc.).

---

## Prerequisites

1. **Azure DevOps Variable Group:** `Dependency-Track`

    * `DT_API_URL` (secret): your Dependency-Track base URL, e.g. `https://dependency-track.audacia.tech/api`
    * `DT_API_KEY` (secret): API key for a Dependency-Track team with upload rights (e.g., permissions like `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD`; grant only what’s needed).
2. **Repository layout:** know your deployables’ paths:

    * Examples:

        * `.NET` deployables:

            * `src/YourProduct.Api/YourProduct.Api.csproj`
            * `src/YourProduct.Ui/YourProduct.Ui.csproj` (e.g., Blazor)
            * `src/YourProduct.Functions/YourProduct.Functions.csproj`
        * `npm` roots:

            * `src/YourProduct.Ui/NpmJS`
            * `src/YourProduct.AdminUi/`
3. **Pipeline permissions:** allow your pipeline to read the `Dependency-Track` variable group and the GitHub templates repo (`audaciaconsulting/Audacia.Build`) via a service connection.

---

## Inputs (what you must provide)

* **`DT_API_URL` and `DT_API_KEY`** in the `Dependency-Track` variable group (secrets).
* **Release number** (`RELEASE_NUMBER`) that becomes the Dependency-Track project version as `release/<RELEASE_NUMBER>`.
* **Environment name** (`ENV_NAME`) used to tag Dependency-Track projects (e.g. `env:dev`, `env:qa`, `env:prod`).
* **Optional extra tags** (`ADDITIONAL_TAGS`) like `owner:team-x,service:orders`.
* **List of deployables** (paths for .NET csproj and npm roots) so the generator knows what to build SBOMs for.

> **About “parent projects” in Dependency-Track:**
> The upload step sets a `parentName` convention of `<ProjectName>.ProjectContainer`. You don’t need to pre-create it; uploads auto-create parents and projects when `autoCreate=true`. You’ll see a tidy hierarchy in the UI.

---

## Option A — E2E Pipeline (fastest start)

Create a pipeline file (e.g., `dependency-track-e2e.pipeline.yaml`) like this:

```yaml
name: $(Date:yyyyMMdd)
trigger: none
pr: none

resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: audaciaconsulting/Audacia.Build
      ref: refs/heads/feature/201961-refactor-dependency-track-pipeline-into-github-templates

pool:
  vmImage: windows-latest

variables:
  - group: Dependency-Track
  - name: CLIENT_NAME
    value: Olympus
  - name: ENV_NAME
    value: dev
  - name: RELEASE_NUMBER
    value: '1'
  - name: ADDITIONAL_TAGS
    value: 'owner:team-olympus,service:tickets'

stages:
  - stage: audit
    displayName: "Audit Dependencies (E2E)"
    variables:
      ApiProjectPath: $(System.DefaultWorkingDirectory)/src/YourProduct.Api/YourProduct.Api.csproj
      UiProjectPath: $(System.DefaultWorkingDirectory)/src/YourProduct.Ui/YourProduct.Ui.csproj
      FunctionsProjectPath: $(System.DefaultWorkingDirectory)/src/YourProduct.Functions/YourProduct.Functions.csproj
      UiNpmRoot: $(System.DefaultWorkingDirectory)/src/YourProduct.Ui/NpmJS
    jobs:
      - job: audit_dependencies
        displayName: "Generate → Upload → Deactivate"
        steps:
          # Either minimal "single-step" template:
          - template: /src/security/dependency-track/steps/audit-dependencies.step.yaml@templates

          # …or the richer E2E steps template that lets you pass options:
          - template: /src/security/dependency-track/steps/audit-dependencies.steps.yaml@templates
            parameters:
              dotnetProjectsMultiline: |
                $(ApiProjectPath)
                $(UiProjectPath)
                $(FunctionsProjectPath)
              npmRootsMultiline: |
                $(UiNpmRoot)
              publishArtifact: true
              artifactName: 'sbom-files'
              nodeVersion: '20.x'
              includeLicenseTexts: true
              failOnUploadError: true
              deactivateOld: true
              tryDownloadArtifact: true
```

**What this does:**

* Generates npm + .NET SBOMs (CycloneDX JSON), publishes them as a pipeline artifact.
* Uploads SBOMs to Dependency-Track:

    * auto-creates project if missing, sets version to `release/<RELEASE_NUMBER>`, marks it as latest, applies tags `env:<ENV_NAME>` + optional `ADDITIONAL_TAGS`.
    * waits for BOM processing tokens to finish.
* Deactivates older active versions so only the latest remains active in the portfolio.

---

## Option B — Staged Pipeline (more control)

Use `dependency-track.pipeline.yaml` (3 stages):

```yaml
name: $(Date:yyyyMMdd)
trigger: none
pr: none

resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: audaciaconsulting/Audacia.Build
      ref: refs/heads/feature/201961-refactor-dependency-track-pipeline-into-github-templates

pool:
  vmImage: windows-latest

variables:
  - group: Dependency-Track
  - name: CLIENT_NAME
    value: Olympus
  - name: ENV_NAME
    value: dev
  - name: RELEASE_NUMBER
    value: '1'
  - name: ADDITIONAL_TAGS
    value: 'owner:team-olympus,service:tickets'

stages:
  # 1) Generate SBOMs
  - stage: generate
    displayName: "Generate SBOMs (npm + .NET via CycloneDX)"
    jobs:
      - job: generate_sbom
        variables:
          ApiProjectPath: $(System.DefaultWorkingDirectory)/src/YourProduct.Api/YourProduct.Api.csproj
          UiProjectPath: $(System.DefaultWorkingDirectory)/src/YourProduct.Ui/YourProduct.Ui.csproj
          FunctionsProjectPath: $(System.DefaultWorkingDirectory)/src/YourProduct.Functions/YourProduct.Functions.csproj
          UiNpmRoot: $(System.DefaultWorkingDirectory)/src/YourProduct.Ui/NpmJS
        steps:
          - template: /src/security/dependency-track/steps/generate-sbom.steps.yaml@templates
            parameters:
              dotnetProjectsMultiline: |
                $(ApiProjectPath)
                $(UiProjectPath)
                $(FunctionsProjectPath)
              npmRootsMultiline: |
                $(UiNpmRoot)
              publishArtifact: true
              artifactName: 'sbom-files'
              nodeVersion: '20.x'
              includeLicenseTexts: true

          # expose "sbomReady" for the next stage
          - pwsh: |
              if ('$(sbomExists)' -eq 'true') {
                Write-Host "##vso[task.setvariable variable=sbomReady;isOutput=true]true"
              } else {
                Write-Host "##vso[task.setvariable variable=sbomReady;isOutput=true]false"
              }
            name: exportSbomReady
            displayName: "Export SBOM readiness as stage output"

  # 2) Upload to Dependency-Track (gated on generate success + SBOM existence)
  - stage: upload
    displayName: "Upload SBOMs to Dependency-Track"
    dependsOn: generate
    condition: and(succeeded('generate'), eq(dependencies.generate.outputs['generate_sbom.exportSbomReady.sbomReady'], 'true'))
    jobs:
      - job: upload_sbom
        steps:
          - template: /src/security/dependency-track/steps/upload-sbom.steps.yaml@templates
            parameters:
              failOnUploadError: true

  # 3) Deactivate non-latest versions (toggle by stage inclusion)
  - stage: deactivate
    displayName: "Deactivate old Dependency-Track project versions"
    dependsOn: upload
    condition: succeeded('upload')
    jobs:
      - job: deactivate_old_versions
        steps:
          - template: /src/security/dependency-track/steps/deactivate-nonlatest.steps.yaml@templates
            parameters:
              artifactName: 'sbom-files'
              tryDownloadArtifact: true
```

**Why this is useful:**

* You can run **Generate** on PRs (fast feedback), but only **Upload + Deactivate** on protected branches.
* You can re-run just the **Upload** stage if Dependency-Track was temporarily unavailable.

---

## What does “Deactivate non-latest” actually do?

After a successful upload, the deactivation step queries the SBOMs to derive the affected project names and sets all **active, non-latest** versions of these projects to inactive.
Result: your Dependency-Track portfolio shows the latest version as active; older versions remain in the database for history but no longer clutter dashboards or trigger current policy checks.

> You can skip this step for PRs or experimental branches by removing the stage or toggling the `deactivateOld` parameter (in E2E).

---

## Tags & Metadata

* Every upload applies `env:<ENV_NAME>` so you can filter projects by environment in Dependency-Track.
* Add business metadata via `ADDITIONAL_TAGS`, e.g.:

    * `owner:team-olympus`
    * `service:tickets`
    * `priority:high`
* The project version is standardized as `release/<RELEASE_NUMBER>`.

---

## Security Notes

* Store `DT_API_KEY` and `DT_API_URL` as **secrets** in the `Dependency-Track` variable group.
* Use least privilege for the API key (e.g., a dedicated **Automation** team in Dependency-Track with just the permissions needed to upload and create projects).
* These templates read secrets from **task environment variables** (not inline string injection) to avoid PowerShell escaping issues.

Relevant official docs for later reference:

* Projects & versions: *Docs → User Guide → Projects*
* API & BOM upload: *Docs → Integrations → API → BOM*
* Auth: *Docs → Administration → Access Management*
  (See [https://docs.dependencytrack.org/](https://docs.dependencytrack.org/) for the latest paths.)

---

## Troubleshooting

* **“No SBOM files to upload”**
  Make sure the Generate stage ran and published the `sbom-files` artifact. Check the generator’s “Validate expected SBOMs” output.
* **“.NET SBOMs failed” or “npm SBOMs failed”**
  Ensure the listed project paths / npm roots exist and build. For npm, commit a `package-lock.json` or let the generator create one.
* **API auth errors**
  Verify `DT_API_URL` and `DT_API_KEY` values and that the key has upload permissions.
* **Project naming**
  The upload step prefers the SBOM’s `metadata.component.name`. If missing, it falls back to the folder name. You can influence names by ensuring SBOM generators include `metadata.component` correctly.

---

## Quick Checklist (new repo)

* [ ] Create `Dependency-Track` variable group with `DT_API_URL` and `DT_API_KEY`.
* [ ] Add the pipeline file (E2E or staged) with your deployable paths and npm roots.
* [ ] Set `ENV_NAME`, `RELEASE_NUMBER`, and `ADDITIONAL_TAGS` variables.
* [ ] Run **Generate**; confirm `sbom-files` artifact exists.
* [ ] Run **Upload**; confirm projects/versions appear in Dependency-Track UI.
* [ ] Optionally run **Deactivate**; confirm only latest versions remain active.

---

## Example: Typical Monolith + UI + Functions

* `.NET`:

    * `src/Olympus.Api/Olympus.Api.csproj`
    * `src/Olympus.Functions/Olympus.Functions.csproj`
* `npm`:

    * `src/Olympus.Ui/NpmJS` (Angular/Vue/Blazor JS Functionality)

Use those paths in `dotnetProjectsMultiline` and `npmRootsMultiline`. The pipeline will produce one SBOM per deployable, upload all of them, and standardize the version to your `RELEASE_NUMBER`.

---

If you hit anything odd, open the pipeline logs and expand:

* **Generate → Validate expected SBOMs**
* **Upload → Prepare SBOM upload (preflight)**
* **Upload → Upload SBOMs (Atomic/Rollback)**
  They print exactly what was found, planned, and uploaded so you can correct inputs quickly.
