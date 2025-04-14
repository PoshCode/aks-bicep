<#
    .SYNOPSIS
        Prepares an Azure subscription, resource group, and service account and puts secrets into a GitHub repo.
    .DESCRIPTION
        Creates a new Azure AD application and service principal, and grants it access to a resource group.
        Also creates a new federated identity credential for the service principal, and sets the secrets
        for the repo workflows.
#>
[CmdletBinding()]
param(
    # The base name to use. E.g. the "cluster" name
    [Parameter(Mandatory = $true)]
    [string]$BaseName,

    # If set, will remove the existing app and service principal, so we can recreate it.
    [switch]$RemoveExisting,

    # The location to create the resource group in. E.g. "eastus"
    [string]$Location = "eastus",

    # The repo to set secrets for. E.g. "PoshCode/aks-bicep"
    [string]$Repository = "PoshCode/aks-bicep"
)

$BaseName = $BaseName.ToLowerInvariant()

# The resource group to create. E.g. "rg-cluster"
$resourceGroupName = @(
    # The first one should be the one where the cluster will be deployed
    "rg-${BaseName}"
    "rg-${BaseName}-aso"
)

# The service name to use. E.g. "rg-cluster-deploy"
$serviceName = "rg-${BaseName}-deploy"

# Register a bunch of preview features
Get-AzProviderFeature -ProviderNamespace Microsoft.ContainerService -OutVariable enabledFeatures
foreach ($feature in "AKS-KedaPreview", "AKSNetworkModePreview", "AzureOverlayPreview",
    "EnableBlobCSIDriver", "EnableNetworkPolicy", "NRGLockdownPreview",
    "NodeOSUpgradeChannelPreview", "IPBasedLoadBalancerPreview") {
    if ($enabledFeatures.Name -notcontains $feature) {
        Register-AzProviderFeature -FeatureName $feature -ProviderNamespace Microsoft.ContainerService
    }
}

Get-AzProviderFeature -ProviderNamespace Microsoft.KubernetesConfiguration -OutVariable enabledFeatures
foreach ($feature in "FluxConfigurations") {
    if ($enabledFeatures.Name -notcontains $feature ) {
        Register-AzProviderFeature -FeatureName $feature -ProviderNamespace Microsoft.KubernetesConfiguration
    }
}


$app =  (Get-AzADApplication -DisplayName $serviceName) ??
        (New-AzADApplication -DisplayName $serviceName)
$service =  (Get-AzADServicePrincipal -ApplicationId $app.AppId) ??
            (New-AzADServicePrincipal -ApplicationId $app.AppId)

# Create resource group
foreach ($name in $resourceGroupName) {
    (Get-AzResourceGroup -Name $name -ErrorAction SilentlyContinue) ??
    (New-AzResourceGroup -Name $name -Location $location -Force -Tag @{
        Repository = $Repository;
        Purpose    = "aks";
        Created    = Get-Date -Format "O"
    })
    $role = (Get-AzRoleAssignment -ResourceGroupName $name -RoleDefinitionName Owner -ObjectId $service.Id) ??
            (New-AzRoleAssignment -ResourceGroupName $name -RoleDefinitionName Owner -ObjectId $service.Id)
}

$fedcred =  (Get-AzADAppFederatedCredential -ApplicationObjectId $app.id -Filter "Subject eq 'repo:${Repository}:ref:refs/heads/main'" -ErrorAction SilentlyContinue) ??
            (New-AzADAppFederatedCredential -ApplicationObjectId $app.Id -Audience "api://AzureADTokenExchange" -Issuer "https://token.actions.githubusercontent.com" -Subject "repo:${Repository}:ref:refs/heads/main" -Name "$($Repository -replace '/','-')-main-gh")

$ctx = Get-AzContext

# Set Secrets for the $Repository workflows
gh secret set --repo https://github.com/$Repository AZURE_CLIENT_ID -b $app.AppId
gh secret set --repo https://github.com/$Repository AZURE_TENANT_ID -b $ctx.Tenant
gh secret set --repo https://github.com/$Repository AZURE_SUBSCRIPTION_ID -b $ctx.Subscription.Id
gh secret set --repo https://github.com/$Repository AZURE_RG -b $resourceGroupName[0]
# gh secret set --repo https://github.com/$Repository USER_OBJECT_ID -b $spId

# Create an AD Group to be administrators of the cluster:
$admins   = (Get-AzADGroup -Filter "DisplayName eq 'AksAdmins'") ??
            (New-AzADGroup -DisplayName AksAdmins -MailNickname AksAdmins -Description "Kubernetes Admins")

gh secret set --repo https://github.com/$Repository ADMIN_GROUP_ID -b $admins.Id