@description('Required. The base for resource names')
param baseName string

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Tags for this resource. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags

@description('Optional. Determines whether Azure Resource Manager is able to retrieve secrets. Defaults to false.')
param enabledForTemplateDeployment bool = false

@description('Optional. Determines whether Azure VMs are able to retrieve certificates (stored as secrets). Defaults to false.')
param enabledForDeployment bool = false

@description('Optional. Determines whether Azure Disk Encryption is able retrieve secrets and unwrap keys. Defaults to false.')
param enabledForDiskEncryption bool = false

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${baseName}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableSoftDelete: true
    enableRbacAuthorization: true
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
  }
}

resource sopsKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: vault
  name: 'sops-key'
  properties: {
    kty: 'RSA'
    keyOps: [
      'decrypt'
      'encrypt'
    ]
  }
}


@description('Name of the keyvault')
output name string = vault.name

@description('Resource Id of the keyvault')
output id string = vault.id

@description('key for sops')
output sopsKeyId string = sopsKey.id
