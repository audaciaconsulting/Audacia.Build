# Certificate Renewal Setup

The Certificate renewal pipeline it meant for updating certificates that are stored in Azure Key Vault. An example usage of this is that wildcard certificates are created/renewed, uploaded to Azure Key Vault and then used by Azure Front Door.

## Azure

These pipeline steps require a couple of components to be set up.

- An Azure Key Vault to store the Certificates in
- An Azure Blob Storage to store cached data for Posh-ACME in
  - Recommended to use a Storage Account for infrastructure type things
  - Recommended Storage Container name is `auto-renew-certificates`
- An Azure DNS Zone for which you are generating certificates
As all of this interaction is done from an Azure DevOps Pipeline, you will need to use an Azure Service Principal to authenticate with Azure. This is likely already setup for respective environments for use in deployments.
The Service Principal needs the following permissions setting up:
- `DNS Zone Contributor` role on the Azure DNS Zone
- `Reader` role on the Key Vault
  - An Access Policy with `Get` and `Import` for Certificates
- `Storage Blob Data Contributor` on the Storage Account Container

## Pipeline

Use the steps template inside of a steps array in a job in your pipeline.
The following parameters can be configured:

- `azureSubscription` - this is the name of the Service Principal to use that is configured in the Project
- `acmeContact` - the email address to send notifications to when certificates are nearing expiry
- `acmeDirectory` - the Let's Encrypt server to use, defaults to `LE_PROD` ([see here](https://poshac.me/docs/v4/Functions/Set-PAServer/))
- `storageAccountName` - the name of the Azure Storage Account to store cached data in
- `storageAccountContainer` - the name of the Storage Container to store cached data in, defaults to `auto-renew-certificates`
- `keyVaultName` - the name of the Azure Key Vault that Certificates are stored in
- `domains` - an array of domains to renew certificates for, each item in the array may contain more than one domain by comma separating the domains