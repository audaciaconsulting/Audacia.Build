# Azure DevOps SBOM & Vulnerability Analysis Pipeline Templates

This directory provides a set of reusable YAML templates that integrate SBOM (Software Bill of Materials) generation and vulnerability analysis into Azure DevOps pipelines. The templates enable:

1. **SBOM Generation:** Generating SBOMs for projects by collecting Dependency Lock files (for example, specific `*.deps.json` files from .NET projects and `package-lock.json` files from NPM projects) and running [Syft](https://github.com/anchore/syft).
2. **SBOM Analysis:** Analyzing SBOMs to produce vulnerability reports using [Grype](https://github.com/anchore/grype).
3. **Composite Execution:** Running a composite pipeline that performs both SBOM generation and analysis in one step, providing an end-to-end solution.

This document describes each template and explains how they may be used individually as well as in a composite approach.

---

## Templates Overview

### 1. `net-core.steps.yaml`

This template is designed for building .NET Core projects. It performs the following actions:

- **Restore, Build, Test, and Publish:** Executes the standard .NET Core commands.
- **Optional Dependency Lock Files Collection:** When enabled (via the `publishLockDepsArtifact` parameter), the template recursively searches the source directory for `.deps.json` files using a configurable list of file patterns and copies them into a designated folder.  
  **Note:** The default pattern (`lockDepsToInclude`) only handles the .NET-specific dependency files.
- **Artifact Publishing:** Publishes the collected Dependency Lock files as a pipeline artifact using a job‑unique artifact name (for example, `$(Agent.JobName)-dependency-lock`). These artifacts will later be aggregated with other Dependency Lock artifacts.

**Key Parameters:**

- **projects:** Glob pattern for project files (default: `**/*.csproj`).
- **runTests:** Boolean flag to run tests.
- **configuration:** Build configuration (for example, `Release` or `Debug`).
- **publishLockDepsArtifact:** Set to `true` to enable collection and publishing of Dependency Lock files (only `*.deps.json` files are collected).
- **lockDepsOutputDir:** Directory where deps files are collected (default: `$(Agent.TempDirectory)/dependency-lock`).
- **lockDepsToInclude:** A comma‑separated list of file patterns to specify which Dependency Lock files to collect. The default values are:
  - `*.Api.deps.json`
  - `*.Identity.deps.json`
  - `*.Tests.deps.json`

When enabled, the PowerShell script in this template uses the provided patterns to filter the files that are recursively found and copies them into a flat folder for publishing.

**Usage:**  
Include this template in the .NET build jobs. When `publishLockDepsArtifact` is enabled, each job collects its `.deps.json` files and publishes them using a job‑unique artifact name. The NPM package lock file is no longer processed by this template.

---

### 2. `sbom-generation.yaml`

This template generates SBOM files from the published Dependency Lock artifact. It:

- **Downloads** the aggregated Dependency Lock artifact.
- **Installs Syft:** Installs the SBOM generator into a specified directory.
- **Generates SBOMs:** Iterates through each Dependency Lock file and generates an SBOM using the chosen output format (default: `cyclonedx-json`). For example, a file named `package-lock.json` (published separately by the NPM job) is converted to an SBOM named `npm-sbom.json`, and files matching `*.deps.json` are processed by removing the `.deps` segment and appending `-sbom.json`.
- **Publishes** the generated SBOMs as a pipeline artifact (default artifact name: `sbom-files`).

**Key Parameters:**

- **sbomOutputDir:** Local directory where SBOM files are stored (default: `$(Agent.TempDirectory)/sbom`).
- **dependencyLockArtifactDirectory:** Directory containing the downloaded Dependency Lock files (if not provided, defaults to the download path).
- **outputFormat:** SBOM format (for example, `cyclonedx-json`).
- **syftInstallDir:** Directory where Syft is installed.

**Usage:**  
Call this template in a stage dedicated to SBOM generation. It assumes that an aggregated lock‑deps artifact named `dependency-lock-files` is available (which includes both .NET deps files and the NPM package lock file).

---

### 3. `sbom-analysis.yaml`

This template analyzes SBOM files to produce vulnerability reports. It:

- **Optionally Downloads** the SBOM artifact if required.
- **Installs Grype** (the vulnerability scanner) into a specified directory.
- **Analyzes SBOM Files:** Iterates over SBOM files (matched by a glob pattern, default: `sbom-*.json`), runs Grype, and generates corresponding vulnerability reports. For instance, an SBOM named `npm-sbom.json` produces a report named `npm-vuln-report.json`, while other SBOMs have their `-sbom` suffix replaced with `-vuln-report`.
- **Publishes** the generated vulnerability reports as a pipeline artifact (default: `vuln-files`).

**Key Parameters:**

- **sbomDir:** Directory where SBOM files are stored (default: `$(Agent.TempDirectory)/sbom`).
- **analysisOutputFormat:** Format for the vulnerability report (default: `cyclonedx-json`).
- **vulnFolder:** Directory to store vulnerability reports.
- **downloadArtifact:** Set to `true` to download the SBOM artifact before analysis.
- **grypeInstallDir:** Directory where Grype is installed.

**Usage:**  
Include this template in a stage dedicated to SBOM analysis. It consumes the SBOM artifact and produces vulnerability reports.

---

### 4. `sbom.steps.yaml` (Composite Template)

The composite template provides an end-to-end solution that:

1. **Downloads** the aggregated Dependency Lock artifact (if a custom path is not provided).
2. **Generates SBOMs:** Invokes `sbom-generation.yaml` to produce SBOM files from the aggregated Dependency Lock files.
3. **Analyzes SBOMs:** Immediately follows with a call to `sbom-analysis.yaml` to produce vulnerability reports.

**Key Parameters:**

- Inherits parameters from the individual generation and analysis templates (such as `sbomOutputDir`, `outputFormat`, `vulnFolder`, etc.).
- **dependencyLockArtifactDirectory:** If not provided, the template downloads the aggregated Dependency Lock artifact (published from the build stage) into a default location.
- **downloadArtifact:** When set to `true`, causes the SBOM artifact to be downloaded before analysis.

**Usage:**  
The composite template is designed for scenarios where SBOM generation and analysis are to be executed in sequence as a single, integrated process.

---

## How to Use These Templates in an Azure DevOps Pipeline

### A. SBOM Generation in Isolation

A stage using `sbom-generation.yaml` might be configured as follows:

```yaml
- stage: SBOM_Generation
  displayName: 'Generate SBOM Only'
  jobs:
    - job: GenerateSBOMOnly
      displayName: 'Generate SBOM from Lock Files'
      steps:
        - task: DownloadPipelineArtifact@2
          displayName: 'Download Dependency Lock Artifact'
          inputs:
            buildType: 'current'
            artifact: 'dependency-lock-files'
            path: '$(Agent.TempDirectory)/dependency-lock'
        - template: /src/security/sbom/steps/sbom-generation.yaml@templates
          parameters:
            sbomOutputDir: '$(Agent.TempDirectory)/sbom'
            dependencyLockArtifactDirectory: '$(Agent.TempDirectory)/dependency-lock'
            outputFormat: 'cyclonedx-json'
            publishArtifact: true
            artifactName: 'sbom-files'
            syftInstallDir: '$(Agent.TempDirectory)'
```

This stage downloads the Dependency Lock files, installs Syft, generates SBOMs, and publishes the resulting artifact.

---

### B. SBOM Analysis in Isolation

A stage using `sbom-analysis.yaml` might be configured as follows:

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

This stage downloads the SBOM artifact (if necessary), installs Grype, runs the analysis, and publishes the vulnerability report artifact.

---

### C. Composite SBOM Generation & Analysis

The composite template (`sbom.steps.yaml`) can be used to perform SBOM generation and analysis together. An example configuration is as follows:

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
            dependencyLockArtifactDirectory: '$(Agent.TempDirectory)/dependency-lock'  # Or leave empty to download the aggregated artifact.
            outputFormat: 'cyclonedx-json'
            vulnFolder: '$(Agent.TempDirectory)/vuln'
            analysisOutputFormat: 'cyclonedx-json'
            downloadArtifact: false  # Set to true if the SBOM artifact must be downloaded.
            publishGenerationArtifact: true
            sbomArtifactName: 'sbom-files'
            syftInstallDir: '$(Agent.TempDirectory)'
            grypeInstallDir: '$(Agent.TempDirectory)'
```

In composite mode, the template downloads (or uses) the aggregated Dependency Lock artifact, generates the SBOM files, and then analyzes them with Grype to produce vulnerability reports.

---

## Aggregating Dependency Lock Files

Multiple build jobs using `net-core.steps.yaml` may publish separate Dependency Lock artifacts. An aggregation job is used to combine these into a single artifact named **`dependency-lock-files`**. For example, an aggregation job in the build stage:

- **Downloads** all per‑job Dependency Lock artifacts.
- **Aggregates** the files using a PowerShell script that copies files from each artifact into a single folder while deduplicating based on filename.
- **Publishes** the aggregated folder as `dependency-lock-files`.

This aggregated artifact is consumed by the SBOM generation and composite templates.

---

## Example Pipeline Structure

An example pipeline (`dev.pipeline-sbom.yaml`) demonstrates the integration of the build stage (with aggregation) and the composite SBOM stage.

### Pipeline File: `dev.pipeline-sbom.yaml`

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

### Build Stage Snippet: `build-sbom.stage.yaml`

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
              lockDepsArtifactName: 'dependency-lock-files'
              lockDepsOutputDir: '$(Agent.TempDirectory)/dependency-lock'
      - job: BuildIdentity
        displayName: 'Build Identity Server'
        steps:
          - template: /src/build/dotnet/steps/net-core.steps.yaml@templates
            parameters:
              projects: '$(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Identity/ParkBlue.SaferRecruitment.Identity.csproj'
              runTests: false
              publishLockDepsArtifact: true
              lockDepsArtifactName: 'dependency-lock-files'
              lockDepsOutputDir: '$(Agent.TempDirectory)/dependency-lock'
      - job: BuildTestDataSeeding
        displayName: 'Build Test Data Seeding App'
        steps:
          - template: /src/build/dotnet/steps/net-core.steps.yaml@templates
            parameters:
              projects: '$(System.DefaultWorkingDirectory)/src/apis/src/ParkBlue.SaferRecruitment.Seeding/ParkBlue.SaferRecruitment.Seeding.csproj'
              runTests: false
              publishLockDepsArtifact: true
              lockDepsArtifactName: 'dependency-lock-files'
              lockDepsOutputDir: '$(Agent.TempDirectory)/dependency-lock'
      - job: BuildNpm
        displayName: 'Build Web Apps'
        steps:
          - task: npmAuthenticate@0
            displayName: 'NPM Authenticate'
            inputs:
              workingFile: '$(Build.SourcesDirectory)/src/apps/park-blue/.npmrc'
          - task: Npm@1
            displayName: 'NPM Install'
            inputs:
              command: 'custom'
              customCommand: 'install --force'
              workingDir: 'src/apps/park-blue'
          - task: Npm@1
            displayName: 'NPM Build'
            inputs:
              command: custom
              workingDir: '$(Build.SourcesDirectory)/src/apps/park-blue'
              customCommand: 'run build'
          # New task: Publish package-lock.json for aggregation.
          - task: PublishBuildArtifacts@1
            displayName: 'Publish package-lock.json'
            inputs:
              PathtoPublish: '$(Build.SourcesDirectory)/src/apps/park-blue/package-lock.json'
              ArtifactName: 'npm-dependency-lock'
          - task: Npm@1
            displayName: 'NPM Test'
            inputs:
              command: 'custom'
              customCommand: 'run test-ci'
              workingDir: 'src/apps/park-blue'
          - task: PublishBuildArtifacts@1
            displayName: 'Publish Web App Artifact'
            inputs:
              PathtoPublish: '$(Build.SourcesDirectory)/src/apps/park-blue/dist/'
              ArtifactName: '$(Build.DefinitionName)'
      - job: AggregateLockDeps
        displayName: 'Aggregate Dependency Lock Files'
        dependsOn:
          - BuildDotNet
          - BuildIdentity
          - BuildTestDataSeeding
          - BuildNpm
        pool:
          vmImage: windows-latest
        steps:
          - download: current
            displayName: 'Download all pipeline artifacts'
          - task: PowerShell@2
            displayName: 'Aggregate Dependency Lock Files into Single Folder'
            inputs:
              targetType: 'inline'
              script: |
                $aggregateDir = "$(Agent.TempDirectory)/dependency-lock-aggregated"
                if (-Not (Test-Path $aggregateDir)) {
                    New-Item -ItemType Directory -Path $aggregateDir | Out-Null
                }
                $artifactDirs = Get-ChildItem -Path "$(Pipeline.Workspace)" -Directory | Where-Object { $_.Name -like "*-dependency-lock" }
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
            displayName: 'Publish Aggregated Dependency Lock Artifact'
            inputs:
              targetPath: '$(Agent.TempDirectory)/dependency-lock-aggregated'
              artifact: 'dependency-lock-files'
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
              dependencyLockArtifactDirectory: '$(Agent.TempDirectory)/dependency-lock'
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

The provided templates offer a flexible and modular approach to integrate SBOM generation and vulnerability analysis into Azure DevOps pipelines. There are three primary usage options:

1. **SBOM Generation in Isolation:**  
   Invoke `sbom-generation.yaml` to produce SBOMs from aggregated Dependency Lock files.

2. **SBOM Analysis in Isolation:**  
   Use `sbom-analysis.yaml` to analyze SBOMs and generate vulnerability reports.

3. **Composite Approach:**  
   Employ `sbom.steps.yaml` to execute SBOM generation and analysis in a single composite process for a streamlined workflow.
