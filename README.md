# PoshCode k8s Cluster

This repo has a full bicep deployment for a Kubernetes Cluster, including a github workflow to deploy it.

I've written my own templates for deploying AKS in [Azure Bicep](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview), and I've been maintaining them for a number of years at this point. They are relatively opinionated as to what features I use, and I last overhauled them completely in early 2024. I'm still maintaining them, and doing clean deploys as of March 2024. If you're not interested in my infrastructure code, but want to deploy Kubernetes to Azure, you should consider the [AKS Construction](https://azure.github.io/AKS-Construction/) as an alternative. There are also AKS templates in the [Azure Quickstart Templates](https://learn.microsoft.com/en-us/samples/azure/azure-quickstart-templates/aks/), although those are relatively simplistic -- fine for a test case or demo, but perhaps not for your production cluster.

## Azure Prerequisites

These pre-requisites are not part of the CI/CD build, because they only have to be done once, but the [Initialize-Azure](./Initialize-Azure.ps1) script is essentially idempotent and re-runnable.

1. Enable some features in your Azure tenant (some of which are pre-release features as of this writing)
2. Create a resource group in Azure to deploy to
3. Create a service account in Azure for automation
4. Assign the "owner" role on the resource group to the service account
5. Create secrets in github for authentication as that service account

The first step, enabling features, only has to be done once per subscription. For best practices, the remaining steps should be done once for each cluster, for security purposes. The idea is that the subscription owner runs this script by hand, and then the automated service account is restricted to deploying to this single resource group.

See [Initialize-Azure](./Initialize-Azure.ps1)` for details. You might call it like this:

```PowerShell
./Initialize-Azure -BaseName $name
```

## Deploying Infrastructure

Each time the IAC templates change, we're going to run New-AzResourceGroupDeployment, but we have a [workflow for that](.github/workflows/deploy.yaml), of course.

[![Deploy Kubernetes Cluster](https://github.com/PoshCode/cluster/actions/workflows/deploy.yaml/badge.svg)](https://github.com/PoshCode/cluster/actions/workflows/deploy.yaml)

If you were to run it by hand, it might look like this:

```PowerShell
$Deployment = @{
    Name = "aks-$(Get-Date -f yyyyMMddThhmmss)"
    ResourceGroupName = "rg-$name"
    TemplateFile = ".\Cluster.bicep"
    TemplateParameterObject = @{
        baseName = "$name"
        adminId = (Get-AzADGroup -Filter "DisplayName eq 'AksAdmins'").Id
    }
}

New-AzResourceGroupDeployment @Deployment -OutVariable Results
```

## GitOps Configuration

One thing to note is that I am using a _public_ repository ([PoshCode/Cluster](/PoshCode/Cluster)) for my GitOps configuration. Because it's public, there's no need to configure a PAT token or anything for Flux to be able to access it.

I'm currently using the Azure Kubernetes Flux Extension to install Flux CD for GitOps. That dramatically simplifies everything, because the Bicep deployment is literally all that's required to deploy the working cluster. However, if you needed to configure the credentials, you would just pass `gitOpsGitUsername` and `gitOpsGitPassword` as part of the `TemplateParameterObject`. There is a feature coming later this year to Flux to support Workflow Identity for git authentication, but for now you need to use a read-only deploy token or something.

### Manually bootstrapping Flux

If you wanted to install flux by hand on an existing cluster, it can be as simple as:

```PowerShell
flux bootstrap github --owner PoshCode --repository cluster --path=clusters/poshcode
```

But if you need to customize workload identity, it can get a lot more complex, because you'll need to patch the flux deployment.