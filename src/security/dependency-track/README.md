# Dependency-Track Pipeline Templates

These Azure Pipelines templates automate SBOM generation, upload to OWASP Dependency-Track, and optional deactivation of non-latest project versions.

## What is Dependency-Track?

[OWASP Dependency-Track](https://dependencytrack.org/) stores and analyses CycloneDX SBOMs for your applications, identifying vulnerabilities, license issues, and policy violations across your portfolio.
Each upload creates or updates a project and version in Dependency-Track, which the platform monitors continuously.

## Two Ways to Run

| Approach         |  When to use                                                                                       |
| ---------------- |------------------------------------------------------------------------------------------------- |
| Modular / Staged | You want Generate, Upload, and Deactivate as separate stages for control and visibility.          |
| End-to-End       | You want a single job that runs the whole flow in one go. Great for small repos or a quick start. |

## Prerequisites

### 1) Variable group with secrets

To authenticate with your Dependency-Track instance, you must provide an API key to the pipeline. Store this key securely using your preferred secret management mechanism (such as a variable group, environment variable, or secret store) and ensure it is accessible to the pipeline at runtime.

If using Azure DevOps, you can store the key as a secret in a variable group or connect it to Azure Key Vault. For other CI/CD systems, follow the recommended approach for securely managing secrets in your environment.

### 2) Variables configured in the pipeline (optional)

These are defined as pipeline variables within each YAML file or via the “Variables” tab in Azure DevOps.

| Variable                 | Purpose                                                               | Example                              |
| ------------------------ | --------------------------------------------------------------------- | ------------------------------------ |
| `ENV_NAME`               | Which environment this SBOM represents                                | `dev`, `qa`, `uat`, `prod`           |
| `RELEASE_NUMBER`         | Project version value used on upload e.g. `$(Build.SourceBranchName)` | `main`                               |
| `ADDITIONAL_TAGS`        | Optional extra tags recorded on the Dependency-Track project          | `owner:team-x,service:abc`           |
| `DEACTIVATE_OLD`         | Whether to mark all older versions inactive after upload              | `true`                               |
| `PARENT_PROJECT_NAME`    | Optional parent “container” in Dependency-Track                       | `OrganisationName - ApplicationName` |
| `PARENT_PROJECT_VERSION` | Version of the parent (may be left empty)                             | `2025.10` or empty                   |

> ⚠️ Parent projects must match on both name and version exactly (case-sensitive) in Dependency-Track for the link to be established. If the version is left empty or no exact match exists, uploads still succeed but no parent link is created.

## Specifying Projects for SBOM Generation

Most repositories follow this structure:

```
src/
├─ apis/src/YourProject.Api/YourProject.Api.csproj
├─ apis/src/YourProject.Functions/YourProject.Functions.csproj
├─ apis/src/YourProject.Identity/YourProject.Identity.csproj
├─ apis/src/YourProject.Seeding/YourProject.Seeding.csproj
└─ apps/your-single-page-application/    ← e.g. Angular project root (package.json / package-lock.json)
```

The templates will:

* Generate .NET SBOMs via `dotnet CycloneDX` for each listed `.csproj`.
* Generate npm SBOMs via `@cyclonedx/cyclonedx-npm` for each listed SPA root folder (where `package.json` lives).
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


## Project Tags in Dependency-Track

Tags appear in Dependency-Track under each project and help with filtering, dashboards, and portfolio access control.
They are not currently used in our Dependency-Track architecture, however, they may be in the future when we potentially have SBOMs for multiple environments per project.
They have been left in place for now should individual teams wish to use them for their own purposes.

The upload step builds tags like:

* `env:<ENV_NAME>` when `ENV_NAME` is set
* Optional comma-separated `ADDITIONAL_TAGS` (e.g. `owner:team-app,service:tickets`)

## Parent Project Linking

If you provide `PARENT_PROJECT_NAME`, the upload attempts to set `parentName` and `parentVersion` for each SBOM.
Dependency-Track performs parent resolution via **exact name and version match (case-sensitive)**.
If no exact match is found, the child projects still upload successfully but remain unlinked.

Use the convention `"<Client> - <System>"` for all parent project names to keep the portfolio consistent.

## Deactivate Non-Latest Versions

After a successful upload, older versions of each project (where `isLatest=false`) are set to inactive.
This keeps the UI focused on the active release while preserving historical versions for audit.

## Azure DevOps Output

- Generate → SBOM file list and counts
- Upload → Markdown summary of projects and versions
- Deactivate → Confirmation of inactive versions set

## Troubleshooting

| Symptom                      | Likely cause                     | Fix                                                                   |
| ---------------------------- | -------------------------------- | --------------------------------------------------------------------- |
| `401 Unauthorized` on upload | API key invalid or expired       | Regenerate in Dependency-Track and update the variable group          |
| SBOM not linked to parent    | Name or version mismatch         | Ensure exact parent match exists in Dependency-Track                  |
| “No SBOM files to upload”    | Wrong paths or missing lockfiles | Check `.csproj` and SPA root paths; ensure `package-lock.json` exists |
| Deactivate skipped           | SBOM artifact missing            | Keep `tryDownloadArtifact: true`                                      |

## Verification Checklist

- [ ] Variable group with `DT_API_KEY`
- [ ] Variable group linked to Key Vault (if applicable)
- [ ] Correct `.csproj` and `package.json` names
- [ ] Accurate project paths in pipeline
- [ ] Parent project created in Dependency-Track
- [ ] Parent project variables set (`"<Organisation> - <System>"`)
- [ ] Pipeline variables defined: `ENV_NAME`, `RELEASE_NUMBER`, `DEACTIVATE_OLD`, `ADDITIONAL_TAGS` (optional)
