@description('Required. The base for resource names')
param baseName string

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Tags for this resource. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags

@description ('''Optional. A dictionary of **subject identifiers** _to_ issuer URLs for configuring federated identity. Defaults to empty.
Supports creating federatedIdentityCredentials for Workload Identity, etc.
The format is: { 'subject identifier': 'issuerUrl' }
For example:
```bicep
{
  // A github actions wofklow connections:
  'repo:PoshCode/cluster:ref:refs/heads/main': 'https://token.actions.githubusercontent.com'

  // An AKS Workload Identities:
  'system:serviceaccount:${AKSNamespaceName}:${AKSServiceAccountName}': cluster.oidcIssuerURL

  // If you need to add the service account twice, add a trailing ":moreunique:value" in the key
  // The ":moreunique:" trailer and everything after it will be stripped out of the subject
  'system:serviceaccount:${AKSNamespaceName}:${AKSServiceAccountName}:moreunique:${cluster.oidcIssuerURL}': cluster.oidcIssuerURL
}
```
''')
param federatedIdentitySubjectIssuerDictionary object = {}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${baseName}'
  location: location
  tags: tags
}

@batchSize(1) // we can't create FIC in parallel, must be sequential
resource credential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [for (issuer, index) in items(federatedIdentitySubjectIssuerDictionary): {
  name: replace(replace(replace(issuer.key,'system:serviceaccount:',''),':','-'),'/','-')
  parent: userAssignedIdentity
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: issuer.value

    // If "moreunique" is there to make the name unique, don't include it in the subject
    subject: split(issuer.key,':moreunique:')[0]
  }
}]


@description('The name of the user assigned idenity resource (because it is calculated)')
output name string = userAssignedIdentity.name

@description('Resource ID, for deployment scripts')
output id string = userAssignedIdentity.id

@description('Principal ID, for Azure Role assignement')
output principalId string = userAssignedIdentity.properties.principalId

@description('Client ID, for application config (so we can use this identity from code)')
output clientId string = userAssignedIdentity.properties.clientId
