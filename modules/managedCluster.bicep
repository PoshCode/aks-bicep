@description('Required. The base for resource names')
param baseName string

@description('Optional. A dns prefix to put before .$location.cloudapp.azure.com')
param dnsPrefix string = baseName

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('Optional. Tags for this resource. Defaults to resourceGroup().tags')
param tags object = resourceGroup().tags


@description('Required. The base version of Kubernetes to use')
param kubernetesVersion string

@description('Optional. Controls how the node pool OS is upgraded. Default: NodeImage')
@allowed([
  'NodeImage'
  'None'
  'SecurityPatch'
  'Unmanaged'
])
param clusterNodeOSUpgradeChannel string = 'NodeImage'

@description('''Required. Controls which versions are automatically upgraded:
- Patch. The major.minor are kept as specified, and patch version is automatically upgraded
- Stable. Always upgrade to the latest patch of what Microsoft calls the "stable" release (n-1)
- Rapid. Always upgrade to the latest patch of what Microsoft calls the "rapid" release (n)
For more information [see setting the AKS cluster auto-upgrade channel](https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster#set-auto-upgrade-channel)
''')
@allowed([
  'node-image'
  'none'
  'patch'
  'rapid'
  'stable'
])
param controlPlaneUpgradeChannel string

@description('Optional. The Azure AD tenant GUID. Defaults to the subscription().tenant.Id')
param tenantId string = subscription().tenantId

@description('Optional. Username of local admin account. Defaults to devopsadmin')
param vmAdminUser string = 'devopsadmin'

@description('Required. SSH public key for local admin account.')
param vmAdminSshPublicKey string

@description('Optional. Maximum number of pods to run on a single node. Defaults to 40.')
param maxPodsPerNode int = 40

// @description('Required. The id of a subnet to deploy into.')
// param nodeSubnetId string

@description('Optional. Service CIDR for this cluster. Defaults to our shared service CIDR: 10.100.0.0/16')
param serviceCidr string = '10.100.0.0/16'

@description('Optional. IP Address for DNS service (make sure it is inside the serviceCidr). Defaults to 10.100.0.10')
param dnsServiceIP string = '10.100.0.10'

@description('Optional. Pod CIDR for this cluster. Defaults to: 10.192.0.0/16')
param podCidr string = '10.192.0.0/16'

@description('The AKS AutoscaleProfile. Has complex defaults I expect to change in production.')
param AutoscaleProfile object = {
  'balance-similar-node-groups': 'true'
  expander: 'random'
  'max-empty-bulk-delete': '10'
  'max-graceful-termination-sec': '600'
  'max-node-provision-time': '15m'
  'max-total-unready-percentage': '45'
  'new-pod-scale-up-delay': '0s'
  'ok-total-unready-count': '3'
  'scale-down-delay-after-add': '10m'
  'scale-down-delay-after-delete': '20s'
  'scale-down-delay-after-failure': '3m'
  'scale-down-unneeded-time': '10m'
  'scale-down-unready-time': '20m'
  'scale-down-utilization-threshold': '0.5'
  'scan-interval': '10s'
  'skip-nodes-with-local-storage': 'true' // here be dragons
  'skip-nodes-with-system-pods': 'true'
}

@description('Optional. Select which type of system NodePool to use. Default is "CostOptimized". Other options are "Standard" or "HighSpec"')
@allowed([ 'CostOptimized', 'Standard', 'HighSpec' ])
param systemNodePoolOption string = 'CostOptimized'

// PER: https://learn.microsoft.com/en-us/samples/azure-samples/aks-ephemeral-os-disk/aks-ephemeral-os-disk/
//  deploying a cluster with osDiskType equal to Ephemeral and kubeletDiskType equal to OS
//  and setting the osDiskSize equal to the maximum VM cache size is the recommended approach
// SEE ALSO: https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.AKS.EphemeralOSDisk/
// SEE ALSO: https://learn.microsoft.com/en-us/azure/aks/cluster-configuration#default-os-disk-sizing
//  Ephemeral OS disk is preferred and results in lower read/write latency, faster node scaling and cluster upgrades
//  The AKS minimum node OS disk size is 30GB. The default size depends on CPU count:
//  <8 128 GB, 8+ 256 GB, 16+ 512 GB, 64+ 1024 GB
//  If using a vm size with less than 128GB cache, we must specify the osDiskSize or managed disk

