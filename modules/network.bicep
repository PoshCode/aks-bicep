@description('Required. The base for resource names')
param baseName string

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Tags for this resource. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags

@description('Required. The address prefix (CIDR) for the vnet')
param vnetAddressPrefix string = '10.100.0.0/16'

var vnetName = 'vnet-${baseName}'

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}


output vnetId string = vnet.id


// @description('Required. The address prefix (CIDR) for the vnet')
// param nodeSubnetPrefix string = '10.100.10.0/24'

// resource nodeSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' = {
//   name: 'nodeSubnet'
//   parent: vnet
//   properties: {
//     addressPrefix: nodeSubnetPrefix
//   }
// }

// output nodeSubnetId string = nodeSubnet.id

// // In overlay mode, we don't need a pod subnet
// resource podSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-09-01' = {
//   name: 'podSubnet'
//   parent: vnet
//   properties: {
//     addressPrefix: '10.4.0.0/16'
//   }
// }
// resource serviceSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-09-01' = {
//   name: 'podSubnet'
//   parent: vnet
//   properties: {
//     addressPrefix: '172.10.0.0/16'
//   }
// }
