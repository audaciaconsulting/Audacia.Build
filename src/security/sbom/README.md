# **## DEPRECATED ##**
# Azure DevOps SBOM & Vulnerability Analysis Pipeline Templates

This directory provides a set of reusable YAML templates that integrate SBOM (Software Bill of Materials) generation and vulnerability analysis into Azure DevOps pipelines. The templates enable:

1. **SBOM Generation:** Generating SBOMs for projects by collecting Dependency Lock files (for example, specific `*.deps.json` files from .NET projects and `package-lock.json` files from NPM projects) and running the **CycloneDX npm CLI for NPM projects** and **Syft for .NET `*.deps.json`** (Syft also remains available as a fallback for NPM if the CLI is unavailable, however, Syft does not currently support dependency graphs for NPM lockfiles).
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
- **Artifact Publishing:** Publishes the collected Dependency Lock files as a pipeline artifact using a job-unique artifact name (for example, `$(Agent.JobName)-dependency-lock`). These artifacts will later be aggregated with other Dependency Lock artifacts.

**Key Parameters:**

- **projects:** Glob pattern for project files (default: `**/*.csproj`).
- **runTests:** Boolean flag to run tests.
- **configuration:** Build configuration (for example, `Release` or `Debug`).
- **publishLockDepsArtifact:** Set to `true` to enable collection and publishing of Dependency Lock files (only `*.deps.json` files are collected).
- **lockDepsOutputDir:** Directory where deps files are collected (default: `$(Agent.TempDirectory)/dependency-lock`).
- **lockDepsToInclude:** A comma-separated list of file patterns to specify which Dependency Lock files to collect. The default values are:
  - `*.Api.deps.json`
  - `*.Identity.deps.json`
  - `*.Tests.deps.json`

When enabled, the PowerShell script in this template uses the provided patterns to filter the files that are recursively found and copies them into a flat folder for publishing.

**Usage:**  
Include this template in the .NET build jobs. When `publishLockDepsArtifact` is enabled, each job collects its `.deps.json` files and publishes them using a job-unique artifact name. The NPM package lock file is no longer processed by this template.

---

### 2. `sbom-generation.yaml`

This template generates SBOM files from the published Dependency Lock artifact. It:

- **Downloads** the aggregated Dependency Lock artifact (now expected under the artifact name **`lock-deps-files`**).
- **Installs Syft:** Installs Syft for `.NET` processing and as a fallback for NPM if needed.
- **Generates SBOMs:**
  - **NPM:** Prefers the **CycloneDX npm CLI** (`npx @cyclonedx/cyclonedx-npm`) to generate CycloneDX SBOMs from `package-lock.json` + `package.json` pairs. Output is created per NPM project (organised by relative path) and includes a proper **dependency graph**. If Node/npm/npx is not available, generation falls back to Syft.
  - **.NET:** Uses Syft to generate SBOMs from discovered `*.deps.json` files.
- **Publishes** the generated SBOMs as a pipeline artifact (default artifact name: `sbom-files`).

**Key Parameters:**

- **sbomOutputDir:** Local directory where SBOM files are stored (default: `$(Agent.TempDirectory)/sbom`).
- **dependencyLockArtifactDirectory:** Directory containing the downloaded Dependency Lock files (default expectation is `$(Agent.TempDirectory)/lock-deps` if not explicitly provided).
- **outputFormat:** SBOM format (for example, `cyclonedx-json`).
- **syftInstallDir:** Directory where Syft is installed.
- **syftConfigFile:** *(Optional)* Path to a Syft configuration file used for SBOM generation.

**Why NPM SBOMs now use the CycloneDX npm CLI**  
The pipeline has switched from using Syft to **`@cyclonedx/cyclonedx-npm`** for NPM SBOM generation because Syft currently does **not** reliably emit a CycloneDX **dependency graph** for NPM lockfiles. Without a dependency graph, it is not possible to determine whether packages are **direct** or **transitive** dependencies. The limitation is tracked in Anchore Syft **issue #2305**, while CycloneDX explicitly supports dependency graphs through the `dependencies` model.