@description('System Pool presets based on the recommended system pool specs')
var systemNodePoolPresets = {
  CostOptimized: {
    vmSize: 'Standard_DS2_v2' // b4ms is cheaper for Windows, but not for linux in WestUS2
    osDiskSizeGB: 86 // 32 for B4ms
    count: 1
    minCount: 1
    maxCount: 3
    enableAutoScaling: true
    availabilityZones: []
  }
  Standard: {
    vmSize: 'Standard_DS2_v2'
    osDiskSizeGB: 86 // Maximum Ephemeral disk size on these VMs
    count: 3
    minCount: 3
    maxCount: 5
    enableAutoScaling: true
    availabilityZones: [
      '1'
      '2'
      '3'
    ]
  }
  HighSpec: {
    vmSize: 'Standard_D4s_v3'
    osDiskSizeGB: 100 // Maximum Ephemeral disk size on these VMs
    count: 3
    minCount: 3
    maxCount: 5
    enableAutoScaling: true
    availabilityZones: [
      '1'
      '2'
      '3'
    ]
  }
}

// overrides for the system node pool
var systemNodePoolBase = {
  name: 'npsystem01' // must be lowercase
  mode: 'System'
  nodeTaints: [
    'CriticalAddonsOnly=true:NoSchedule'
  ]
  nodeLabels: {
    optimized: 'general'
    partition: 'system'
  }
  osType: 'Linux'
  osDiskType: 'Ephemeral'
  kubeletDiskType: 'OS'
  maxPods: maxPodsPerNode
  type: 'VirtualMachineScaleSets'
  workloadRuntime: 'OCIContainer' // vs. WASM
  upgradeSettings: {
    maxSurge: '33%'
  }
}
var systemNodePool = union(systemNodePoolBase, systemNodePoolPresets[systemNodePoolOption])

@description('''Optional. An array of node pools for non-system workloads.
By default, one non-system node pool is created.

To control the node pools, you must pass an array of [managedclusters/agentpools][1], like:
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

For more information:
1. https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters/agentpools
''')
param additionalNodePoolProfiles array = []

var additionalNodePools = union(!empty(additionalNodePoolProfiles) ? additionalNodePoolProfiles : [ {
    vmSize: 'Standard_E2bds_v5'
    osDiskSizeGB: 75
    nodeLabels: {
      optimized: 'memory'
      partition: 'apps1'
    }
  } ], [systemNodePool])

@description('Required. We need to define the control plane identity so we can grant it permissions (and not have to recreate them if we delete/recreate the cluster).')
param controlPlaneIdentityId string

@description('Required. We need to define the agent pool identity so we can grant it permissions (and not have to recreate them if we delete/recreate the cluster).')
param kubeletIdentityId string

// @description('A logAnalyticsWorkspaceId for kubernetes')
// param logAnalyticsWorkspaceResourceID string

