# Terraform

## Contents

- [Overview](#overview)
- [Tasks](#tasks)

## Overview

The Terraform steps can be used to create Azure resources needed for an environment, including:

- Azure SQL database
- App service and staging slots
- Storage accounts
- Key vault

A pipeline using these steps should be run once per environment. The environment to provision (e.g. QA or UAT) can be configured as a parameter, and a job can even be defined to create some Azure DevOps variable groups to save information about the resources that are created.

## Tasks

### set-variable.yaml

The `set-variable` step adds a variable to the `terraform.tfvars` file. The given variable should already be defined in the `variables.tf` file.

### expand-variables.yaml

The `expand-variables` step adds each Terraform output as a pipeline variable so that they can be consumed by subsequent pipeline steps.

### destroy.yaml

The `destroy` step deletes previously provisioned resources. If no resources are passed in as parameters then all resources are deleted; otherwise just the list of resources passed into the step are deleted.