**Usage:**  
Call this template in a stage dedicated to SBOM generation. It assumes that an aggregated artifact named **`lock-deps-files`** is available (which includes both `.NET` `*.deps.json` files and NPM `package-lock.json`/`package.json` pairs).

---

### 3. `sbom-analysis.yaml`

This template analyzes SBOM files to produce vulnerability reports. It:

- **Optionally Downloads** the SBOM artifact if required.
- **Installs Grype** (the vulnerability scanner) into a specified directory.
- **Analyzes SBOM Files:** Iterates over SBOM files (matched by a glob pattern, default: `*-sbom.json`), runs Grype, and generates corresponding vulnerability reports. For instance, an SBOM named `npm-sbom.json` produces a report named `npm-vuln-report.json`, while other SBOMs have their `-sbom` suffix replaced with `-vuln-report`.
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
- **syftConfigFile:** *(Optional)* Path to a Syft configuration file used for SBOM generation.

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
            artifact: 'lock-deps-files'                 # Updated artifact name
            path: '$(Agent.TempDirectory)/lock-deps'    # Updated default path
        - template: /src/security/sbom/steps/sbom-generation.yaml@templates
          parameters:
            sbomOutputDir: '$(Agent.TempDirectory)/sbom'
            dependencyLockArtifactDirectory: '$(Agent.TempDirectory)/lock-deps'
            outputFormat: 'cyclonedx-json'
            publishArtifact: true
            artifactName: 'sbom-files'
            syftInstallDir: '$(Agent.TempDirectory)'
````

This stage downloads the Dependency Lock files, installs Syft (for .NET and fallback), generates SBOMs using **CycloneDX npm CLI for NPM** and **Syft for .NET**, and publishes the resulting artifact.

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
            sbomGlob: '*-sbom.json'
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
            dependencyLockArtifactDirectory: '$(Agent.TempDirectory)/lock-deps'  # Updated default path
            outputFormat: 'cyclonedx-json'
            vulnFolder: '$(Agent.TempDirectory)/vuln'
            analysisOutputFormat: 'cyclonedx-json'
            downloadArtifact: false  # Set to true if the SBOM artifact must be downloaded.
            publishGenerationArtifact: true
            sbomArtifactName: 'sbom-files'
            syftInstallDir: '$(Agent.TempDirectory)'
            grypeInstallDir: '$(Agent.TempDirectory)'
```

In composite mode, the template downloads (or uses) the aggregated Dependency Lock artifact, generates the SBOM files (NPM via CycloneDX npm CLI, .NET via Syft), and then analyzes them with Grype to produce vulnerability reports.

---

## Aggregating Dependency Lock Files

Multiple build jobs may publish separate Dependency Lock artifacts. An aggregation job is used to combine these into a single artifact named **`lock-deps-files`**. For example, an aggregation job in the build stage:

* **Downloads** all per-job Dependency Lock artifacts.
* **Aggregates** the files (including `.NET` `*.deps.json` and NPM `package-lock.json` plus their `package.json`) into a single folder structure while deduplicating as appropriate.
  The SBOM generation step then discovers each NPM app directory and emits a per-app SBOM with a dependency graph (via CycloneDX npm CLI).
* **Publishes** the aggregated folder as `lock-deps-files`.

This aggregated artifact is consumed by the SBOM generation and composite templates.

---

## Conclusion

The provided templates offer a flexible and modular approach to integrate SBOM generation and vulnerability analysis into Azure DevOps pipelines. There are three primary usage options:

1. **SBOM Generation in Isolation:**
   Invoke `sbom-generation.yaml` to produce SBOMs from aggregated Dependency Lock files (NPM via CycloneDX npm CLI; .NET via Syft).

2. **SBOM Analysis in Isolation:**
   Use `sbom-analysis.yaml` to analyze SBOMs and generate vulnerability reports.

3. **Composite Approach:**
   Employ `sbom.steps.yaml` to execute SBOM generation and analysis in a single composite process for a streamlined workflow.

> **Note on dependency graphs for NPM:** Syft currently does not reliably populate the CycloneDX dependency graph for NPM lockfiles, which prevents distinguishing direct vs transitive dependencies; see Anchore Syft issue **#2305**. The CycloneDX npm CLI is used for NPM to ensure dependency graph coverage aligned with the CycloneDX model.