@description('A private AKS Kubernetes cluster')
resource cluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: 'aks-${baseName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlPlaneIdentityId}': {}
    }
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: tenantId
    }
    identityProfile: {
      kubeletidentity: {
        resourceId: kubeletIdentityId
      }
    }
    agentPoolProfiles: [ systemNodePool ]
    apiServerAccessProfile: {
      enablePrivateCluster: false
      // authorizedIPRanges: [
      // ]
      // privateDNSZone: 'none' // https://learn.microsoft.com/en-us/azure/aks/private-clusters#configure-private-dns-zone
      // enablePrivateClusterPublicFQDN: true // only if privateClusterDNSZone = none
    }
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: clusterNodeOSUpgradeChannel
      upgradeChannel: controlPlaneUpgradeChannel
    }
    autoScalerProfile: AutoscaleProfile
    /* *** AzureMonitoring ***
    azureMonitorProfile: {
      logs: {
        appMonitoring: {
          enabled: true
        }
        containerInsights: {
          enabled: true
          logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceID
          windowsHostLogs: {
            enabled: true
          }
        }
      }
      metrics: {
        appMonitoringOpenTelemetryMetrics: {
          enabled: true
        }
        enabled: true
        kubeStateMetrics: {
          metricAnnotationsAllowList: monitoringMetricAnnotations
          metricLabelsAllowlist: monitoringMetricLabels
        }
      }
    }
    // */
    // AAD enabled, no local accounts allowed
    disableLocalAccounts: false
    dnsPrefix: dnsPrefix
    enablePodSecurityPolicy: false
    enableRBAC: true
    // For private clusters? Public clusters use dnsPrefix
    //fqdnSubdomain: baseName

    kubernetesVersion: kubernetesVersion
    linuxProfile: {
      adminUsername: vmAdminUser
      ssh: {
        publicKeys: [
          {
            keyData: vmAdminSshPublicKey
          }
        ]
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      outboundType: 'loadBalancer'
      // This is the cluster load balancer, not the outbound
      loadBalancerSku: 'Standard'
      serviceCidr: serviceCidr
      podCidr: podCidr
      ipFamilies: [ 'IPv4' ]
      dnsServiceIP: dnsServiceIP
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
      }
    }
    // I really hate the default MC_ nonsense
    nodeResourceGroup: '${resourceGroup().name}-aks'
    oidcIssuerProfile: {
      enabled: true
    }
    publicNetworkAccess: 'Enabled'
    // privateLinkResources: [
    //   {
    //     //// id: '/subscriptions/167823da-0f70-4b25-992f-f29fdd28d520/resourcegroups/rg-aks-azusw2-dvo-dv1/providers/Microsoft.ContainerService/managedClusters/aks-aksinfra-azusw2-dvo-dv1/privateLinkResources/management'
    //     name: 'management'
    //     type: 'Microsoft.ContainerService/managedClusters/privateLinkResources'
    //     groupId: 'management'
    //     requiredMembers: [
    //       'management'
    //     ]
    //   }
    // ]

    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
      // defender: {
      //   logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceID
      //   securityMonitoring: {
      //     enabled: false
      //   }
      // }
    }

    // We're using our own UAI
    // servicePrincipalProfile: {
    //   clientId: 'msi'
    // }


    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
    /* *** It's not clear what guardrails do ***
    guardrailsProfile: {
      level: 'Warning'
      version: ''
    } //  */
    workloadAutoScalerProfile: {
      // *** KEDA autoscaling is one of the core reasons to use k8s in the first place ***
      keda: {
        enabled: true
      }
      // */
      /* *** the VerticalPodAutoscaler helps adjust requests and limits
      verticalPodAutoscaler: {
        enabled: false
        controlledValues: 'RequestsAndLimits'
        updateMode: 'Auto'
      }
      // */
    }
    addonProfiles: {
      /* *** KeyVault CSI Provider ***
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      } // */

      /* *** Log Analytics ***
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceResourceID
        }
      } // */

      /* *** OSM is an Envoy based service mesh interface ***
      // https://learn.microsoft.com/en-us/azure/aks/open-service-mesh-about
      openServiceMesh: {
        enabled: true
        config: {}
      }
      // */

      azurepolicy: {
        enabled: true
        config: {
          version: 'v2'
        }
      }
    }
  }
}

