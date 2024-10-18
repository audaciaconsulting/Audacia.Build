# OWASP ZAP Steps

## Contents

- [Reason](#reason) - Reason for pipeline tasks
- [Prerequisites](#prerequisites) - Requirements to use pipeline tasks
- [Scan Types](#scan-types) - The types of scan supported
- [Authentication](#authentication) - Authentication methods
- [Context Files](#context-files) - Description of ZAP Context files and how they can be used
- [Usage](#usage) - How to use the steps in a pipeline

## Reason

To automate OWASP ZAP scans on endpoints to allow for regular security scans and increased security.

Scan results will appear as failed tests against the build, and the HTML and XML reports of the scan are published as build artifacts.

It is important to note that automated OWASP scans are not intended as a replacement for scheduled, manual, security scans - but are instead intended to add an additional layer of security testing.

## Prerequisites

### Docker

To be able to use the main OWASP ZAP scan pipeline step (scan.yaml) you must use a vm image which supports docker. The recommended image to use is `ubuntu-latest`.

### Audacia.Build repository reference

Ensure the following lines are added to your build pipeline.yaml

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: Audacia/Audacia.Build
```

Example `.yaml` files for various configurations can be found in the `examples/security/owasp-zap` folder in the Audacia.Build repository.

For a broader understanding of yaml pipelines in azure read the following [documentation](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema%2Cparameter-schema#yaml-basics).

## Scan Types

Three types of OWASP ZAP scan are supported, these are:

- Baseline
  - Runs the ZAP spider against the specified target for (by default) 1 minute and then waits for the passive scanning to complete before reporting the results. This does not perform any active "attack".
- Full
  - Runs the ZAP spider against the specified target (by default with no time limit) followed by an optional ajax spider scan and then a full active scan before reporting the results. This is much more comprehensive - performing an actual attack (which can change data) and can take a lot more time to run.
- API
  - Tuned for performing scans against APIs defined by OpenAPI, SOAP, or GraphQL via either a local file or a URL. It imports the definition that you specify and then runs an Active Scan against the URLs found. The Active Scan is tuned to APIs, so it doesn’t bother looking for things like XSSs.

Multiple scans can be run as part of the same pipeline.

For more information about the OWASP zap2docker scan types please see the [ZAP Docker Documentation](https://www.zaproxy.org/docs/docker).

## Authentication

The Audacia.Build OWASP ZAP steps currently actively supports 3 authentication types. In order to support a particular authentication method, additional files (e.g. context files, scripts) and additional build steps may be required. The below authentication types are currently supported:

- Authorization Header Authentication
  - JWT token provisioning can be achieved using the `src/security/auth/tasks/authenticate-jwtbearer.yaml` step.
  - The header name can also be overridden to alow for headers not directly called "Authorization", for example the use of custom headers to specify a PAT (personal access token).
  - Client_credential and password grant types are supported.
  - See `examples/security/owasp-zap/header-authenticated-api-scan` in `Audacia.Build` for an example / template.
  - [Click here to view the relevant OWASP ZAP docs](https://www.zaproxy.org/docs/desktop/start/features/authentication/#envvars).
- Form-Based Authentication
  - Simple username/password form posting functionality and inspection a response for an indication of successful login.
  - Does not support CSRF tokens.
  - Requires a valid `.context` file.
  - See `examples/security/owasp-zap/form-authenticated-ui-scan` in `Audacia.Build` for an example / template.
  - [Click here to view the relevant OWASP ZAP docs](https://www.zaproxy.org/docs/desktop/start/features/authmethods/#formBased).
- Script Based Authentication
  - Requires a suitable authentication script file and a valid `.context` referencing it.
  - See below for a high level overview of one scripting option using [Zest scripts](#zest-scripts).
  - No examples are currently provided as script based authentication is fairly bespoke.
  - [Click here to view the relevant OWASP ZAP docs](https://www.zaproxy.org/docs/desktop/addons/zest/).

While any authentication that OWASP ZAP supports may work, more complex authentication methods will require further work by the implementer (for example, configuring and exporting context files and recording/compiling scripts from the OWASP ZAP GUI) in order to use them.

Due to the nature and complexity of `Azure AD SSO` and `Authorization Code with PKCE` - these are not currently supported.

If you have any questions about authentication, or intend to implement script based authentication or an authentication method that is not currently actively supported, please discuss this with Philip Rashleigh first.

### Zest Scripts

Zest is a scripting language developed by Mozilla's security team.

Zest scripts are recorded as macros, or manually compiled, from within the OWASP ZAP GUI and then exported. Scripts contain sets of HTTP requests and responses.

Zest scripts can be used to support different kinds of authentication mechanisms that are not natively supported by OWASP ZAP.

Parameters and tokens can be added (for example a parameter can be used in place of a hardcoded URL to allow for dynamic requests). In addition variables can be extracted from responses and used in future requests (for example - a CSRF token).

For more information on Zest please see [this blog post](https://augment1security.com/zest/introduction-to-graphical-zest-in-owasp-zap-proxy-part-2/).

## Context Files

ZAP uses `.context` files in order to configure different elements of a scan.

You can specify a context file location using the `zapContextLocation` parameter of the `scan.yaml` step.

`.context` files can either be configured manually be editing XML, or can be configured in, and exported from, the OWASP ZAP GUI.

**Note that the ZAP GUI will not encrypt secrets (e.g. passwords) and instead just base64 encodes them. For obvious reasons we must avoid storing hard coded secrets in source control**. There are some ways around this using placeholders, which are already in use in the example `.context` files provided. If you would like to use an exported ZAP context - you must **speak to Security about this first.**.

### Sections

Some brief highlights are given below - for further information please consult the XML comments in the `.context` examples in  `examples/security/owasp-zap` folder in the `Audacia.Build` repository and the [ZAP Context Documentation](https://www.zaproxy.org/docs/desktop/start/features/contexts).

| Name | Description |
| --- | --- |
| incregexes | Entries are used to specify URLs to explicitly target. You must include the main application/API url here if using a context file - in the format `<incregexes>https://example.com.*</incregexes>`. Multiple entries can be added to include multiple sites/subsets of sites in the same scan. Regular expressions can be used to help specify where to scan based on patterns. |
| exregexes  | The inverse of the above - entries can be added to specify excluding particular URLs (with regex patterns) from a scan. |
| tech\include  | Entries can be used to specify which technologies to include in the scan. |
| authentication\type | This section is used to configure the authentication for the application. `2` for forms based auth. `4` for script based. |
| alertfilters\filter | This section can be used to configure false positives. If an alert is configured here it will not show up as a failed test in AzureDevOps (instead showing under `Others`). See [https://www.zaproxy.org/docs/desktop/addons/alert-filters/alertfilterdialog](https://www.zaproxy.org/docs/desktop/addons/alert-filters/alertfilterdialog). |

## Usage

### initialize.yaml

#### Description

This must be run before any scan steps. It downloads down the latest zap2docker image, creates a temporary working folder and performs some other initialization steps.

### scan.yaml

#### Description

This is the main script that is used to facilitate an OWASP ZAP scan. There are various parameter configurations for different scan types. In order to facilitate an understanding it may be useful to refer to the examples before diffing in to the documentation.

Multiple scan.yaml steps can be run from within the same pipeline. Combining multiple scans in one pipeline is more optimal as the zap2docker image does not need to be downloaded again for each individual scan.

The first scan.yaml step in a pipeline must be preceded by an initialize.yaml step and the last scan.yaml in a pipeline must be followed by a finalize.yaml step.

#### Parameters

| Name                |            | Description |
|---                  |---         | ---         |
| name  | (required) | A name for the scan. This must be unique within the pipeline (multiple scan.yaml steps cannot have the same name) and should be descriptive as to what the scan is doing. |
| scanType  | (required) | `Baseline`, `Full` or `API` - using `API` requires the targetUrl be an open api endpoint, e.g. 'https://example.com/swagger/v1/swagger.json'. |
| targetUrl  | (required) | The target endpoint to scan. required to be open api document endpoint for `API` scan. |
| authorizationHeaderName | (optional) | Used to override the name of an authorization header (e.g. "MY-API-AUTH-KEY" instead of "Authorization") |
| authorizationHeaderValue | (optional) | The value of the authorization header if using header based authentication. See `authenticate-jwtbearer.yaml` for JWT token provisioning found [here](https://dev.azure.com/audacia/Audacia/_git/Audacia.Build?path=/src/security/auth/tasks/authenticate-jwtbearer.yaml&version=GBmaster&_a=contents). |
| zapContextLocation | (optional) | The ZAP context file to use for non-header based authentication, alert filters, and additional configuration. See below. |
| authenticationScriptType | (optional) | `Mozilla Zest`, `Oracle Nashorn` or  `Graal.js` - authentication script type for more complex authentication - must be paired with a Zap context configured for script authentication. |
| authenticationScriptLocation | (optional) | Transformed (see `transform-authentication-script.yaml` step) Zest Authentication script location for more complex authentication - must be paired with a Zap context configured for script authentication  and a specified `authenticationScriptType`. |
| username | (optional) | The username for the automation user, required is authenticating using a context file. |
| password | (optional) | The password for the automation user, required is authenticating using a context file. |
| useAjaxSpider    | (optional) | Defaults `false`. Use Ajax Spider test URLs found on webpages that have been scanned - `Baseline` and `Full` scan types only. |
| maxPassiveScanTime | (optional) | Max time in minutes to wait for ZAP to start and the passive scan to run (minutes). |
| maxSpiderCrawlTime | (optional) | The number of minutes to spider for (minutes) - `Baseline` and `Full` scan types only. |

#### With Context Files

If you are using a `.context` file, you must ensure there is an `incregexes` entry in the context file referencing the mail application/API url, e.g.: `<incregexes>https://example.com.*</incregexes>` or `<incregexes>https://api.example.com.*</incregexes>`. Please see [context files](#context-files) for more information.

#### Output**

This step will emit scan results as failed tests and publish scan HTML and XML reports as build artifacts.

#### Example**

See examples under `examples/security/owasp-zap` in the `Audacia.Build` repository. `examples/security/owasp-zap/unauthenticated-baseline-multi-scan` gives an example of performing multiple scans within the same pipeline.

### finalize.yaml

#### Description

This must be run before after the scan steps. It deliberately fails the pipeline if there are any alerts (failed tests) from the scans and performs some cleanup steps.

### authenticate-jwtbearer.yaml

#### Description

This optional step should be run before a scan if the user would like to obtain a JWT token for use in bearer token authentication, for example in an API scan using OpenIddict or IdentityServer. Please note that this step will not handle token expiry and renewal, and if a token expires before a scan has completed this will affect test outcomes.

#### Parameters

| Name                |            | Description |
|---                  |---         | ---         |
| tokenIssuerUrl  | (required) | The url from which to request a token. |
| scope      | (required) | The scope of the token. |
| clientId   | (required) | The client ID. |
| clientSecret | (required) | The client secret. |
| username    | (required) | The username for the user. |
| password    | (required) | The password for the user (please make sure this is stored as a secret). |

#### Output

This step will emit a yaml variable of `access_token` which can then be made use of in other steps (i.e. using `$(access_token)`).

#### Example

See `examples/security/owasp-zap/header-authenticated-api-scan` in the `Audacia.Build` repository for a usage example.
