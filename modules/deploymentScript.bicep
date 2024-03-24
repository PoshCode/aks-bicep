@description('Required. Name of the deploymentScript.')
param name string

@description('Required. The version of the Az modules (E.g. \'9.0\'). To get the supported list, just put in a bad value, or see here: https://mcr.microsoft.com/v2/azuredeploymentscripts-powershell/tags/list')
param azPowerShellVersion string

@description('Required. Script content. Please use loadTextContent() with a ps1 file named the same as the deploymentScript, for readability.')
param scriptContent string

@description('Required. The resource Id of a user assigned identity to run the deployment script. You can use UAIIdentity module to get this and get the id by calling UAIIdentity.outputs.userAssignedResourceID')
param userAssignedIdentityResourceID string

@description('Optional. Script arguments, separated by spaces. Defaults to empty.')
param scriptArguments string = ''

@description('Optional. The Azure data center location. Defaults to Resource Group Location')
param location string = resourceGroup().location

@description('Optional. Tags to apply to the deployment script. Defaults to the tags on the resource group.')
param tags object = resourceGroup().tags

@description('Optional. Maximum allowed script execution time specified in ISO 8601 format (for example P1D means one day). Defaults to PT30M (30 minutes).')
param timeout string = 'PT30M'

@description('Optional. Interval for which the service retains the script resource after the script has finished executing. The container will be deleted when this duration expires. Duration is based on ISO 8601 pattern and must be between 1 and 26 hours. Defaults to PT1H (one hour).')
param retentionInterval string = 'PT1H'

@description('Optional. The environment variables to pass over to the script. Defaults empty')
param environmentVariables array = []

@description('Optional. If a dynamically changing value is passed in, like utcNow() or newGuid(), then the output of the deploymentScript will not be cached, and will be recalculated/re-run.')
param forceUpdateTag string = '1'


var identity = {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '${userAssignedIdentityResourceID}' : {}
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (!empty(identity)) {
  name: name
  kind: 'AzurePowerShell'
  location: location
  tags: tags
  identity: identity
  properties: {
    scriptContent: scriptContent
    arguments: scriptArguments
    environmentVariables: environmentVariables
    azPowerShellVersion: azPowerShellVersion
    cleanupPreference: 'OnSuccess'
    retentionInterval: retentionInterval
    timeout: timeout
    forceUpdateTag: forceUpdateTag
  }
}

@description('Script properties.') // Preferably, we would have the script output here instead, but the outputs object does not exist if the $DeploymentScriptOutputs variable is empty
output deployScriptProperties object = deploymentScript.properties
