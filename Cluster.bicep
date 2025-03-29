// *** This template deploys the cluster for poshcode.org. See README.md before making changes ***
@description('Optional. This template deploys the cluster for poshcode.org. See README.md before making changes')
var baseName = 'poshcode'

@description('Optional. The url of the gitOps repository. Defaults to https://github.com/PoshCode/cluster obviously')
param gitOpsGitRepositoryUrl string = 'https://github.com/PoshCode/cluster'

@description('Optional. The user name for access to the gitOps repository')
@secure()
param gitOpsGitUsername string = ''

@description('Optional. The password (or PAT) for access to the gitOps repository')
@secure()
param gitOpsGitPassword string = ''

@description('Required. The GUID of the group or user that should have admin rights.')
param adminId string

@description('Optional. The Azure AD tenant GUID. Defaults to the subscription().tenant.Id')
param tenantId string = subscription().tenantId

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Tags for the resource. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags

@description('Optional. Username of local admin account. Defaults to {baseName}admin')
param vmAdmin string = ''
var vmAdminUser = vmAdmin == '' ? '${baseName}admin' : vmAdmin

// TODO: Get an SSH Key into the shared keyvault
@description('Optional. SSH Key for node admin access.')
param vmAdminSshPublicKey string = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC1sz5ltbHp9evmM9GevZgTbD2Xup2/63pp1lS5gKZU8n1HliS0CDAA23yCFloHi+y14IYz1aTPDRKM3zfz6OWLIaIMPvwN68dvHkCUleFP6mxtSHJGUQ/hIraEGcWp76YlwIvl8zP5iwljlZsraePMwcaKKCivR/ZFwN2bArNObvLk2svPW078AZCQix/c6YJTpUuOioq8W7R+4Zdl6fv4YOYID+vBOpKSZ3g64Qthpy7ZMGlWG+k9TdXfTUY3z837ZglxA6Ztp2ICj6WuNWH6ha88z+otJgdyzXTR+R6JVGS0PkcCCH30eBbnBl6IqH3We2vHJLKoYiELas5o7lPPhAGfS1OCzAcucUCVJEpIZL3fgRGJ6U0qhhHBRISywFPFXglj1XRZIypG8mW+rwQfxXKafWMWgEFZDB2ItHrqbrFHqjCKZPhY/4fDX0bI0GTlJ9XzP62FSp1x12jJ+AQVOdKM43f1w84ECnMeowUrC8TE/JIGGOoaywxOyOP5INk= aks deployment'

@description('Optional. Maximum number of pods to run on a single node. Defaults to 40.')
param maxPodsPerNode int = 40

// @description('Optional. The address prefix (CIDR) for the vnet')
// param vnetAddressPrefix string = '10.100.0.0/16'

// @description('Optional. The address prefix (CIDR) for the vnet')
// param nodeSubnetPrefix string = '10.100.10.0/24'

@description('Optional. If not set, you must install your own CNI before the cluster will be functional (See README)')
@allowed(['none', 'azure'])
param networkPlugin string = 'none'

@description('Optional. Only takes effect if the networkPlugin is set to "azure". Only the azure dataplane supports Windows containers, but this defaults to cilium.')
@allowed(['cilium', 'azure'])
param networkDataplane string = 'cilium'

@description('Optional. Service CIDR for this cluster. Defaults to our shared service CIDR: 10.100.0.0/16')
param serviceCidr string = '10.100.0.0/16'

@description('Optional. IP Address for DNS service (make sure it is inside the serviceCidr). Defaults to 10.100.0.10')
param dnsServiceIP string = '10.100.0.10'

@description('Optional. Pod CIDR for this cluster. Defaults to: 10.192.0.0/16')
param podCidr string = '10.192.0.0/16'

/*
@description('The Log Analytics retention period')
param logRetentionInDays int = 30

@description('The Log Analytics daily data cap (GB) (0=no limit)')
param logDataCap int = 0

@description('Diagnostic categories to log')
param diagnosticCategories array = [
  'cluster-autoscaler'
  'kube-controller-manager'
  'kube-audit-admin'
  'guard'
]
*/

