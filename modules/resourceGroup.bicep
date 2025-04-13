targetScope = 'subscription'

@description('Required. The base name of the resource group (will be prefixed with "rg-")')
param name string

@description('The location to deploy')
param location string

@description('Tags for the resource')
param tags object

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
    name: name
    location: location
    tags: tags
}

@description('The resource ID of the resource group')
output id string = rg.id

@description('The name of the resource group')
output name string = rg.name

@description('The location of the resource group')
output location string = rg.location
