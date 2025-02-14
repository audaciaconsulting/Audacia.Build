# OWASP ZAP Scan Pipelines

This repository contains documentation and templates for two distinct approaches to running OWASP ZAP scans as part of our CI/CD pipelines:

1. **ZAP Automation Scan**  
   A new approach based on the [ZAP Automation Framework](https://www.zaproxy.org/docs/automate/automation-framework/). This method centralizes configuration in a single YAML file and provides a flexible, dynamic, and future-proof solution for automated security testing.

2. **ZAP Packaged Scan**  
   The current legacy method that uses multiple YAML templates to orchestrate the scan (initialize, scan, and finalize steps). While this approach has served us well, it is more complex, less flexible, and is planned to be replaced in time by the Automation Framework ([ref](https://www.zaproxy.org/docs/automate/automation-framework/)).

---

## Overview

### ZAP Automation Scan

- **Centralized Configuration**:  
  All scanning definitions, including contexts, authentication, and reporting, are defined in a single `zap-automation.yaml` file.

- **Dynamic & Flexible**:  
  The configuration can be generated dynamically in the pipeline and can also be loaded directly into the ZAP GUI for manual execution. This dual usability allows for consistent scans across both automated and interactive scenarios.

- **Streamlined Process**:  
  Integration with Docker and native Azure DevOps tasks simplifies setup, reporting, and artifact management.

- **Future-Proof**:  
  Aligns with the evolving OWASP ZAP ecosystem and is designed to incorporate future features and improvements with minimal changes to our pipeline.

### ZAP Packaged Scan

- **Legacy Approach**:  
  Uses multiple YAML templates (initialize, scan, and finalize) to run ZAP scans.
- **Increased Complexity**:  
  Configuration and reporting are handled through several separate scripts and transformations, which can be more challenging to maintain.
- **Deprecation Plan**:  
  This approach will eventually be phased out in favor of the more modern automation scan approach.

---

## Recommendation

We **recommend using the ZAP Automation Scan approach** for all new projects and when updating existing pipelines. Benefits include:

- **Simplified Configuration**: Centralizing all parameters into a single YAML file reduces complexity.
- **Enhanced Flexibility**: The automation configuration can be used in CI/CD pipelines or directly within the ZAP GUI.
- **Consistent and Repeatable Scanning**: Automated configuration generation ensures that scan definitions remain consistent across environments.
- **Alignment with Future Standards**: As the OWASP ZAP community evolves the Automation Framework, this approach will allow us to take advantage of new features with minimal disruption.

While the Packaged Scan approach is still available for legacy support, its eventual deprecation means it is best used only for existing projects until a migration can be planned.

---

## Documentation

For more details on each approach, please refer to the following documentation files:

- **[ZAP Automation Scan Documentation](zap-automation-scan.md)**  
  Covers the new automated scanning approach using the ZAP Automation Framework.

- **[ZAP Packaged Scan Documentation](zap-packaged-scan.md)**  
  Describes the legacy packaged scan method currently in use.

---

## Migration Guidance

If you are currently using the ZAP Packaged Scan approach, we encourage you to migrate to the Automation Scan method as soon as practical. Transitioning will help ensure that your security scanning remains robust, maintainable, and in line with future OWASP ZAP improvements.

---

By adopting the Automation Scan approach, we aim to simplify our security testing, reduce manual overhead, and provide a more adaptable and future-proof scanning solution.