@description('Optional. The AKS AutoscaleProfile has complex defaults I expect to change in production.')
param AutoscaleProfile object = {
  'balance-similar-node-groups': 'true'
  expander: 'random'
  'max-empty-bulk-delete': '3'
  'max-graceful-termination-sec': '600'
  'max-node-provision-time': '15m'
  'max-total-unready-percentage': '45'
  'new-pod-scale-up-delay': '120s'
  'ok-total-unready-count': '3'
  'scale-down-delay-after-add': '10m'
  'scale-down-delay-after-delete': '20s'
  'scale-down-delay-after-failure': '3m'
  'scale-down-unneeded-time': '10m'
  'scale-down-unready-time': '20m'
  'scale-down-utilization-threshold': '0.5'
  'scan-interval': '10s'
  // here be dragons
  'skip-nodes-with-local-storage': 'true'
  'skip-nodes-with-system-pods': 'true'
}

@description('Optional. Select which type of system NodePool to use. Default is "CostOptimized". Other options are "Standard" or "HighSpec"')
@allowed([ 'CostOptimized', 'Standard', 'HighSpec' ])
param systemNodePoolOption string = 'CostOptimized'

@description('''Optional. An array of managedclusters/agentpools for non-system workloads, like:
[
  {
    vmSize: 'Standard_E2bds_v5'
    osDiskSizeGB: 75
    nodeLabels: {
      optimized: 'memory'
      partition: 'apps1'
    }
  }
]

By default, one non-system node pool is created.

For more information on managedclusters/agentpools:
https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters/agentpools
''')
param additionalNodePoolProfiles array = []

@description('''
Optional. The base version of Kubernetes to use. Node pools are set to auto patch, so they only use the 'major.minor' part.
Defaults to 1.30
''')
param kubernetesVersion string = '1.30'

@description('''Optional. Controls automatic upgrades:
- none. No automatic patching
- node-image: Patch the node OS
- patch. Patch updates applied
- stable. Automatically upgrade to new "stable" releases
- rapid. Always upgrade to new "rapid" releases

For more information on the AKS cluster auto-upgrade channel:
https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster#set-auto-upgrade-channel
''')
@allowed([
  'node-image'
  'none'
  'patch'
  'rapid'
  'stable'
])
param controlPlaneUpgradeChannel string = 'stable'

@description('Optional. Controls how the nodes are patched. Default: NodeImage')
@allowed([
  'NodeImage'
  'None'
  'SecurityPatch'
  'Unmanaged'
])
param clusterNodeOSUpgradeChannel string = 'NodeImage'

// For subdeployments, prefix our name (which is hopefully unique/time-stamped)
var deploymentName = deployment().name

// resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
//   name: 'la-${baseName}'
//   location: location
//   tags: tags
//   properties:  union({
//       retentionInDays: logRetentionInDays
//       sku: {
//         name: 'PerNode'
//       }
//     },
//     logDataCap>0 ? { workspaceCapping: {
//       dailyQuotaGb: logDataCap
//     }} : {}
//   )
// }

// resource containerLogsV2_Basiclogs 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
//   name: 'ContainerLogV2'
//   parent: logAnalytics
//   properties: {
//     plan: 'Basic'
//   }
//   dependsOn: [
//     aks
//   ]
// }


// Used by the AKS agent pools to talk to the ACR
// The actual cluster's identity does not need federation
module kubeletId 'modules/userAssignedIdentity.bicep' = {
  name: '${deploymentName}_uai_kubelet'
  params: {
    baseName: '${baseName}-kubelet'
    location: location
    tags: tags
  }
}

// https://learn.microsoft.com/en-us/azure/aks/use-managed-identity#add-role-assignment-for-managed-identity

// Used by AKS control plane components to manage cluster resources...
// IMPORTANT: If you're using your own Disks, StaticIP, KubeletId, Vnet or RouteTable ...
// This user needs permissions on them
module controlPlaneId 'modules/userAssignedIdentity.bicep' = {
  name: '${deploymentName}_uai_controlPlaneId'
  params: {
    baseName: '${baseName}-aks'
    location: location
    tags: tags
  }
}

