# Dependency-Track Pipeline Templates

These Azure DevOps templates automate SBOM generation, upload to OWASP Dependency-Track, and optional deactivation of non-latest project versions.

---

## What is Dependency-Track?

[OWASP Dependency-Track](https://dependencytrack.org/) stores and analyses CycloneDX SBOMs for your applications to surface vulnerabilities, license issues, and policy violations across your portfolio.  
Each upload creates or updates a project and version in Dependency-Track, which the platform monitors continuously.

---

## Two Ways to Run

| Approach             | File                                 | When to use                                                                                       |
| -------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Modular / Staged     | `dependency-track.pipeline.yaml`     | You want Generate, Upload, and Deactivate as separate stages for control and visibility.          |
| End-to-End           | `dependency-track-e2e.pipeline.yaml` | You want a single job that runs the whole flow in one go. Great for small repos or a quick start. |

---

## Prerequisites

### 1) Variable group with secrets

The API key for your Dependency-Track instance must be stored in a variable group that is linked to the pipeline. You can store this key as a secret in a standard variable group or in a variable group connected to Azure Key Vault.

If your project is hosted in the Audacia GitHub organization, create a variable group and link it to our Azure Key Vault.

If your project is hosted in a different organization, you can store the key as a secret or use a variable group linked to a different Azure Key Vault.

### 2) Variables configured in the pipeline

These are defined as pipeline variables within each YAML file or via the “Variables” tab in Azure DevOps.

| Variable                 | Purpose                                                      | Example                    |
| ------------------------ | ------------------------------------------------------------ | -------------------------- |
| `ENV_NAME`               | Which environment this SBOM represents                       | `dev`, `qa`, `uat`, `prod` |
| `RELEASE_NUMBER`         | Project version value used on upload                         | `main`                     |
| `ADDITIONAL_TAGS`        | Optional extra tags recorded on the Dependency-Track project | `owner:team-x,service:abc` |
| `DEACTIVATE_OLD`         | Whether to mark all older versions inactive after upload     | `true`                     |
| `PARENT_PROJECT_NAME`    | Optional parent “container” in Dependency-Track              | `Audacia - Olympus`        |
| `PARENT_PROJECT_VERSION` | Version of the parent (may be left empty)                    | `2025.10` or empty         |

> ⚠️ Parent projects must match on both name and version exactly in Dependency-Track for the link to be set. If the version is left empty (or no exact match exists), uploads still succeed but no parent link is established.

---

## Typical repo layout (Angular + .NET)

Most repositories follow this structure:

```

src/
├─ apis/src/YourProduct.Api/YourProduct.Api.csproj
├─ apis/src/YourProduct.Functions/YourProduct.Functions.csproj
├─ apis/src/YourProduct.Identity/YourProduct.Identity.csproj
├─ apis/src/YourProduct.Seeding/YourProduct.Seeding.csproj
└─ apps/your-angular-app/              ← Angular project root (package.json / package-lock.json)

````

The templates will:
- Generate .NET SBOMs via `dotnet CycloneDX` for each listed `.csproj`.
- Generate npm SBOMs via `@cyclonedx/cyclonedx-npm` for each listed Angular root folder (where `package.json` lives).  
  If `package-lock.json` isn’t present, the step will create one and run a minimal install for resolution.

---

## Naming note

Before running the pipeline, verify that the names defined in your `.csproj` and `package.json` files are correct, consistent, and descriptive.  
Dependency-Track uses these names directly from the SBOMs to create or update projects.

If these values are:
- too generic (`"App"` or `"WebApplication1"`)
- duplicated across repos
- inconsistent with your team’s naming scheme

then Dependency-Track will show confusing or duplicate project entries.

Recommended naming conventions:
- Backends: `Company.Product.Component` (e.g. `Audacia.Olympus.Api`)
- Frontends: `company-product-ui` (e.g. `audacia-olympus-ui`)

Ensure these names reflect the deployable artefact or service that will appear in reports.

---

## Option 1: Modular / Staged pipeline (recommended)

File in your repo: `dependency-track.pipeline.yaml`  
This pattern is used by Park Blue and Olympus (Angular UI + .NET backends).

```yaml
# Example (abridged)
name: $(Date:yyyyMMdd)
trigger: none
pr: none

resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: audaciaconsulting/Audacia.Build

pool:
  vmImage: windows-latest

# Central variables (API URL/KEY should live in the variable group as secrets)
variables:
  - group: ParkBlue.SaferRecruitment.Dependency-Track
  - name: CLIENT_NAME
    value: Olympus
  - name: ENV_NAME
    value: dev
  - name: RELEASE_NUMBER
    value: $(Build.SourceBranchName)
  - name: ADDITIONAL_TAGS
    value: ''
  - name: DEACTIVATE_OLD
    value: true
  - name: PARENT_PROJECT_NAME
    value: 'Park Blue - Safer Recruitment'
  - name: PARENT_PROJECT_VERSION
    value: ''

  - name: DT_API_KEY
    value: $(DT-API-KEY)
  - name: DT_API_URL
    value: 'https://api.dependency-track.audacia.tech/api'

stages:
  - stage: generate
    displayName: "Generate SBOMs (npm + .NET via CycloneDX)"
    jobs:
      - job: generate_sbom
        displayName: "Generate SBOMs & publish artifact"
        variables:
          ApiProjectPath: $(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Api/ParkBlue.SaferRecruitment.Api.csproj
          IdentityProjectPath: $(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Identity/ParkBlue.SaferRecruitment.Identity.csproj
          SeedingProjectPath: $(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Seeding/ParkBlue.SaferRecruitment.Seeding.csproj
          UiNpmRoot: $(System.DefaultWorkingDirectory)/src/apps/park-blue
        steps:
          - template: /src/security/dependency-track/steps/generate-sbom.steps.yaml@templates
            parameters:
              dotnetProjectsMultiline: |
                $(ApiProjectPath)
                $(IdentityProjectPath)
                $(SeedingProjectPath)
              npmRootsMultiline: |
                $(UiNpmRoot)
              publishArtifact: true
              artifactName: 'sbom-files'
              nodeVersion: '20.x'

          - pwsh: |
              Write-Host "sbomExists=$(sbomExists)"
              if ('$(sbomExists)' -eq 'true') {
                Write-Host "##vso[task.setvariable variable=sbomReady;isOutput=true]true"
              } else {
                Write-Host "##vso[task.setvariable variable=sbomReady;isOutput=true]false"
              }
            name: exportSbomReady
            displayName: "Mark SBOM Generation Complete"

  - stage: upload
    displayName: "Upload SBOMs to Dependency-Track"
    dependsOn: generate
    condition: and(succeeded('generate'), eq(dependencies.generate.outputs['generate_sbom.exportSbomReady.sbomReady'], 'true'))
    jobs:
      - job: upload_sbom
        displayName: "Upload SBOM & Log Summary"
        steps:
          - checkout: none
          - template: /src/security/dependency-track/steps/upload-sbom.steps.yaml@templates
            parameters:
              failOnUploadError: true
              parentProjectName: $(PARENT_PROJECT_NAME)
              parentProjectVersion: $(PARENT_PROJECT_VERSION)

  - stage: deactivate
    displayName: "Deactivate old Dependency-Track project versions"
    dependsOn: upload
    condition: and(succeeded('upload'), eq(variables.DEACTIVATE_OLD, true))
    jobs:
      - job: deactivate_old_versions
        displayName: "Set non-latest versions to inactive"
        steps:
          - checkout: none
          - template: /src/security/dependency-track/steps/deactivate-nonlatest.steps.yaml@templates
            parameters:
              artifactName: 'sbom-files'
              tryDownloadArtifact: true
````

---

## Option 2: End-to-End (single job)

File in your repo: `dependency-track-e2e.pipeline.yaml`
Runs Generate → Upload → Deactivate in one job using variables.

```yaml
- template: /src/security/dependency-track/steps/audit-dependencies.steps.yaml@templates
  parameters:
    dotnetProjectsMultiline: |
      $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Api/Audacia.Olympus.Api.csproj
      $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Ui/Audacia.Olympus.Ui.csproj
      $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Functions/Audacia.Olympus.Functions.csproj
    npmRootsMultiline: |
      $(System.DefaultWorkingDirectory)/src/Audacia.Olympus.Ui/NpmJS
    publishArtifact: true
    artifactName: sbom-files
    nodeVersion: '20.x'
    failOnUploadError: true
    parentProjectName: ${{ variables.PARENT_PROJECT_NAME }}
    parentProjectVersion: ${{ variables.PARENT_PROJECT_VERSION }}
    deactivateOld: ${{ variables.DEACTIVATE_OLD }}
    tryDownloadArtifact: true
```

---

## Project tags in Dependency-Track

The upload step builds tags like:

* `env:<ENV_NAME>` when `ENV_NAME` is set
* Optional comma-separated `ADDITIONAL_TAGS` (e.g. `owner:team-olympus,service:tickets`)

Tags appear in Dependency-Track under each project and help with filtering, dashboards, and portfolio access control.

---

## Parent project linking

If you provide `PARENT_PROJECT_NAME`, the upload attempts to set `parentName` and `parentVersion` for each SBOM.
Dependency-Track resolves the parent by exact name and version.
If there’s no exact match, the children still upload but will not be linked.

Use the convention `"<Client> - <System>"` for all parent project names to keep the portfolio consistent.

---

## Deactivate non-latest versions

After a successful upload, older versions of each project (where `isLatest=false`) are set to inactive.
This keeps the UI focused on the active release while preserving history for audit.

---

## Azure DevOps output

* Generate → SBOM file list and counts
* Upload → Markdown summary of projects and versions
* Deactivate → Confirmation of inactive versions set

---

## Troubleshooting

| Symptom                      | Likely cause                     | Fix                                                                       |
| ---------------------------- | -------------------------------- | ------------------------------------------------------------------------- |
| `401 Unauthorized` on upload | API key invalid or expired       | Regenerate in Dependency-Track and update variable group                  |
| SBOM not linked to parent    | Name or version mismatch         | Ensure exact parent match exists in Dependency-Track                      |
| “No SBOM files to upload”    | Wrong paths or missing lockfiles | Check `.csproj` and Angular root paths; ensure `package-lock.json` exists |
| Deactivate skipped           | SBOM artifact missing            | Keep `tryDownloadArtifact: true`                                          |

---

## Quick start checklist

* [ ] Variable group with `DT_API_URL` and `DT_API_KEY`
* [ ] Correct `.csproj` and `package.json` names
* [ ] Accurate project paths in pipeline
* [ ] Parent project created in Dependency-Track
* [ ] Parent project variables set (`"<Client> - <System>"`)
* [ ] Pipeline variables defined: `ENV_NAME`, `RELEASE_NUMBER`, `DEACTIVATE_OLD`, `ADDITIONAL_TAGS` (optional)