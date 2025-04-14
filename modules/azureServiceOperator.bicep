targetScope = 'resourceGroup'

// *** This template deploys the cluster for poshcode.org. See README.md before making changes ***
@description('Required. The AKS OIDC IssuerUrl')
param oidcIssuerUrl string

@description('Optional. This template deploys the cluster for poshcode.org. See README.md before making changes')
param baseName string = 'aso'

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Tags for the resource. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags

// 64 is the max deployment name, and the longest name in our sub-deployments is 17 characters, 64-17 = 47
@description('Optional. Provide unique deployment name prefix for the module references. Defaults to take(deploymentName().name, 47)')
@maxLength(47)
param deploymentNamePrefix string = take(deployment().name, 64-17)


module aso 'userAssignedIdentity.bicep' = {
  // name: '${deploymentNamePrefix}_uai_aso'
  params: {
    baseName: baseName
    location: location
    tags: tags
    federatedIdentitySubjectIssuerDictionary: {
      // For creating Azure resources
      'system:serviceaccount:azure:operator': oidcIssuerUrl
    }
  }
}


module iam_azure_owner 'resourceRoleAssignment.bicep' = {
  // name: '${deploymentNamePrefix}_iam_aso_operator'
  params: {
    principalIds: [ aso.outputs.principalId ]
    resourceId: aso.outputs.id
    roleName: 'Contributor'
  }
}