// For the KubeletId, Managed Identity Operator
module kubelet_iam 'modules/resourceRoleAssignment.bicep' = {
  name: '${deploymentName}_kubelet_iam'
  params: {
    principalIds: [ controlPlaneId.outputs.principalId ]
    resourceId: kubeletId.outputs.id
    roleName: 'Managed Identity Operator'
  }
}

// We can't deploy the cluster until the control plane identity owns the kubelet identity
module waitForRole 'modules/deploymentScript.bicep' = {
  name: '${deploymentName}_wait_role'
  params: {
    name: 'waitForRoleAssignment'
    location: location
    azPowerShellVersion : '13.2'
    userAssignedIdentityResourceID: controlPlaneId.outputs.id
    timeout: 'PT60M'
    scriptContent : join([
      '$DeploymentScriptOutputs = @{ Attempts = 1 }'
      'while (!($DeploymentScriptOutputs["RoleAssignment"] = Get-AzRoleAssignment -Scope "${kubeletId.outputs.id}" -PrincipalId "${controlPlaneId.outputs.principalId}" -RoleDefinitionName "Managed Identity Operator" -ErrorAction SilentlyContinue | ConvertTo-Json)) {'
      '   Write-Output ("{0:D2} Waiting a minute for the role assignment to be created..." -f $DeploymentScriptOutputs["Attempts"]++)'
      '   Start-Sleep -Seconds 60'
      '}'
    ], '\n')
  }
}

// For a custom VNet, vnet contributor

// module vnet 'modules/network.bicep' = {
//   name: '${deploymentName}_vnet'
//   params: {
//     baseName: baseName
//     location: location
//     tags: tags
//     vnetAddressPrefix: vnetAddressPrefix
//     //nodeSubnetPrefix: nodeSubnetPrefix
//   }
// }
// module vnet_iam 'modules/resourceRoleAssignment.bicep' = {
//   name: '${deploymentName}_vnet_aks_iam'
//   params: {
//     principalIds: [ controlPlaneId.outputs.principalId ]
//     resourceId: vnet.outputs.vnetId
//     roleName: 'Network Contributor'
//   }
// }


module keyVault 'modules/keyVault.bicep' = {
  name: '${deploymentName}_keyvault'
  params: {
    baseName: baseName
    location: location
    tags: tags
  }
}

module aks 'modules/managedCluster.bicep' = {
  name: '${deploymentName}_aks'
  dependsOn: [ waitForRole ]
  params: {
    baseName: baseName
    location: location
    tags: tags
    controlPlaneIdentityId: controlPlaneId.outputs.id
    kubeletIdentityId: kubeletId.outputs.id

    controlPlaneUpgradeChannel: controlPlaneUpgradeChannel
    clusterNodeOSUpgradeChannel: clusterNodeOSUpgradeChannel
    // nodeSubnetId: vnet.outputs.nodeSubnetId
    kubernetesVersion: kubernetesVersion
    AutoscaleProfile: AutoscaleProfile
    maxPodsPerNode: maxPodsPerNode
    // logAnalyticsWorkspaceResourceID: logAnalytics.id
    networkPlugin: networkPlugin
    networkDataplane: networkDataplane
    serviceCidr: serviceCidr
    podCidr: podCidr
    systemNodePoolOption: systemNodePoolOption
    vmAdminSshPublicKey: vmAdminSshPublicKey
    vmAdminUser: vmAdminUser
    tenantId: tenantId
    additionalNodePoolProfiles: additionalNodePoolProfiles
    dnsServiceIP: dnsServiceIP
  }
}

module fluxId 'modules/userAssignedIdentity.bicep' = {
  name: '${deploymentName}_uai_fluxId'
  params: {
    baseName: 'flux'
    location: location
    tags: tags
    federatedIdentitySubjectIssuerDictionary: {
      // For checking for new versions of helm charts and images
      'system:serviceaccount:flux-system:helm-controller': aks.outputs.oidcIssuerUrl
      'system:serviceaccount:flux-system:image-reflector-controller': aks.outputs.oidcIssuerUrl
      // Hypothetically, if workload identity works for git repos
      'system:serviceaccount:flux-system:source-controller': aks.outputs.oidcIssuerUrl
      // For SOPS (this identity would need KEY access to the right key)
      'system:serviceaccount:flux-system:kustomize-controller': aks.outputs.oidcIssuerUrl
    }
  }
}

