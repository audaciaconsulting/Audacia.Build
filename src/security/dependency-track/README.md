# Dependency-Track Pipeline Templates

These Azure DevOps templates automate SBOM generation, upload to OWASP Dependency-Track, and optional deactivation of non-latest project versions.

## What is Dependency-Track?

[OWASP Dependency-Track](https://dependencytrack.org/) stores and analyses CycloneDX SBOMs for your applications, identifying vulnerabilities, license issues, and policy violations across your portfolio.  
Each upload creates or updates a project and version in Dependency-Track, which the platform monitors continuously.

## Two Ways to Run

| Approach             | File                                 | When to use                                                                                       |
| -------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Modular / Staged     | `dependency-track.pipeline.yaml`     | You want Generate, Upload, and Deactivate as separate stages for control and visibility.          |
| End-to-End           | `dependency-track-e2e.pipeline.yaml` | You want a single job that runs the whole flow in one go. Great for small repos or a quick start. |

## Prerequisites

### 1) Variable group with secrets

The API key for your Dependency-Track instance must be stored in a variable group linked to the pipeline.  
You can store this key as a secret in a standard variable group or in a variable group connected to Azure Key Vault.

If your project is hosted in the Audacia Azure DevOps or GitHub organization, create a variable group and link it to the shared Azure Key Vault.

If your project is hosted in a different organization, you can store the key as a secret or use a variable group linked to another Azure Key Vault.

### 2) Variables configured in the pipeline (optional)

These are defined as pipeline variables within each YAML file or via the “Variables” tab in Azure DevOps.

| Variable                 | Purpose                                                    | Example                    |
| ------------------------ |------------------------------------------------------------| -------------------------- |
| `ENV_NAME`               | Which environment this SBOM represents                     | `dev`, `qa`, `uat`, `prod` |
| `RELEASE_NUMBER`         | Project version value used on upload e.g. `$(Build.SourceBranchName)` | `main`                     |
| `ADDITIONAL_TAGS`        | Optional extra tags recorded on the Dependency-Track project | `owner:team-x,service:abc` |
| `DEACTIVATE_OLD`         | Whether to mark all older versions inactive after upload   | `true`                     |
| `PARENT_PROJECT_NAME`    | Optional parent “container” in Dependency-Track            | `OrganisationName - ApplicationName` |
| `PARENT_PROJECT_VERSION` | Version of the parent (may be left empty)                  | `2025.10` or empty         |

> ⚠️ Parent projects must match on both name and version exactly (case-sensitive) in Dependency-Track for the link to be established. If the version is left empty or no exact match exists, uploads still succeed but no parent link is created.

## Typical Repo Layout (SPA + .NET)

Most repositories follow this structure:

```

src/
├─ apis/src/YourProject.Api/YourProject.Api.csproj
├─ apis/src/YourProject.Functions/YourProject.Functions.csproj
├─ apis/src/YourProject.Identity/YourProject.Identity.csproj
├─ apis/src/YourProject.Seeding/YourProject.Seeding.csproj
└─ apps/your-single-page-application/    ← e.g. Angular project root (package.json / package-lock.json)

````

The templates will:
- Generate .NET SBOMs via `dotnet CycloneDX` for each listed `.csproj`.
- Generate npm SBOMs via `@cyclonedx/cyclonedx-npm` for each listed SPA root folder (where `package.json` lives).  
  If `package-lock.json` isn’t present, the step will create one and run a minimal install for resolution.

> The template automatically installs the necessary tools (`CycloneDX` and `@cyclonedx/cyclonedx-npm`) if not already available.

## Naming Note

Before running the pipeline, verify that the names defined in your `.csproj` and `package.json` files are correct, consistent, and descriptive.  
Dependency-Track uses these names directly from the SBOMs to create or update projects.

Avoid:
- Too generic names (`"App"`, `"WebApplication1"`)
- Duplicates across repositories
- Inconsistent naming across components

Recommended naming conventions:
- Backends: `Company.Product.Component`
- Frontends: `company-product-ui`

Ensure names reflect the deployable artifact or service that will appear in reports.

## Option 1: Modular / Staged Pipeline (recommended)

File in your repo: `dependency-track.pipeline.yaml`

> Example below is abridged — update repository paths and project names to match your solution.

```yaml
name: $(Date:yyyyMMdd)
trigger: none
pr: none

resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: yourorg/Audacia.Build

pool:
  vmImage: windows-latest

# Central variables (API URL/KEY should live in the variable group as secrets)
variables:
  - group: Organisation.ApplicationName.Dependency-Track
  - name: CLIENT_NAME
    value: ApplicationName
  - name: ENV_NAME
    value: dev
  - name: RELEASE_NUMBER
    value: $(Build.SourceBranchName)
  - name: ADDITIONAL_TAGS
    value: ''
  - name: DEACTIVATE_OLD
    value: true
  - name: PARENT_PROJECT_NAME
    value: 'Organisation - ApplicationName'
  - name: PARENT_PROJECT_VERSION
    value: ''
  - name: DT_API_KEY
    value: $(DT-API-KEY)
  - name: DT_API_URL
    value: ''

stages:
  # =========================
  # 1) GENERATE STAGE
  # =========================
  - stage: generate
    displayName: "Generate SBOMs (npm + .NET via CycloneDX)"
    jobs:
      - job: generate_sbom
        displayName: "Generate SBOMs & publish artifact"
        steps:
          - template: /src/security/dependency-track/steps/generate-sbom.steps.yaml@templates
            parameters:
              dotnetProjectsMultiline: |
                $(ApiProjectPath)
                $(UiProjectPath)
                $(FunctionsProjectPath)
              npmRootsMultiline: |
                $(UiNpmRoot)
              publishArtifact: ${{ variables.PublishArtifact }}
              artifactName: $(ArtifactName)
              nodeVersion: $(NodeVersion)

  # =========================
  # 2) UPLOAD STAGE
  # =========================
  - stage: upload
    displayName: "Upload SBOMs to Dependency-Track"
    dependsOn: generate
    jobs:
      - job: upload_sbom
        displayName: "Upload SBOM & Log Summary"
        steps:
          - checkout: none
          - template: /src/security/dependency-track/steps/upload-sbom.steps.yaml@templates
            parameters:
              failOnUploadError: ${{ variables.FailOnUploadError }}
              parentProjectName: ${{ variables.PARENT_PROJECT_NAME }}
              parentProjectVersion: ${{ variables.PARENT_PROJECT_VERSION }}

  # =========================
  # 3) DEACTIVATE STAGE (run standalone or after upload)
  # =========================
  - stage: deactivate
    displayName: "Deactivate old Dependency-Track project versions"
    dependsOn: upload
    condition: and(succeeded('upload'), eq(variables['DEACTIVATE_OLD'], true))
    jobs:
      - job: deactivate_old_versions
        displayName: "Set non-latest versions to inactive"
        steps:
          - checkout: none
          - template: /src/security/dependency-track/steps/deactivate-nonlatest.steps.yaml@templates
            parameters:
              artifactName: $(ArtifactName)
              tryDownloadArtifact: ${{ variables.TryDownloadArtifact }}
              parentProjectName: ${{ variables.PARENT_PROJECT_NAME }}
````

## Option 2: End-to-End (Single Job)

File in your repo: `dependency-track-e2e.pipeline.yaml`
Runs Generate → Upload → Deactivate in one job using variables.

```yaml

# RUN E2E TEMPLATE JOB
name: $(Date:yyyyMMdd)
trigger: none
pr: none

resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: yourorg/Audacia.Build

pool:
  vmImage: windows-latest

# ---------------------------------------------------------------------------------
# NOTE: Ensure your application / project names in package.json and .csproj files
# are sensible and representative. These names are used as the Project name in
# Dependency-Track when SBOMs are uploaded.
# ---------------------------------------------------------------------------------

variables:
  - group: Audacia.Olympus.Dependency-Track
  - name: CLIENT_NAME
    value: Olympus

  # Runtime config (edit defaults per repo/branch as needed)
  - name: ENV_NAME
    value: dev
  - name: RELEASE_NUMBER
    value: $(Build.SourceBranchName)
  - name: ADDITIONAL_TAGS
    value: ' '
  - name: DEACTIVATE_OLD
    value: true

  - name: DT_API_KEY
    value: $(DT-API-KEY)
  - name: DT_API_URL
    value: ''

  # Optional parent project for upload linkage
  - name: PARENT_PROJECT_NAME
    value: 'Organisation - ApplicationName'
  - name: PARENT_PROJECT_VERSION
    value: ''

  # Project paths and settings
  - name: ApiProjectPath
    value: $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Api/Audacia.Olympus.Api.csproj
  - name: UiProjectPath
    value: $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Ui/Audacia.Olympus.Ui.csproj
  - name: FunctionsProjectPath
    value: $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Functions/Audacia.Olympus.Functions.csproj
  - name: UiNpmRoot
    value: $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Ui/NpmJS
  - name: NodeVersion
    value: '20.x'
  - name: ArtifactName
    value: 'sbom-files'
  - name: PublishArtifact
    value: true
  - name: FailOnUploadError
    value: true
  - name: TryDownloadArtifact
    value: true

stages:
  - stage: audit
    displayName: "Audit Dependencies (E2E)"
    jobs:
      - job: audit_dependencies
        displayName: "Audit dependencies (generate → upload → deactivate)"
        steps:
          - template: /src/security/dependency-track/steps/audit-dependencies.steps.yaml@templates
            parameters:
              dotnetProjectsMultiline: |
                $(ApiProjectPath)
                $(UiProjectPath)
                $(FunctionsProjectPath)
              npmRootsMultiline: |
                $(UiNpmRoot)
              publishArtifact: ${{ variables.PublishArtifact }}
              artifactName: $(ArtifactName)
              nodeVersion: $(NodeVersion)
              failOnUploadError: ${{ variables.FailOnUploadError }}
              parentProjectName: ${{ variables.PARENT_PROJECT_NAME }}
              parentProjectVersion: ${{ variables.PARENT_PROJECT_VERSION }}
              deactivateOld: ${{ variables.DEACTIVATE_OLD }}
              tryDownloadArtifact: ${{ variables.TryDownloadArtifact }}

```

## Project Tags in Dependency-Track

The upload step builds tags like:

* `env:<ENV_NAME>` when `ENV_NAME` is set
* Optional comma-separated `ADDITIONAL_TAGS` (e.g. `owner:team-app,service:tickets`)

Tags appear in Dependency-Track under each project and help with filtering, dashboards, and portfolio access control.

## Parent Project Linking

If you provide `PARENT_PROJECT_NAME`, the upload attempts to set `parentName` and `parentVersion` for each SBOM.
Dependency-Track performs parent resolution via **exact name and version match (case-sensitive)**.
If no exact match is found, the child projects still upload successfully but remain unlinked.

Use the convention `"<Client> - <System>"` for all parent project names to keep the portfolio consistent.

## Deactivate Non-Latest Versions

After a successful upload, older versions of each project (where `isLatest=false`) are set to inactive.
This keeps the UI focused on the active release while preserving historical versions for audit.

## Azure DevOps Output

* Generate → SBOM file list and counts
* Upload → Markdown summary of projects and versions
* Deactivate → Confirmation of inactive versions set

## Troubleshooting

| Symptom                      | Likely cause                     | Fix                                                                   |
| ---------------------------- | -------------------------------- | --------------------------------------------------------------------- |
| `401 Unauthorized` on upload | API key invalid or expired       | Regenerate in Dependency-Track and update the variable group          |
| SBOM not linked to parent    | Name or version mismatch         | Ensure exact parent match exists in Dependency-Track                  |
| “No SBOM files to upload”    | Wrong paths or missing lockfiles | Check `.csproj` and SPA root paths; ensure `package-lock.json` exists |
| Deactivate skipped           | SBOM artifact missing            | Keep `tryDownloadArtifact: true`                                      |

## Verification Checklist

* [ ] Variable group with `DT_API_KEY`
* [ ] Variable group linked to Key Vault (if applicable)
* [ ] Correct `.csproj` and `package.json` names
* [ ] Accurate project paths in pipeline
* [ ] Parent project created in Dependency-Track
* [ ] Parent project variables set (`"<Organisation> - <System>"`)
* [ ] Pipeline variables defined: `ENV_NAME`, `RELEASE_NUMBER`, `DEACTIVATE_OLD`, `ADDITIONAL_TAGS` (optional)