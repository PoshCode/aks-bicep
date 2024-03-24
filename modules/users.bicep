// ATTENTION PERSON WHO COPIES THIS IN THE FUTURE:
// namespace MUST be hard-coded here (change "Required" to "Optional" and uncomment the deffinition)
// namespace MUST match the namespace of your app in Kubernetes (do not leave it as an empty string!)
@description('Required. The kubernetes namespace for your user')
param namespace string // = ''

@description('Required. The name of the service account. E.g. namespace-workload-identity')
param serviceAccountName string = '${namespace}-workload-identity'

@description('Required. The OpenID Connect Issuerl URL. E.g. aks.oidcIssuerUrl')
param oidcIssuerUrl string

// 63 is our max deployment name, and the longest name in our sub-deployments is 12 characters, 63-12 = 51
@description('Optional. Provide unique deployment name prefix for the module references. Defaults to take(deploymentName().name, 51)')
@maxLength(51)
param deploymentNamePrefix string = take(deployment().name, 51)

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Override default tagging with your own tags. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags

module uai 'userAssignedIdentity.bicep' = {
  name: '${deploymentNamePrefix}_uai'
  params: {
    baseName: '${namespace}-${serviceAccountName}'
    location: location
    tags: tags
    // This is the part that makes it work with AKS -- but the right-hand-side value must be YOUR workload identity
    federatedIdentitySubjectIssuerDictionary: {
      'system:serviceaccount:${namespace}:${serviceAccountName}': '${oidcIssuerUrl}'
    }
  }
}

/* *** KeyVault example. To GET secrets in kubernetes, you must add a give access to the kubeletIdentityObjectId. ***
module keyVault 'br/resources:keyvault:6' = {
  name: '${deploymentName}_keyvault'
  params: {
    name: names.outputs.keyVaultName
    location: location
    tags: tags
  }
}
output keyVaultResourceId string = keyVault.outputs.id
output keyVaultName string = keyVault.outputs.name

// If you already have a key vault, you just need this part:
module keyvault_kubelet_iam 'br/resources:resourceroleassignment:1.0.2' = {
  name: '${deploymentName}_akv2k8s_iam'
  params: {
    principalIds: [
      cluster.outputs.kubeletIdentityObjectId
    ]
    resourceId: keyVault.outputs.id
    roleName: 'Key Vault Secrets User'
  }
}

// */

@description('The ResourceId is sometimes used for deployment scripts')
output userAssignedResourceId string = uai.outputs.id

@description('The PrincipalId is used for Azure Resource Role Assignements')
output userAssignedIdentityPrincipalId string = uai.outputs.principalId

@description('''User Assigned Client ID, put this in your patch-ServiceAccount.yaml:
metadata:
  name: serviceAccountName
  annotations:
    azure.workload.identity/client-id: HERE''')
output userAssignedIdentityClientId string = uai.outputs.clientId
