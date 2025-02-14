# ZAP Automation Scan Template

## Why This Template Was Created

1. **Adoption of the ZAP Automation Framework**  
   Our previous method of configuring OWASP ZAP scans—using a mix of command line scripts and manual configuration—served us well. However, by moving to [ZAP's Automation Framework](https://www.zaproxy.org/docs/automate/automation-framework/), we can now define all scan parameters in a single, declarative YAML file. This change provides:
    - A centralized configuration that is easier to maintain and update.
    - An approach that simplifies how scan definitions, contexts, and reporting are managed.

2. **Streamlined and Consistent Security Testing**  
   Integrating the Automation Framework into our CI/CD pipelines offers a more streamlined process:
    - Automated generation of the `zap-automation.yaml` file reduces manual overhead and ensures consistency across different projects.
    - Enhanced repeatability in scans, with all required parameters and reporting options defined in one place, allowing for reliable and predictable security testing.

3. **Improved Integration with DevOps Workflows**  
   The new template leverages native Azure DevOps tasks to integrate seamlessly with our existing workflows:
    - Scan results are automatically converted into formats (such as NUnit test results) that are easily incorporated into our build and test reports.
    - The process includes automatic handling of working directories and artifacts, simplifying post-scan cleanup and traceability.

4. **Future-Proofing Our Security Processes**  
   Moving to the Automation Framework aligns our security practices with evolving standards:
    - The framework’s design supports ongoing enhancements and new features from the OWASP ZAP community.
    - This approach provides flexibility, making it easier to incorporate new scanning capabilities and reporting options as they become available, all while keeping our pipeline configurations clear and manageable.

## Input Parameters

The new automated scan pipeline accepts several input parameters that control its behavior. Below is a description of each parameter along with example values:

- **name** (string)  
  A unique identifier for the scan. This value is used to name directories, log files, and artifacts.  
  _Example_: `API Scan` or `QuickScan_Test`

- **targetUrl** (string)  
  The URL of the target application or API to scan. For API scans, this typically points to the swagger/OpenAPI definition.  
  _Example_: `https://customer-api.example.com/swagger/v1/swagger.json`

- **scanType** (string)  
  Specifies the type of scan to perform. Allowed values are `"quick-scan"` or `"API"`.  
  _Example_: Use `"quick-scan"` for general web scanning or `"API"` for API endpoint testing.

- **maxScanTime** (number)  
  The maximum duration for the scan, specified in minutes. This sets an upper limit on how long the scan will run.  
  _Example_: `15` for a quick scan or `60` for a more thorough assessment.

- **authorizationHeaderValue** (string)  
  For API scans, this parameter is used to set a global HTTP header for authorization. If left empty, the pipeline can default to using a JWT access token obtained during authentication.  
  _Example_: `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI...`

- **createBugsForFailures** (boolean)  
  Indicates whether the pipeline should automatically create bug work items for any failures or alerts detected during the scan.  
  _Example_: `false` or `true` if integration with your work item tracking system is desired.

- **parentCardId** (string)  
  When bug creation is enabled, this optional parameter can specify a parent card or work item ID under which the bugs should be grouped.  
  _Example_: `12345`

- **organisationUri** (string)  
  The URI of the Azure DevOps organization. Defaults to `$(System.TeamFoundationCollectionUri)`.  
  _Example_: `https://dev.azure.com/yourorg/`

- **projectName** (string)  
  The name of the Azure DevOps project. Defaults to `$(System.TeamProject)`.  
  _Example_: `MySecurityProject`

- **deleteGlobalAlerts** (boolean)  
  Controls whether to delete all existing global alerts before applying the custom alert filters.  
  _Example_: `false` (default) or `true` if a clean slate is preferred.

- **alertFilters** (object array)  
  A collection of custom alert filters that modify the risk level or behavior of specific alerts in the scan. Each alert filter should be defined with the following properties:
    - **ruleId** (integer, mandatory): The scan rule ID or alert reference.
    - **newRisk** (string, mandatory): The new risk level to assign to matching alerts. Allowed values include `'False Positive'`, `'Info'`, `'Low'`, `'Medium'`, or `'High'`.
    - **context** (string, optional): The context name. If left empty, the filter applies globally.
    - **url** (string, optional): A string pattern to match against the alert’s URL.
    - **urlRegex** (boolean, optional): If `true`, the URL pattern is treated as a regular expression.
    - **parameter** (string, optional): A string pattern to match against the alert's parameter field.
    - **parameterRegex** (boolean, optional): If `true`, the parameter pattern is treated as a regular expression.
    - **attack** (string, optional): A string pattern to match against the alert’s attack field.
    - **attackRegex** (boolean, optional): If `true`, the attack pattern is treated as a regular expression.
    - **evidence** (string, optional): A string pattern to match against the alert’s evidence field.
    - **evidenceRegex** (boolean, optional): If `true`, the evidence pattern is treated as a regular expression.
  
  _Example_:
  ```yaml
  alertFilters:
    - ruleId: 10054
      newRisk: 'Info'
      context: ''
      url: ''
      urlRegex: false
      parameter: ''
      parameterRegex: false
      attack: ''
      attackRegex: false
      evidence: ''
      evidenceRegex: false
  ```

## What Is a Passive Scan vs. an Active Scan?

- **Passive Scan**  
  With passive scanning, ZAP inspects traffic from normal site exploration (like spidering) without sending additional potentially harmful requests. It notes insecure headers or known patterns that indicate problems. This is safer but might not catch deeper security flaws.

- **Active Scan**  
  An active scan goes further by actively probing the target application with a variety of potentially malicious or unexpected inputs. This approach can uncover SQL injections, cross-site scripting, and other vulnerabilities that a passive scan alone cannot detect. However, it is more intrusive and can affect performance or stability.

## How the Pipeline Works

1. **Initialization**
    - The template checks if there is a working temporary directory established by an earlier “initialize” step.
    - Ensures all prerequisites are in place (e.g., environment variables, directory paths).

2. **Working Directory Creation**
    - A dedicated folder is created for each scan in the pipeline’s temporary workspace.
    - Results (logs, reports, config files) are stored here.

3. **Dynamic Generation of the ZAP Configuration**
    - The pipeline builds `zap-automation.yaml`, which instructs ZAP how to perform both **passive** and **active** scans, as well as how to generate **XML** and **HTML** reports.
    - This includes context definitions, the site’s base URL, optional authentication details, spider rules, active scanning parameters, reporting instructions, and—newly—custom alert filters.
    - **Alert Filters:**  
      Custom alert filters can be appended to the configuration to modify the risk levels of specific alerts. For example, an alert filter can lower the risk of a known false positive or adjust how an alert is reported.
    - **Significance:** The generated ZAP Automation Config is structured to be both human-readable and machine-consumable. It can be generated dynamically during the CI/CD pipeline run or used directly within the ZAP GUI for manual execution. This flexibility ensures that the same configuration file can serve multiple purposes—enabling consistent scans whether run as part of automated pipelines or interactively in the ZAP desktop environment.

4. **Publishing & Logging of the Config File**
    - The `zap-automation.yaml` file is stored as a build artifact, so it can be reviewed later to understand exactly how the scan was configured.
    - It is also written to the pipeline logs to simplify debugging or troubleshooting.

5. **Executing ZAP in Docker**
    - A ZAP Docker container is run with the working directory mounted.
    - ZAP reads the dynamically generated `zap-automation.yaml` and executes:
        1. Spider & AJAX spider (while passive scanning).
        2. **Passive scan wait** to finish evaluating requests.
        3. **Active scan** to aggressively test for deeper vulnerabilities.
        4. **Report jobs**: one for `traditional-xml-plus` and one for `traditional-html-plus`.

6. **Renaming Reports**
    - The automation framework outputs “ZAP-Report*.xml” and “ZAP-Report*.html” files. These are renamed or copied to `Report.xml` and `Report.html` for consistency.

7. **Transform XML to NUnit**
    - The XML report is converted into NUnit format so that any issues appear as test results in Azure DevOps.
    - This aligns with typical CI/CD patterns where test failures are a familiar mechanism for flagging problems.

8. **Publishing Artifacts & Test Results**
    - Both the XML and HTML final reports are published as build artifacts.
    - The NUnit-transformed results are published as test results, making security alerts visible as “failures” in the pipeline’s test summary.

9. **Alerts Flag**
    - The pipeline checks the XML report for any non-false-positive alerts.
    - If found, it sets a pipeline variable (`alertsExist`), enabling additional logic—such as automatically creating bugs or failing the build.

## Outputs Produced

1. **ZAP Automation Config (`zap-automation.yaml`)**
    - Contains all scanning definitions, from spider rules and active scanning policies to reporting instructions and custom alert filters.
    - **Importance:** The structured nature of this configuration file is central to the process. It not only ensures that all parameters are explicitly defined and documented but also allows the file to be executed directly within the ZAP GUI for manual runs. This dual usability supports both automated and interactive security assessments.

2. **XML & HTML Reports**
    - `Report.xml`: machine-readable data for deeper analysis or CI/CD ingestion.
    - `Report.html`: human-friendly summary of all vulnerabilities discovered.

3. **NUnit Test Results (`NUnit-Report.xml`)**
    - Security findings are transformed into “test cases,” letting teams track issues via pipeline test tabs.

4. **Logs & Artifacts**
    - Docker logs, transformation logs, and the final pipeline artifacts.
    - Ensures traceability for each run.

## Example Pipeline YAML

```yaml
name: $(Date:yyyyMMdd)
trigger: none
pr: none
schedules:
  - cron: "0 00 * * 6"  # Weekly scan
    displayName: Weekly OWASP API Vulnerability Check Customer
    branches:
      include:
        - main
resources:
  repositories:
    - repository: templates
      type: github
      endpoint: shared-github
      name: audaciaconsulting/Audacia.Build

variables:
  - group: Example.Tests

jobs:
  - job: OWASP_Security_Tests
    displayName: Run OWASP API Security Tests Customer Portal
    pool:
      vmImage: ubuntu-latest
    workspace:
      clean: all
    steps:
      # Initialize (must run before any scan)
      - template: src/security/owasp-zap/tasks/initialize.yaml@templates
      
      # Authenticate via JWT bearer (sets the access_token variable)
      - template: src/security/auth/tasks/authenticate-jwtbearer.yaml@templates
        parameters:
          tokenIssuerUrl: 'https://login.example.audacia.systems/connect/token'
          clientScope: 'api'
          clientId: $(CLIENT_ID)
          clientSecret: $(CLIENT_SECRET)
          username: $(CUSTOMER_USERNAME)
          password: $(CUSTOMER_PASSWORD)
      
      # Run the new OWASP ZAP Automation scan template with an alert filter.
      - template: src/security/owasp-zap/tasks/zap-automation-scan.yaml@templates
        parameters:
          name: 'API Scan'
          targetUrl: 'https://customer-api.example.audacia.systems/swagger/v1/swagger.json'
          scanType: 'API'
          maxScanTime: 60
          authorizationHeaderValue: 'Bearer $(access_token)'
          createBugsForFailures: false
          deleteGlobalAlerts: false
          alertFilters:
            - ruleId: 10054
              newRisk: 'Info'
              context: ''
              url: ''
              urlRegex: false
              parameter: ''
              parameterRegex: false
              attack: ''
              attackRegex: false
              evidence: ''
              evidenceRegex: false
```

---

By combining passive scanning, an **active scan**, robust reporting, and now customizable **alert filters**, this template ensures thorough, automated security testing. Leveraging the [ZAP Automation Framework](https://www.zaproxy.org/docs/automate/automation-framework/) reduces manual overhead, keeps configurations consistent, and allows the security testing process to evolve over time without rewriting complicated scripts or reconfiguring the ZAP UI from scratch.
