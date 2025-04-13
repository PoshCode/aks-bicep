# PoshCode k8s Cluster

This repo has a full bicep deployment for a Kubernetes Cluster, including a github workflow to deploy it.

I've written my own templates for deploying AKS in [Azure Bicep](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview), and I've been maintaining them for a number of years at this point. They are relatively opinionated as to what features I use, and I last overhauled them completely in early 2024. I'm still maintaining them, and doing clean deploys as of March 2024. If you're not interested in my infrastructure code, but want to deploy Kubernetes to Azure, you should consider the [AKS Construction](https://azure.github.io/AKS-Construction/) as an alternative. There are also AKS templates in the [Azure Quickstart Templates](https://learn.microsoft.com/en-us/samples/azure/azure-quickstart-templates/aks/), although those are relatively simplistic -- fine for a test case or demo, but perhaps not for your production cluster.

## Azure Prerequisites

These pre-requisites are not part of the CI/CD build, because they only have to be done once, but the [`Initialize-Azure`](./Initialize-Azure.ps1) script is essentially idempotent and re-runnable.

1. Enable some features in your Azure tenant (some of which are pre-release features as of this writing)
2. Create a resource group in Azure to deploy to (currently TWO resource groups, see [Azure Service Operator](#azure-service-operator) below)
3. Create a service account in Azure for automation
4. Assign the "owner" role on the resource group to the service account
5. Create secrets in github for authentication as that service account

The first step, enabling features, only has to be done once per subscription. For best practices, the remaining steps should be done once for each cluster, for security purposes. The idea is that the subscription owner runs this script by hand, and then the automated service account is restricted to deploying to this single resource group.

See [`Initialize-Azure`](./Initialize-Azure.ps1) for details. You might call it like this:

```PowerShell
./Initialize-Azure -BaseName $name
```

### Azure Service Operator

I'm testing some things with the [Azure Service Operator](https://github.com/Azure/azure-service-operator), and for right now, this bicep creates a third resource group (i.e. if you create 'rg-poshcode' in Azure, AKS will create 'rg-poshcode-aks' and the bicep needs 'rg-poshcode-aso' to _contain_ the operator). That way it's creating a user assigned identity for the [Azure Service Operator](https://github.com/Azure/azure-service-operator) to use which has `Contributor` access just to the -aso resource group.

In order to avoid giving the github service account additional access, I modified the Initialize-Azure PowerShell script instead.

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

One thing to note is that I am using a _public_ repository ([PoshCode/Cluster](/PoshCode/Cluster)) for my GitOps configuration. Because it's public, there's no need to configure any sort of authentication tokens for Flux to be able to access it.

I'm currently using the Azure Kubernetes Flux Extension to install Flux CD for GitOps, this dramatically simplifies configuration for Flux: when the Bicep deployment is complete, Flux is already running on the cluster.

### Manually bootstrapping Flux

If you wanted to install flux by hand on an existing cluster, it can be as simple as:

```PowerShell
flux bootstrap github --owner PoshCode --repository cluster --path=clusters/poshcode
```

But if you need to customize workload identity, it can get a bit more complex, but Workload Identity is supported now for access to [Azure DevOps](https://fluxcd.io/flux/components/source/gitrepositories/#azure) and [GitHub](https://fluxcd.io/flux/components/source/gitrepositories/#github), at least.

## ⚠️ CURRENT STATUS _WARNING_ ⚠️

I am testing with Cilium Gateway API. Gateway API support in Cilium is part of _their_ Service Mesh functionality, and it doesn't seem Azure's AKS team is terribly keen on making it an option to let Cilium take over all of networking, so although they have an "Azure CNI powered by Cilium" it doesn't look like I can get the Gateway API from cilium if I install it with Azure CNI, so in order to use Cilium fully...

**IMPORTANT**: Upgrading Cilium is currently a process that is fraught with peril. _Look, it's my duty as a knight to sample as much peril as I can_. You may feel differently. [Check at least one version of their upgrade guides before you decide to use Cilium](https://docs.cilium.io/en/stable/operations/upgrade/).

Additionally, you need to use Windows containers, you must use azure networking CNI.

If you set the 'networkPlugin' parameter to 'azure' you'll get Azure CNI powered by Cilium. If you need to use Windows containers, also set the 'networkDataplane' to 'azure' (otherwise, Azure CNI powered by Cilium is clearly the fastest network available out of the box in AKS).

### I have set the network plugin to "none"

NOTE: The easiest way to into cilium is to use the cilium CLI (it actually includes helm, and the helm chart). But to do this, it needs to discover details about your cluster usint the the `az` CLI tool _and the `aks-preview` extension_.

Make sure you have the latest version of those installed, and if you can run the equivalent of this command, the cilium install will work:

```powershell
az aks show --resource-group rg-poshcode --name aks-poshcode
```

### Installling Cilium

Installing the cilium CLI tool locally is as simple as downloading the right release from their GitHub release pages and unzipping.

```PowerShell
Install-GitHubRelease cilium cilium-cli
```

Installing cillium into the AKS cluster can be done _part of the way through the Bicep deployment_.  With "none" as the network plugin, the nodes won't come up "ready" and the flux deployment will time out. If you run the cilium install while ARM is still trying to install Flux, it will succeed in a single pass.

1. You want to `Import-AzAksCredential` as soon as the cluster shows up in Azure.
2. Try `kubectl get nodes` until it shows your nodes (they won't come up ready, because they won't have a network)
3. Then run the `cilium install` command, using the correct for the resourceGroup name

```PowerShell
cilium install --version 1.17.0 --set azure.resourceGroup="rg-$name" --set kubeProxyReplacement=true
```

If you are not fast enough, it is not a big deal -- the deployment will fail after the time-out, but you can just re-run the deployment after you finish the cilium install.

### Configuring the Cilium Gateway API

In order to use the Gateway API, we need to [install the Gateway CRDs](https://gateway-api.sigs.k8s.io/guides/). That's handled (after the cluster install) by Flux. Of course that means that we have to re-configure Cilium _after_ the initial deployment. I haven't automated this part yet (because I didn't want to make the GitOps deployment _depend_ on Cilium), but it's pretty straightforward:

First install the Gateway API CRDs (in my deployment, this is handled by Flux)

```PowerShell
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
```

Then [redeploy the cilium chart, to enable the gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/). I'm _also_ enabling hubble and prometheus:

```PowerShell
cilium install --version 1.17.0 --set azure.resourceGroup="rg-$name" `
    --set kubeProxyReplacement=true `
    --set gatewayAPI.enabled=true `
    --set hubble.enabled=true `
    --set prometheus.enabled=true `
    --set operator.prometheus.enabled=true `
    --set hubble.metrics.enableOpenMetrics=true `
    --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"
```

