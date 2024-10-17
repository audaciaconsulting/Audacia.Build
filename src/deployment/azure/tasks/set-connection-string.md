# Set SQL Connection String Step

## Contents

- [Reason](#reason) - Reason for pipeline step
- [Prerequisites](#prerequisites) - Requirements to use pipeline tasks
- [Usage](#usage) - How to use the step in a pipeline

## Reason

This is being done as workaround due to an [issue](https://github.com/terraform-providers/terraform-provider-azurerm/issues/1440) with Terraform provisioning in Azure, where the application of database connections are not unique per deployment slot.

## Prerequisites

Ensure the following lines are added to your build pipeline.yaml

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: Audacia/Audacia.Build
```

For a broader understanding of yaml pipelines in azure read the following [documentation](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema%2Cparameter-schema#yaml-basics).

You will also need an Azure Service Principle creating which has access to your deployed environment. This can be done in Azure Devops by going to Project Settings > Service Connections > New Service Connection.

## Usage

Sets the database connection string on a Deployment Slot for an Azure Web Application.

### Parameters

| Name              |            | Description                                                     |
|---                |---         |---                                                              |
| azureSubscription | (required) | Azure Service Principle / Azure Subscription for the resource   |
| resourceGroupName | (required) | Name of the Azure Resource Group containing the application     |
| applicationName   | (required) | Name of the Azure Wep Application                               |
| slotName          | (optional) | Name of the Azure Web App Slot. Defaults to Production the slot |
| dbContext         | (required) | Name of the DbContext for your project                          |
| connectionString  | (required) | Connection string for your database context                     |

```yaml
  - template: /src/deployment/azure/tasks/set-connection-string.yaml@templates
    parameters:
      azureSubscription: 'Audacia Dev/Test'
      resourceGroupName: customer-project-dev
      applicationName: customer-project-dev-api
      slotName: Staging
      dbContextName: DatabaseContext
      connectionString: $(devConnectionString)
```
