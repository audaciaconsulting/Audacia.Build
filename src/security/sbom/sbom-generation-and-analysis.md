# Azure DevOps SBOM & Vulnerability Analysis Pipeline Templates

This directory provides a set of reusable YAML templates to help you integrate SBOM (Software Bill of Materials) generation and vulnerability analysis into the Azure DevOps pipelines. Using these templates you can:

1. **Generate SBOMs** for the .NET Core (and related) projects by collecting package lock files (e.g. `package-lock.json` and `*.deps.json`) and running [Syft](https://github.com/anchore/syft).
2. **Analyze SBOMs** to produce vulnerability reports using [Grype](https://github.com/anchore/grype).
3. **Run a composite pipeline** that performs both SBOM generation and analysis in one go, providing a user‑friendly end-to‑end solution.

This document describes each template and explains how to use them individually as well as in a composite approach.

---

## Templates Overview

### 1. `net-core.steps.yaml`

This template is designed for building .NET Core projects. It:
- Restores, builds, tests, and publishes the .NET Core projects as before.
- **Optionally** collects lock/deps files (e.g. `package-lock.json` and `*.deps.json`) from the source directory.
- Publishes a job‑unique artifact (using the agent’s job name) to avoid conflicts when multiple jobs are used.

**Key Parameters:**
- **projects**: Glob pattern for project files (default: `**/*.csproj`).
- **runTests**: Boolean flag to run tests.
- **configuration**: Build configuration (e.g. `Release` or `Debug`).
- **publishLockDepsArtifact**: Set to `true` to enable collection and publishing of lock/deps files.
- **lockDepsOutputDir**: Directory where lock/deps files are collected (default: `$(Agent.TempDirectory)/lock-deps`).

**Usage:**  
Include this template in the build jobs. When `publishLockDepsArtifact` is enabled, each job publishes its lock/deps files under a unique name (e.g. `$(Agent.JobName)-lock-deps`).

---

### 2. `sbom-generation.yaml`

This template generates SBOM files from the published lock/deps artifact. It:
- Downloads the aggregated lock/deps artifact.
- Installs Syft (the SBOM generator) into a specified directory.
- Iterates through each lock/deps file and generates an SBOM using the chosen output format (default: `cyclonedx-json`).
- Optionally publishes the generated SBOMs as an artifact (default artifact name: `sbom-files`).

**Key Parameters:**
- **sbomOutputDir**: Local directory where SBOM files are stored (default: `$(Agent.TempDirectory)/sbom`).
- **lockDepsArtifactDir**: Directory containing the downloaded lock/deps files (if not provided, defaults to the download path).
- **outputFormat**: SBOM format (e.g. `cyclonedx-json`).
- **syftInstallDir**: Directory where Syft is installed.

**Usage:**  
Call this template in a stage dedicated to SBOM generation. It assumes that a lock‑deps artifact named `lock-deps-files` is available.

---

### 3. `sbom-analysis.yaml`

This template analyzes SBOM files to produce vulnerability reports. It:
- Optionally downloads the SBOM artifact if needed.
- Installs Grype (the vulnerability scanner) into a specified directory.
- Iterates over each SBOM file (using a glob pattern, default: `sbom-*.json`), runs Grype, and generates a corresponding vulnerability report (for example, `npm-vuln-report.json` for an SBOM named `npm-sbom.json` or replacing the `-sbom` suffix with `-vuln-report` for others).
- Publishes the generated vulnerability reports as an artifact (default: `vuln-files`).

**Key Parameters:**
- **sbomDir**: Directory where SBOM files are stored (default: `$(Agent.TempDirectory)/sbom`).
- **analysisOutputFormat**: Format for the vulnerability report (default: `cyclonedx-json`).
- **vulnFolder**: Directory to store vulnerability reports.
- **downloadArtifact**: Set to `true` to download the SBOM artifact before analysis.
- **grypeInstallDir**: Directory where Grype is installed.

**Usage:**  
Include this template in a stage dedicated to SBOM analysis. It will consume the SBOM artifact and produce vulnerability reports.

---

### 4. `sbom.steps.yaml` (Composite Template)

This composite template provides an end-to-end solution that:
1. Downloads the aggregated lock/deps artifact (if a custom path isn’t provided).
2. Runs SBOM generation (using `sbom-generation.yaml`).
3. Immediately follows with SBOM analysis (using `sbom-analysis.yaml`).

**Key Parameters:**
- All parameters from the individual generation and analysis templates (e.g. `sbomOutputDir`, `outputFormat`, `vulnFolder`, etc.).
- **lockDepsArtifactDir**: If not provided, the template will download the aggregated lock/deps artifact (published from the build stage) into a default location.
- **downloadArtifact** (for analysis): Set to `true` if the SBOM artifact should be downloaded.

**Usage:**  
Most users will use this composite template to generate and analyze SBOMs in one step. It abstracts the complexity of calling separate templates and provides a user‑friendly experience.

---

## How to Use These Templates in an Azure DevOps Pipeline

### A. SBOM Generation in Isolation

Use the `sbom-generation.yaml` template in a dedicated stage. For example:

```yaml
- stage: SBOM_Generation
  displayName: 'Generate SBOM Only'
  jobs:
    - job: GenerateSBOMOnly
      displayName: 'Generate SBOM from Lock Files'
      steps:
        - task: DownloadPipelineArtifact@2
          displayName: 'Download Lock/Deps Artifact'
          inputs:
            buildType: 'current'
            artifact: 'lock-deps-files'
            path: '$(Agent.TempDirectory)/lock-deps'
        - template: /src/security/sbom/steps/sbom-generation.yaml@templates
          parameters:
            sbomOutputDir: '$(Agent.TempDirectory)/sbom'
            lockDepsArtifactDir: '$(Agent.TempDirectory)/lock-deps'
            outputFormat: 'cyclonedx-json'
            publishArtifact: true
            artifactName: 'sbom-files'
            syftInstallDir: '$(Agent.TempDirectory)'
```

This stage downloads the lock/deps files, installs Syft, generates SBOMs, and publishes the resulting artifact.

---

### B. SBOM Analysis in Isolation

Use the `sbom-analysis.yaml` template in a dedicated stage. For example:

```yaml
- stage: SBOM_Analysis
  displayName: 'Analyze Existing SBOMs'
  jobs:
    - job: AnalyzeExistingSBOM
      displayName: 'Analyze SBOM Files'
      steps:
        - template: /src/security/sbom/steps/sbom-analysis.yaml@templates
          parameters:
            sbomDir: '$(Agent.TempDirectory)/sbom'
            sbomGlob: 'sbom-*.json'
            analysisOutputFormat: 'cyclonedx-json'
            vulnFolder: '$(Agent.TempDirectory)/vuln'
            downloadArtifact: true
            sbomArtifactName: 'sbom-files'
            grypeInstallDir: '$(Agent.TempDirectory)'
```

This stage downloads the SBOM artifact (if needed), installs Grype, runs the analysis, and publishes the vulnerability report artifact.

---

### C. Composite SBOM Generation & Analysis

Use the composite template (`sbom.steps.yaml`) to perform SBOM generation and analysis together. For example:

```yaml
- stage: SBOM_Composite
  displayName: 'Generate and Analyze SBOM'
  dependsOn: Build
  jobs:
    - job: GenerateAndAnalyzeSBOM
      displayName: 'Composite SBOM Generation and Analysis'
      continueOnError: true
      steps:
        - template: /src/security/sbom/steps/sbom.steps.yaml@templates
          parameters:
            sbomOutputDir: '$(Agent.TempDirectory)/sbom'
            lockDepsArtifactDir: '$(Agent.TempDirectory)/lock-deps'  # Or leave empty to download the aggregated artifact.
            outputFormat: 'cyclonedx-json'
            vulnFolder: '$(Agent.TempDirectory)/vuln'
            analysisOutputFormat: 'cyclonedx-json'
            downloadArtifact: false  # Set to true if the SBOM artifact must be downloaded.
            publishGenerationArtifact: true
            sbomArtifactName: 'sbom-files'
            syftInstallDir: '$(Agent.TempDirectory)'
            grypeInstallDir: '$(Agent.TempDirectory)'
```

In composite mode, the template:
- Downloads the aggregated lock/deps artifact (if no custom directory is provided),
- Generates the SBOM files, and
- Immediately analyzes them with Grype to produce vulnerability reports.

---

## Aggregating Lock/Deps Files

Since multiple build jobs using `net-core.steps.yaml` may publish separate lock/deps artifacts, an aggregation job (typically in the build stage) is used to combine them into a single artifact named **`lock-deps-files`**. For example, the `AggregateLockDeps` job in the build stage:
- Downloads all per‑job lock/deps artifacts.
- Uses a PowerShell script to copy files from each artifact into a single aggregated folder (deduplicating files in the process).
- Publishes the aggregated folder as `lock-deps-files`.

This aggregated artifact is then consumed by the SBOM generation and composite templates.

---

## Example Pipeline Structure

Below is an example pipeline (`dev.pipeline-sbom.yaml`) that brings together the build stage (including aggregation) and the composite SBOM stage:

```yaml
name: $(Year:yy)$(DayOfYear).$(rev:r)
trigger: none
resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: audaciaconsulting/Audacia.Build
      ref: feature/190253-add-pipeline-templates-for-sbom-functionality
pool: 
  vmImage: windows-latest

stages:
  - template: stages/build-sbom.stage.yaml
```

And a snippet from `build-sbom.stage.yaml`:

```yaml
stages:
  - stage: Build
    displayName: Build
    jobs:
      - job: BuildDotNet
        displayName: 'Build API'
        steps:
          - template: /src/build/dotnet/steps/net-core.steps.yaml@templates
            parameters:
              projects: '$(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Api/ParkBlue.SaferRecruitment.Api.csproj'
              runTests: true
              publishLockDepsArtifact: true
              lockDepsArtifactName: 'lock-deps-files'
              lockDepsOutputDir: '$(Agent.TempDirectory)/lock-deps'
      # (Other build jobs...)
      - job: AggregateLockDeps
        displayName: 'Aggregate Lock/Deps Files'
        dependsOn:
          - BuildDotNet
          # (Other dependencies...)
        pool:
          vmImage: windows-latest
        steps:
          - download: current
            displayName: 'Download all pipeline artifacts'
          - task: PowerShell@2
            displayName: 'Aggregate Lock/Deps Files into Single Folder'
            inputs:
              targetType: 'inline'
              script: |
                $aggregateDir = "$(Agent.TempDirectory)/lock-deps-aggregated"
                if (-Not (Test-Path $aggregateDir)) {
                    New-Item -ItemType Directory -Path $aggregateDir | Out-Null
                }
                $artifactDirs = Get-ChildItem -Path "$(Pipeline.Workspace)" -Directory | Where-Object { $_.Name -like "*-lock-deps" }
                foreach ($dir in $artifactDirs) {
                    Write-Host "Processing files from: $($dir.FullName)"
                    Get-ChildItem -Path $dir.FullName -File | ForEach-Object {
                        $destPath = Join-Path $aggregateDir $_.Name
                        if (-Not (Test-Path $destPath)) {
                            Write-Host "Copying file: $($_.Name)"
                            Copy-Item -Path $_.FullName -Destination $destPath -Force
                        }
                        else {
                            Write-Host "Duplicate file $($_.Name) found, skipping."
                        }
                    }
                }
          - task: PublishPipelineArtifact@1
            displayName: 'Publish Aggregated Lock/Deps Artifact'
            inputs:
              targetPath: '$(Agent.TempDirectory)/lock-deps-aggregated'
              artifact: 'lock-deps-files'
  - stage: SBOM_Composite
    displayName: 'Generate and Analyze SBOM'
    dependsOn: Build
    jobs:
      - job: GenerateAndAnalyzeSBOM
        displayName: 'Composite SBOM Generation and Analysis'
        continueOnError: true
        steps:
          - template: /src/security/sbom/steps/sbom.steps.yaml@templates
            parameters:
              sbomOutputDir: '$(Agent.TempDirectory)/sbom'
              lockDepsArtifactDir: '$(Agent.TempDirectory)/lock-deps'
              outputFormat: 'cyclonedx-json'
              vulnFolder: '$(Agent.TempDirectory)/vuln'
              analysisOutputFormat: 'cyclonedx-json'
              downloadArtifact: false
              publishGenerationArtifact: true
              sbomArtifactName: 'sbom-files'
              syftInstallDir: '$(Agent.TempDirectory)'
              grypeInstallDir: '$(Agent.TempDirectory)'
```

---

## Conclusion

These templates provide a flexible and modular way to integrate SBOM generation and vulnerability analysis into the Azure DevOps pipelines. You can use the individual templates for separate SBOM generation or analysis steps, or opt for the composite approach using `sbom.steps.yaml` for an end-to-end process. Most users are expected to use the composite template to simplify the workflow, while advanced users may choose to run the stages independently.

Feel free to adjust the parameters and customize the scripts to suit the project needs.