resource agentPools 'Microsoft.ContainerService/managedClusters/agentPools@2024-01-01' = [for (pool, index) in additionalNodePools: {
  // The default is 6 characters long because that's the max for Windows nodes
  name: contains(pool, 'name') ? pool.name : format('npuser{0:D2}', index)
  parent: cluster
  properties: {
    availabilityZones: contains(pool, 'availabilityZones') ? pool.availabilityZones : []
    // capacityReservationGroupID: 'string'
    count: contains(pool, 'count') ? pool.count : 1
    // creationData: { sourceResourceId: 'string' }
    enableAutoScaling: contains(pool, 'enableAutoScaling') ? pool.enableAutoScaling : true
    // enableCustomCATrust: contains(pool, 'enableCustomCATrust') ? pool.enableCustomCATrust : false
    enableEncryptionAtHost: contains(pool, 'enableEncryptionAtHost') ? pool.enableEncryptionAtHost : false
    enableFIPS: contains(pool, 'enableFIPS') ? pool.enableFIPS : false
    enableNodePublicIP: contains(pool, 'enableNodePublicIP') ? pool.enableNodePublicIP : false
    enableUltraSSD: contains(pool, 'enableUltraSSD') ? pool.enableUltraSSD : false
    // gpuInstanceProfile: 'string'
    // hostGroupID: 'string'
    // podSubnetID: 'string'
    kubeletConfig: contains(pool, 'kubeletConfig') ? pool.kubeletConfig : null // If not null, causes error: CustomKubeletConfig or CustomLinuxOSConfig can not be changed for this operation.
    kubeletDiskType: contains(pool, 'kubeletDiskType') ? pool.kubeletDiskType : 'OS'
    linuxOSConfig: contains(pool, 'linuxOSConfig') ? pool.linuxOSConfig : null
    maxCount: contains(pool, 'maxCount') ? pool.maxCount : 10 // int
    maxPods: contains(pool, 'maxPods') ? pool.maxPods : maxPodsPerNode // int
    minCount: contains(pool, 'minCount') ? pool.minCount : 1 // int
    mode: contains(pool, 'mode') ? pool.mode : 'User' // 'string'
    networkProfile: contains(pool, 'networkProfile') ? pool.networkProfile : {}

    nodeLabels: contains(pool, 'nodeLabels') ? pool.nodeLabels : {} // {}
    // nodePublicIPPrefixID: Doesn't support being empty
    nodeTaints: contains(pool, 'nodeTaints') ? pool.nodeTaints : [] // ['string' ]
    orchestratorVersion: join(take(split(kubernetesVersion, '.'), 2), '.')
    osDiskSizeGB: contains(pool, 'osDiskSizeGB') ? pool.osDiskSizeGB : 128 // int
    osDiskType: contains(pool, 'osDiskType') ? pool.osDiskType : 'Ephemeral' // 'string'
    osSKU: contains(pool, 'osSKU') ? pool.osSKU : 'Ubuntu' // 'string'
    osType: contains(pool, 'osType') ? pool.osType : 'Linux' // 'string'
    // podSubnetID: 'string'
    // powerState: contains(pool,'powerState') ? pool.powerState : //
    // proximityPlacementGroupID: contains(pool,'proximityPlacementGroupID') ? pool.proximityPlacementGroupID : // 'string'
    scaleDownMode: contains(pool, 'scaleDownMode') ? pool.scaleDownMode : 'Delete' // 'string'
    scaleSetEvictionPolicy: contains(pool, 'scaleSetEvictionPolicy') ? pool.scaleSetEvictionPolicy : 'Delete' // 'string'
    // scaleSetPriority: contains(pool,'scaleSetPriority') ? pool.scaleSetPriority : 'Regular' // causes error:  Changing property 'properties.ScaleSetPriority' is not allowed.
    // spotMaxPrice: contains(pool,'spotMaxPrice') ? pool.spotMaxPrice : 0
    type: contains(pool, 'type') ? pool.type : 'VirtualMachineScaleSets'
    tags: contains(pool, 'tags') ? pool.tags : tags // tags
    upgradeSettings: contains(pool, 'upgradeSettings') ? pool.upgradeSettings : { maxSurge: '33%' }
    vmSize: contains(pool, 'vmSize') ? pool.vmSize : 'Standard_DS2_v2' // 'string'
    // vnetSubnetID: contains(pool, 'vnetSubnetID') ? pool.vnetSubnetID : nodeSubnetId // 'string'
    // windowsProfile: contains(pool,'windowsProfile') ? pool.windowsProfile : {} // { }
    workloadRuntime: contains(pool, 'workloadRuntime') ? pool.workloadRuntime : 'OCIContainer' // 'string'
  }
}]

@description('The id of the AKS cluster')
output id string = cluster.id

@description('User Assigned Object ID for the Kubelet Identity used to access the ACR. Used for Azure Role assignement for AcrPull to the ACR, and for granting Akv2K8s access to KeyVaults')
output kubeletIdentityObjectId string = cluster.properties.identityProfile.kubeletidentity.objectId

@description('The OIDC Issuer URL for federated credentials (Workload Identity)')
output oidcIssuerUrl string = cluster.properties.oidcIssuerProfile.issuerURL