@description('Optional. If true, skips Flux extension (you can still deploy it later, or by hand).')
param installFluxManually bool = false

// Managed Flux (obviously depends on the fluxId which depends on aks)
module flux 'modules/flux.bicep' = if (!installFluxManually) {
  name: '${deploymentName}_flux'
  params: {
    baseName: baseName
    identityClientId: fluxId.outputs.clientId
    gitOpsGitRepositoryUrl: gitOpsGitRepositoryUrl
    gitOpsGitUsername: gitOpsGitUsername
    gitOpsGitPassword: gitOpsGitPassword
  }
}

// // Managed monitoring
// module alerts 'modules/metricAlerts.bicep' = {
//   name: '${deploymentName}_alerts'
//   dependsOn: [aks]
//   params: {
//     baseName: baseName
//     location: location
//     logAnalyticsWorkspaceResourceID: logAnalytics.id
//     diagnosticCategories: diagnosticCategories
//   }
// }

module iam_admin_aks 'modules/resourceRoleAssignment.bicep' = {
  name: '${deploymentName}_iam_admin_aks'
  params: {
    principalIds: [ adminId ]
    resourceId: aks.outputs.id
    roleName: 'Azure Kubernetes Service RBAC Cluster Admin'
  }
}

module iam_admin_kv_secrets 'modules/resourceRoleAssignment.bicep' = {
  name: '${deploymentName}_iam_admin_kv_secrets'
  params: {
    principalIds: [ adminId ]
    resourceId: keyVault.outputs.id
    roleName: 'Key Vault Secrets Officer'
  }
}

module iam_admin_kv_crypto 'modules/resourceRoleAssignment.bicep' = {
  name: '${deploymentName}_iam_admin_kv_crypto'
  params: {
    principalIds: [ adminId ]
    resourceId: keyVault.outputs.id
    roleName: 'Key Vault Crypto Officer'
  }
}

module iam_flux_crypto 'modules/resourceRoleAssignment.bicep' = {
  name: '${deploymentName}_iam_flux_crypto'
  params: {
    principalIds: [ fluxId.outputs.principalId ]
    resourceId: keyVault.outputs.id
    roleName: 'Key Vault Crypto User'
  }
}

// @description('Flux release namespace')
// output fluxReleaseNamespace string = flux.outputs.fluxReleaseNamespace

@description('Cluster ID')
output clusterId string = aks.outputs.id

@description('User Assigned Identity Resource ID, required by deployment scripts')
output kubeletIdentityResourceID string = kubeletId.outputs.id

@description('User Assigned Identity Object ID, used for Azure Role assignement')
output kubeletIdentityPrincipalId string = kubeletId.outputs.principalId

@description('User Assigned Identity Client ID, used for application config (so we can use this identity from code)')
output kubeletIdentityClientId string = kubeletId.outputs.clientId

@description('User Assigned Identity Resource ID, required by deployment scripts')
output fluxIdResourceID string = fluxId.outputs.id

@description('User Assigned Identity Object ID, used for Azure Role assignement')
output fluxIdPrincipalId string = fluxId.outputs.principalId

@description('User Assigned Identity Client ID, used for application config (so we can use this identity from code)')
output fluxIdClientId string = fluxId.outputs.clientId

@description('Uri for the sops-key to be used for secret encryption')
output sopsKeyId string = keyVault.outputs.sopsKeyId

@description('The results from the waitForRole script, for troubleshooting')
output deploymentScriptResults object = waitForRole.outputs.deployScriptProperties
// output LogAnalyticsName string = logAnalytics.name
// output LogAnalyticsGuid string = logAnalytics.properties.customerId
// output LogAnalyticsId string = logAnalytics.id
