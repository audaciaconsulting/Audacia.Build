# 🧩 Dependency-Track Pipeline Templates

These Azure DevOps templates automate **SBOM generation**, **upload to OWASP Dependency-Track**, and optional **deactivation of non-latest project versions**.

They support the repo layout we use most often: **Angular (npm) UI + .NET backend(s)** (APIs, Worker/Functions, etc.).

---

## 📖 What is Dependency-Track?

[OWASP Dependency-Track](https://dependencytrack.org/) stores and analyses **CycloneDX SBOMs** for your apps to surface **vulnerabilities**, **license issues**, and **policy violations** across your portfolio.
Each upload creates or updates a **Project** and **Version** in Dependency-Track, which the platform monitors continuously.

---

## 🧱 Two Ways to Run

| Approach             | File                                 | When to use                                                                                       |
| -------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| **Modular / Staged** | `dependency-track.pipeline.yaml`     | You want **Generate**, **Upload**, **Deactivate** as separate stages for control/visibility.      |
| **End-to-End**       | `dependency-track-e2e.pipeline.yaml` | You want a single job that runs the whole flow in one go. Great for small repos or a quick start. |

---

## 🧰 Prerequisites

### 1) Variable group with secrets

Create an Azure DevOps variable group (per repo/team) that holds the Dependency-Track connection:

| Variable     | Purpose                                                                                  | Example                                     |
| ------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------- |
| `DT_API_URL` | Dependency-Track API base URL                                                            | `https://dependency-track.audacia.tech/api` |
| `DT_API_KEY` | API key issued to a Dependency-Track **Team** with permissions to upload/manage projects | `***secret***`                              |

Recommended team permissions:
`ACCESS_MANAGEMENT`, `BOM_UPLOAD`, `PORTFOLIO_MANAGEMENT`, `PROJECT_CREATION_UPLOAD`, `VIEW_PORTFOLIO`.

### 2) Variables you’ll configure in the pipeline

These are defined as **pipeline variables** (not parameters) within each YAML file or via the “Variables” tab in Azure DevOps.

| Variable                 | Purpose                                                                 | Example                    |
| ------------------------ | ----------------------------------------------------------------------- | -------------------------- |
| `ENV_NAME`               | Which environment this SBOM represents                                  | `dev`, `qa`, `uat`, `prod` |
| `RELEASE_NUMBER`         | Your release/build number (used as project version: `release/<number>`) | `2025.10.08.1`             |
| `ADDITIONAL_TAGS`        | Optional extra tags recorded on the Dependency-Track project            | `owner:team-x,service:abc` |
| `DEACTIVATE_OLD`         | Whether to mark all older versions inactive after upload                | `true`                     |
| `PARENT_PROJECT_NAME`    | Optional parent “container” in Dependency-Track                         | `Audacia - Olympus`        |
| `PARENT_PROJECT_VERSION` | Version of the parent                                                   | `2025.10`                  |

> ⚠️ **Parent projects must match on *both* Name and Version exactly** in Dependency-Track or the link won’t be set.
> In Olympus we standardise parent names as: **`"<Client> - <System>"`**
> Examples: `Accugrit - IGLU`, `Solus - Evolve`, `Audacia - Olympus`.

---

## 🗂️ Typical repo layout (Angular + .NET)

Most of our repos look like:

```
src/
 ├─ apis/src/YourProduct.Api/YourProduct.Api.csproj
 ├─ apis/src/YourProduct.Identity/YourProduct.Identity.csproj
 ├─ apis/src/YourProduct.Seeding/YourProduct.Seeding.csproj
 └─ apps/your-angular-app/              ← Angular project root (package.json / package-lock.json)
```

The templates will:

* Generate **.NET SBOMs** via `dotnet CycloneDX` for each listed `.csproj`.
* Generate an **npm SBOM** via `@cyclonedx/cyclonedx-npm` for each listed Angular root folder (where `package.json` lives).
  If `package-lock.json` isn’t present, the step will create one and run a minimal install for resolution.

---

## ⚠️ Naming Note — check your project names

Before running the pipeline, **verify that the names defined in your `.csproj` and `package.json` files are correct, consistent, and descriptive**.

Dependency-Track uses these names directly from the SBOMs to create or update projects.

If these values are:

* too generic (`"App"` or `"WebApplication1"`),
* duplicated across repos, or
* inconsistent with your team’s naming scheme,

then **Dependency-Track will show confusing or duplicate project entries**.

> ✅ Recommended convention:
>
> * **Backends:** `Company.Product.Component` (e.g. `Audacia.Olympus.Api`)
> * **Frontends:** `company-product-ui` (e.g. `audacia-olympus-ui`)

Ensure these names reflect the deployable artefact or service that will appear in reports.

---

## 🧩 Option 1: Modular / Staged pipeline (recommended)

**File in your repo:** `dependency-track.pipeline.yaml`

This is the pattern used by **Park Blue** (Angular UI + .NET backends).
Now uses **variables** instead of parameters — values are defined directly in the YAML or in the Azure DevOps Variables tab.

Example (abridged):

```yaml
variables:
  - group: ParkBlue.SaferRecruitment.Dependency-Track
  - name: CLIENT_NAME
    value: ParkBlue
  - name: ENV_NAME
    value: dev
  - name: RELEASE_NUMBER
    value: '1'
  - name: ADDITIONAL_TAGS
    value: ' '

stages:
  - stage: generate
    jobs:
      - job: generate_sbom
        steps:
          - template: /src/security/dependency-track/steps/generate-sbom.steps.yaml@templates
            parameters:
              dotnetProjectsMultiline: |
                $(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Api/ParkBlue.SaferRecruitment.Api.csproj
                $(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Identity/ParkBlue.SaferRecruitment.Identity.csproj
              npmRootsMultiline: |
                $(System.DefaultWorkingDirectory)/src/apps/park-blue
              publishArtifact: true
              artifactName: 'sbom-files'
              nodeVersion: '20.x'
              includeLicenseTexts: true
          - pwsh: |
              if ('$(sbomExists)' -eq 'true') {
                Write-Host "##vso[task.setvariable variable=sbomReady;isOutput=true]true"
              } else {
                Write-Host "##vso[task.setvariable variable=sbomReady;isOutput=true]false"
              }
            name: exportSbomReady

  - stage: upload
    dependsOn: generate
    condition: and(succeeded('generate'), eq(dependencies.generate.outputs['generate_sbom.exportSbomReady.sbomReady'], 'true'))
    jobs:
      - job: upload_sbom
        steps:
          - checkout: none
          - template: /src/security/dependency-track/steps/upload-sbom.steps.yaml@templates
            parameters:
              failOnUploadError: true
              parentProjectName: ${{ variables.PARENT_PROJECT_NAME }}
              parentProjectVersion: ${{ variables.PARENT_PROJECT_VERSION }}

  - stage: deactivate
    dependsOn: upload
    condition: and(succeeded('upload'), eq(variables['DEACTIVATE_OLD'], 'true'))
    jobs:
      - job: deactivate_old_versions
        steps:
          - checkout: none
          - template: /src/security/dependency-track/steps/deactivate-nonlatest.steps.yaml@templates
            parameters:
              artifactName: 'sbom-files'
              tryDownloadArtifact: true
```

---

## ⚙️ Option 2: End-to-End (single job)

**File in your repo:** `dependency-track-e2e.pipeline.yaml`

Runs **Generate → Upload → Deactivate** in one job, using variables instead of parameters.

```yaml
- template: /src/security/dependency-track/steps/audit-dependencies.steps.yaml@templates
  parameters:
    dotnetProjectsMultiline: |
      src/apis/src/ParkBlue.SaferRecruitment.Api/ParkBlue.SaferRecruitment.Api.csproj
      src/apis/src/ParkBlue.SaferRecruitment.Identity/ParkBlue.SaferRecruitment.Identity.csproj
      src/apis/src/ParkBlue.SaferRecruitment.Seeding/ParkBlue.SaferRecruitment.Seeding.csproj
    npmRootsMultiline: |
      src/apps/park-blue
    publishArtifact: true
    artifactName: sbom-files
    nodeVersion: '20.x'
    includeLicenseTexts: true
    failOnUploadError: true
    parentProjectName: ${{ variables.PARENT_PROJECT_NAME }}
    parentProjectVersion: ${{ variables.PARENT_PROJECT_VERSION }}
    deactivateOld: ${{ variables.DEACTIVATE_OLD }}
    tryDownloadArtifact: true
```

---

## 🏷️ Project Tags in Dependency-Track

The upload step builds tags like:

* Always: `env:<ENV_NAME>`
* Optional: any comma-separated `ADDITIONAL_TAGS` (e.g. `owner:team-olympus,service:tickets`)

Tags appear in Dependency-Track under each project and help with filtering, dashboards, and Portfolio Access Control.

---

## 🧲 Parent Project Linking

If you provide both:

* `PARENT_PROJECT_NAME` (e.g. `Audacia - Olympus`)
* `PARENT_PROJECT_VERSION` (e.g. `2025.10`)

…the upload sets these as `parentName` / `parentVersion` for each SBOM.
Dependency-Track resolves the **parent by exact name and version**.
If there’s no exact match, the children still upload but will not be linked.

> 🔑 Use the convention **`"<Client> - <System>"`** for all parent project names to keep the portfolio consistent.

---

## 🧹 Deactivate Non-Latest: what it actually does

After a successful upload, older versions of each project (where `isLatest=false`) are set to **inactive**.
This keeps the UI focused on the active release, while preserving history for audit.

---

## 📊 Azure DevOps output

* **Generate** → SBOM file list & counts
* **Upload** → Markdown summary of projects and versions
* **Deactivate** → Confirmation of inactive versions set

---

## 🛠️ Troubleshooting

| Symptom                      | Likely cause                     | Fix                                                                       |
| ---------------------------- | -------------------------------- | ------------------------------------------------------------------------- |
| `401 Unauthorized` on upload | API key invalid/expired          | Regenerate in Dependency-Track; update variable group                     |
| SBOM not linked to parent    | Name/version mismatch            | Ensure exact parent match exists in Dependency-Track                      |
| “No SBOM files to upload”    | Wrong paths or missing lockfiles | Check `.csproj` and Angular root paths; ensure `package-lock.json` exists |
| Deactivate skipped           | SBOM artifact missing            | Keep `tryDownloadArtifact: true`                                          |

---

## ✅ Quick start checklist

* [ ] Variable group with `DT_API_URL` + `DT_API_KEY`
* [ ] Correct `.csproj` and `package.json` names (see **⚠️ Naming Note**)
* [ ] Accurate project paths in pipeline
* [ ] Parent project created in Dependency-Track
* [ ] Parent project variables set (`"<Client> - <System>"`)
* [ ] Pipeline variables defined:
  `ENV_NAME`, `RELEASE_NUMBER`, `DEACTIVATE_OLD`, `ADDITIONAL_TAGS` (optional)

---
