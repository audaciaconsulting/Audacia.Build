# Dependency-Track Pipeline Templates

These Azure Pipelines templates automate SBOM generation, upload to OWASP Dependency-Track, and optional deactivation of non-latest project versions.

## What is Dependency-Track?

[OWASP Dependency-Track](https://dependencytrack.org/) stores and analyses CycloneDX SBOMs for your applications, identifying vulnerabilities, license issues, and policy violations across your portfolio.
Each upload creates or updates a project and version in Dependency-Track, which the platform monitors continuously.

## Two Ways to Run

| Approach         | When to use                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| Modular / Staged | You want Generate, Upload, and Deactivate as separate stages for control and visibility.          |
| End-to-End       | You want a single job that runs the whole flow in one go. Great for small repos or a quick start. |

> **Implementation note:**
> When using the SBOM generator templates (`generate-dotnet-sbom.steps.yaml` and `generate-npm-sbom.steps.yaml`), the `publishArtifact` variable controls whether each generator publishes its output as a pipeline artifact.
>
> - **If you are running only one generator** (for example, just the .NET or npm template), set `publishArtifact: true` to publish its SBOMs directly.
> - **If you are running multiple generators** (for example, both .NET and npm), set `publishArtifact: false` on each generator and add a single `PublishPipelineArtifact@1` step afterwards. This publishes a single combined artifact (e.g. `sbom-files`) containing all SBOM outputs.
>
> This approach ensures:
> - A single, consolidated SBOM artifact for multi-ecosystem projects
> - No duplicate or conflicting artifact names
> - Consistent behavior between modular (staged) and end-to-end pipeline designs

## Prerequisites

### 1) Variable group with secrets

To authenticate with your Dependency-Track instance, you must provide an API key to the pipeline. Store this key securely using your preferred secret management mechanism (such as a variable group, environment variable, or secret store) and ensure it is accessible to the pipeline at runtime.

If using Azure DevOps, you can store the key as a secret in a variable group or connect it to Azure Key Vault. For other CI/CD systems, follow the recommended approach for securely managing secrets in your environment.

### 2) Variables configured in the pipeline (optional)

These are defined as pipeline variables within each YAML file or via the “Variables” tab in Azure DevOps.

| Variable               | Purpose                                                               | Example                              |
| ---------------------- | --------------------------------------------------------------------- | ------------------------------------ |
| `envName`              | Which environment this SBOM represents                                | `dev`, `qa`, `uat`, `prod`           |
| `version`              | Project version value used on upload e.g. `$(Build.SourceBranchName)` | `main`                               |
| `additionalTags`       | Optional extra tags recorded on the Dependency-Track project          | `owner:team-x,service:abc`           |
| `deactivateOld`        | Whether to mark all older versions inactive after upload              | `true`                               |
| `parentProjectName`    | Optional parent “container” in Dependency-Track                       | `OrganisationName - ApplicationName` |
| `parentProjectVersion` | Version of the parent (may be left empty)                             | `2025.10` or empty                   |

> ⚠️ Parent projects must match on both name and version exactly (case-sensitive) in Dependency-Track for the link to be established. If the version is left empty or no exact match exists, uploads still succeed but no parent link is created.

## Specifying Projects for SBOM Generation

When specifying a .NET project, the template expects a `.csproj` file to be specified.
Examples might include:

- `$(System.DefaultWorkingDirectory)/src/YourProject.Api/YourProject.Api.csproj`
- `$(System.DefaultWorkingDirectory)/src/YourProject.Functions/YourProject.Functions.csproj`
- `$(System.DefaultWorkingDirectory)/src/YourProject.Identity/YourProject.Identity.csproj`
- `$(System.DefaultWorkingDirectory)/src/YourProject.Seeding/YourProject.Seeding.csproj`

When specifying an npm project, the template expects **the directory** that contains the `package.json` and `package-lock.json` files.
Examples might include:

- `$(System.DefaultWorkingDirectory)/src/YourProject.Ui`
- `$(System.DefaultWorkingDirectory)/src/apps`
- `$(System.DefaultWorkingDirectory)/playwright`
- `$(System.DefaultWorkingDirectory)/performance`

Optional `.npmrc` paths can also be provided for authentication against private feeds.  
Each `.npmrc` will be authenticated separately using `npmAuthenticate@0` before SBOM generation.

The templates will:

- Generate .NET SBOMs via `dotnet CycloneDX` for each listed `.csproj`.
- Generate npm SBOMs via `@cyclonedx/cyclonedx-npm` for each listed SPA root folder (where `package.json` lives).
  If `package-lock.json` isn’t present, the step will create one and run a minimal install for resolution.
  When license text inclusion is enabled, `npm ci` is used for full dependency restoration.

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

The pipeline templates support adding tags to each project if required, enabling enhanced organization and filtering within Dependency-Track.

In Dependency-Track, tags appear under each project and support filtering, dashboards, and portfolio access control.

The upload step builds tags like:

- `env:<envName>` when `envName` is set
- Optional comma-separated `additionalTags` (for example `owner:team-app,service:tickets`)

## Parent Project Linking

If you provide `parentProjectName`, the upload attempts to set `parentName` and `parentVersion` for each SBOM.
Dependency-Track performs parent resolution via **exact name and version match (case-sensitive)**.
If no exact match is found, the child projects still upload successfully but remain unlinked.

Use the convention `"<Client> - <System>"` for all parent project names to keep the portfolio consistent.

## Deactivate Non-Latest Versions

After a successful upload, older versions of each project (where `isLatest=false`) are set to inactive.
This keeps the UI focused on the active release while preserving historical versions for audit.

## npm Dependency Tree Warnings

If `npm ls` detects issues such as missing dependencies, invalid versions, or peer conflicts,  
the SBOM generation step logs a warning (for example `npm error code ELSPROBLEMS`).  
This does **not** block SBOM generation or upload. The task completes as “Succeeded with issues”,  
and Dependency-Track still receives the SBOM. Developers should resolve dependency tree issues  
to maintain accurate evidence and reproducibility.

## Azure DevOps Output

- Generate → SBOM file list and counts
- Upload → summary of projects and versions
- Deactivate → Confirmation of inactive versions set

## Troubleshooting

| Symptom                                  | Likely cause                                             | Fix                                                                                       |
| ---------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `401 Unauthorized` on upload             | API key invalid or expired                                | Regenerate in Dependency-Track and update the variable group                              |
| SBOM not linked to parent                | Name or version mismatch                                  | Ensure exact parent match exists in Dependency-Track                                      |
| “No SBOM files to upload”                | Wrong paths or missing lockfiles                          | Check `.csproj` and SPA root paths; ensure `package-lock.json` exists                     |
| Deactivate skipped                       | SBOM artifact missing                                     | Keep `tryDownloadArtifact: true`                                                          |
| `ELSPROBLEMS` warning during npm SBOM    | Dependency tree inconsistencies detected by `npm ls`       | SBOMs still upload successfully; align dependency versions to remove warnings             |

## Verification Checklist

- [ ] Variable group with `DT_API_KEY`
- [ ] Variable group linked to Key Vault (if applicable)
- [ ] Correct `.csproj`, and `package.json` names
- [ ] Accurate project paths, and `npmrc` paths (if using) in pipeline
- [ ] Parent project created in Dependency-Track
- [ ] Parent project variables set (`"<Organisation> - <System>"`)
- [ ] Pipeline variables defined: `envName`, `version`, `deactivateOld`, `additionalTags` (optional)
