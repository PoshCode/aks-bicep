@description('Required. The base for resource names (an aks-baseName cluster must exist)')
param baseName string

@description('Optional. The root kustomization name for the cluster (defaults to baseName, but flux normally defaults to "bootstrap")')
param fluxKustomizationName string = baseName

@description('Required. The url of the gitOps repository.')
param gitOpsGitRepositoryUrl string

@description('Optional. If true, multiTenancy is enforced by the flux controller.')
param multiTenancy bool = false

@description('Optional. The ClientId of a user assigned identity to use for flux.')
param identityClientId string = ''

@description('Optional. If true, deploys the notification controller.')
param enableNotifications bool = false

@description('Optional. If true, deploys the image reflector and image automation controllers.')
param enableImageAutomation bool = false

@description('Optional. The user name for access to the gitOps repository')
@secure()
param gitOpsGitUsername string = ''

@description('Optional. The password (or PAT) for access to the gitOps repository')
@secure()
param gitOpsGitPassword string = ''

resource cluster 'Microsoft.ContainerService/managedClusters@2023-05-02-preview' existing = {
  name: 'aks-${baseName}'
}

var configuration = union(
  {
    'multiTenancy.enforce': multiTenancy ? 'true' : 'false'
    // https://fluxcd.io/flux/components/
    'source-controller.enabled': 'true'
    'kustomize-controller.enabled': 'true'
    'helm-controller.enabled': 'true'
  },
  identityClientId != '' ? {
    'workloadIdentity.enable': 'true'
    'workloadIdentity.azureClientId': identityClientId
  } : {},
  enableNotifications ? {
      // https://fluxcd.io/flux/components/notification/ can generate events for source changes
      'notification-controller.enabled': 'true'
  }: {},
  enableImageAutomation ? {
      // https://fluxcd.io/flux/components/image/ can update the Git repository when new container images are available
      'image-automation-controller.enabled': 'true'
      'image-reflector-controller.enabled': 'true'
  } : {})



// Supposedly, the extension will be installed automatically when you create the first
// Microsoft.KubernetesConfiguration/fluxConfigurations in a cluster
// But we're installing it by hand to control it more
resource flux 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
  name: 'flux'
  scope: cluster
  properties: {
    extensionType: 'microsoft.flux'
    autoUpgradeMinorVersion: true
    releaseTrain: 'Stable'
    aksAssignedIdentity: {
      type: 'UserAssigned'
    }
    scope: {
      cluster: {
        releaseNamespace: 'flux-system'
      }
    }
    configurationSettings: configuration
  }
  // If you have more than one Microsoft.KubernetesConfiguration they MUST BE SEQUENTIAL
  // This one is first
}

var gitRepository = union({
      url: gitOpsGitRepositoryUrl
      syncIntervalInSeconds: 120
      timeoutInSeconds: 180
      repositoryRef: {
        branch: 'main'
      }
    },(empty(gitOpsGitPassword) ? {} : {
      // This secret is created when we pass in configurationProtectedSettings
      localAuthRef: '${fluxKustomizationName}-protected-parameters'
    }))


var credentials = empty(gitOpsGitPassword) ? {} : {
  username: base64(gitOpsGitUsername)
  password: base64(gitOpsGitPassword)
}

resource fluxConfig 'Microsoft.KubernetesConfiguration/fluxConfigurations@2023-05-01' = {
  name: fluxKustomizationName
  scope: cluster

  properties: {
    sourceKind: 'GitRepository'
    scope: 'cluster'
    namespace: 'flux-system'

    gitRepository: gitRepository
    kustomizations: {
      cluster: {
        path: 'clusters/${baseName}'
        timeoutInSeconds: 600
        syncIntervalInSeconds: 120
        retryIntervalInSeconds: 60
        prune: false
      }
    }
    configurationProtectedSettings: credentials
  }
  // If you have more than one Microsoft.KubernetesConfiguration they MUST BE SEQUENTIAL
  dependsOn: [ flux ]
}

@description('The namespace used by flux for deployments')
output fluxReleaseNamespace string = flux.properties.scope.cluster.releaseNamespace
