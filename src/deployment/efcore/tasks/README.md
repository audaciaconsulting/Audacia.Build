# EF Core Deployment Steps

## Contents

- [Tasks](#tasks)

## Tasks

### migrate-bundle.yaml

Runs the EF Core migrations bundle.

#### Parameters

| Name                     |            | Description                                                                              |
|---                       |---         |---                                                                                       |
| connectionString         | (required) | The SQL Server connection string                                                         |
| serviceConnectionName    | (required) | Azure Service Principle / Azure Subscription for the resource                            |
| workingDirectory         | (optional) | The directory containing the bundle, defaults to $(Pipeline.Workspace)\EFMigrationBundle |

#### Usage

```yaml
  - template: /src/deployment/efcore/migrate-bundle.yaml@templates
    parameters:
      serviceConnectionName: 'QA Service Connection'
      connectionString: $(ConnectionStrings.DatabaseContext)
```

### migrate-idempotent-script.yaml

Runs the EF Core migrations script for the provided DbContext on the provided SQL Server.
Requires build and publish to have been run at an earlier stage in the pipeline.

#### Parameters

| Name              |            | Description                                                   |
|---                |---         |---                                                            |
| dbContext         | (required) | Name of the DbContext                                         |
| azureSubscription | (required) | Azure Service Principle / Azure Subscription for the resource |
| sqlHostname       | (required) | SQL Server Hostname                                           |
| sqlDatabase       | (required) | Database Name on the SQL Server                               |
| sqlUser           | (required) | SQL Server Username                                           |
| sqlPassword       | (required) | SQl Server Password                                           |
| artifactName      | (optional) | The name of the build artifact to use                         |
| displayName       | (optional) | Custom display name                                           |

#### Usage

```yaml
  - template: /src/deployment/efcore/migrate-idempotent-script.yaml@templates
    parameters:
      dbContext: DatabaseContext
      azureSubscription: 'Audacia Dev/Test'
      sqlHostname: audacia-template.database.windows.net
      sqlDatabase: Audacia.Template.Api
      sqlUser: adminuser
      sqlPassword: adminpassword
```
