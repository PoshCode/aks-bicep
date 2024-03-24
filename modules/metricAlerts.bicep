@description('Required. The base for resource names')
param baseName string

@description('Optional. The location to deploy. Defaults to resourceGroup().location')
param location string = resourceGroup().location

@description('A logAnalyticsWorkspaceId for kubernetes')
param logAnalyticsWorkspaceResourceID string

@description('Diagnostic categories to log')
param diagnosticCategories array = [
  'cluster-autoscaler'
  'kube-controller-manager'
  'kube-audit-admin'
  'guard'
]


resource cluster 'Microsoft.ContainerService/managedClusters@2023-07-01' existing = {
  name: 'aks-${baseName}'
}

resource AksDiags 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aksDiags'
  scope: cluster
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceID
    logs: [for aksDiagCategory in diagnosticCategories: {
      category: aksDiagCategory
      enabled: true
    }]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource sysLog 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'msci-${baseName}'
  location: location
  kind: 'Linux'
  properties: {
    dataFlows: [
      {
        destinations: [
          'ciworkspace'
        ]
        streams: [
          'Microsoft-Syslog'
          'Microsoft-ContainerInsights-Group-Default'
        ]
      }
    ]
    dataSources: {
      extensions: [
        {
          streams: [
            'Microsoft-ContainerInsights-Group-Default'
          ]
          extensionName: 'ContainerInsights'
          extensionSettings: {
            dataCollectionSettings: {
              interval : '1m'
              namespaceFilteringMode: 'Off'
            }
          }
          name: 'ContainerInsightsExtension'
        }
      ]
      syslog: [
        {
          facilityNames: [
            'auth'
            'authpriv'
            'cron'
            'daemon'
            'mark'
            'kern'
            'local0'
            'local1'
            'local2'
            'local3'
            'local4'
            'local5'
            'local6'
            'local7'
            'lpr'
            'mail'
            'news'
            'syslog'
            'user'
            'uucp'
          ]
          logLevels: [
            'Debug'
            'Info'
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
          name: 'sysLogsDataSource'

          streams: ['Microsoft-Syslog']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'ciworkspace'
          workspaceResourceId: logAnalyticsWorkspaceResourceID
        }
      ]
    }
  }
}

resource association 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${cluster.name}-law-association'
  scope: cluster
  properties: {
    dataCollectionRuleId: sysLog.id
    description: 'Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster.'
  }
}

@description('Select the frequency on how often the alert rule should be run. Selecting frequency smaller than granularity of datapoints grouping will result in sliding window evaluation')
@allowed([
  'PT1M'
  'PT15M'
])
param evalFrequency string = 'PT1M'

@description('Create the metric alerts as either enabled or disabled')
param metricAlertsEnabled bool = true

@description('Defines the interval over which datapoints are grouped using the aggregation type function')
@allowed([
  'PT5M'
  'PT1H'
])
param windowSize string = 'PT5M'

@allowed([
  'Critical'
  'Error'
  'Warning'
  'Informational'
  'Verbose'
])
param alertSeverity string = 'Informational'

var alertServerityLookup = {
  Critical: 0
  Error: 1
  Warning: 2
  Informational: 3
  Verbose: 4
}
var alertSeverityNumber = alertServerityLookup[alertSeverity]

var AksResourceId = resourceId('Microsoft.ContainerService/managedClusters', 'aks-${baseName}')

resource Node_CPU_utilization_high_for_aks_cluster_CI_1 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Node CPU utilization high for aks-${baseName} CI-1'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'host'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'cpuUsagePercentage'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Node CPU utilization across the cluster.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Node_working_set_memory_utilization_high_for_aks_cluster_CI_2 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Node working set memory utilization high for aks-${baseName} CI-2'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'host'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'memoryWorkingSetPercentage'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Node working set memory utilization across the cluster.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Jobs_completed_more_than_6_hours_ago_for_aks_cluster_CI_11 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Jobs completed more than 6 hours ago for aks-${baseName} CI-11'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'completedJobsCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors completed jobs (more than 6 hours ago).'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Container_CPU_usage_high_for_aks_cluster_CI_9 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Container CPU usage high for aks-${baseName} CI-9'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'cpuExceededPercentage'
          metricNamespace: 'Insights.Container/containers'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors container CPU utilization.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Container_working_set_memory_usage_high_for_aks_cluster_CI_10 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Container working set memory usage high for aks-${baseName} CI-10'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'memoryWorkingSetExceededPercentage'
          metricNamespace: 'Insights.Container/containers'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors container working set memory utilization.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Pods_in_failed_state_for_aks_cluster_CI_4 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Pods in failed state for aks-${baseName} CI-4'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'phase'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
          metricName: 'podCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Pod status monitoring.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Disk_usage_high_for_aks_cluster_CI_5 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Disk usage high for aks-${baseName} CI-5'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'host'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'device'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'DiskUsedPercentage'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors disk usage for all nodes and storage devices.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Nodes_in_not_ready_status_for_aks_cluster_CI_3 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Nodes in not ready status for aks-${baseName} CI-3'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'status'
              operator: 'Include'
              values: [
                'NotReady'
              ]
            }
          ]
          metricName: 'nodesCount'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Node status monitoring.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Containers_getting_OOM_killed_for_aks_cluster_CI_6 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Containers getting OOM killed for aks-${baseName} CI-6'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'oomKilledContainerCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors number of containers killed due to out of memory (OOM) error.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Persistent_volume_usage_high_for_aks_cluster_CI_18 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Persistent volume usage high for aks-${baseName} CI-18'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'podName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetesNamespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'pvUsageExceededPercentage'
          metricNamespace: 'Insights.Container/persistentvolumes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors persistent volume utilization.'
    enabled: false
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Pods_not_in_ready_state_for_aks_cluster_CI_8 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Pods not in ready state for aks-${baseName} CI-8'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'PodReadyPercentage'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'LessThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors for excessive pods not in the ready state.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: windowSize
  }
}

resource Restarting_container_count_for_aks_cluster_CI_7 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Restarting container count for aks-${baseName} CI-7'
  location: 'global'
  properties: {
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'restartingContainerCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors number of containers restarting across the cluster.'
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      AksResourceId
    ]
    severity: alertSeverityNumber
    targetResourceType: 'Microsoft.ContainerService/managedClusters'
    windowSize: windowSize
  }
}

resource Container_CPU_usage_violates_the_configured_threshold_for_aks_cluster_CI_19 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: 'Container CPU usage violates the configured threshold for aks-${baseName} CI-19'
  location: 'global'
  properties: {
    description: 'This alert monitors container CPU usage. It uses the threshold defined in the config map.'
    severity: alertSeverityNumber
    enabled: true
    scopes: [
      AksResourceId
    ]
    evaluationFrequency: evalFrequency
    windowSize: windowSize
    criteria: {
      allOf: [
        {
          threshold: 0
          name: 'Metric1'
          metricNamespace: 'Insights.Container/containers'
          metricName: 'cpuThresholdViolated'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          skipMetricValidation: true
          criterionType: 'StaticThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
  }
}

resource Container_working_set_memory_usage_violates_the_configured_threshold_for_aks_cluster_CI_20 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: 'Container working set memory usage violates the configured threshold for aks-${baseName} CI-20'
  location: 'global'
  properties: {
    description: 'This alert monitors container working set memory usage. It uses the threshold defined in the config map.'
    severity: alertSeverityNumber
    enabled: metricAlertsEnabled
    scopes: [
      AksResourceId
    ]
    evaluationFrequency: evalFrequency
    windowSize: windowSize
    criteria: {
      allOf: [
        {
          threshold: 0
          name: 'Metric1'
          metricNamespace: 'Insights.Container/containers'
          metricName: 'memoryWorkingSetThresholdViolated'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          skipMetricValidation: true
          criterionType: 'StaticThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
  }
}


resource PV_usage_violates_the_configured_threshold_for_aks_cluster_CI_21 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: 'PV usage violates the configured threshold for aks-${baseName} CI-21'
  location: 'global'
  properties: {
    description: 'This alert monitors PV usage. It uses the threshold defined in the config map.'
    severity: alertSeverityNumber
    enabled: metricAlertsEnabled
    scopes: [
      AksResourceId
    ]
    evaluationFrequency: evalFrequency
    windowSize: windowSize
    criteria: {
      allOf: [
        {
          threshold: 0
          name: 'Metric1'
          metricNamespace: 'Insights.Container/persistentvolumes'
          metricName: 'pvUsageThresholdViolated'
          dimensions: [
            {
              name: 'podName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetesNamespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          skipMetricValidation: true
          criterionType: 'StaticThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
  }
}

/* *** This would not deploy?
resource Daily_law_datacap 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'Daily data cap breached for workspace la-${baseName} CIQ-1'
  location: location
  properties: {
    displayName: 'Daily data cap breached for workspace la-${baseName} CIQ-1'
    description: 'This alert monitors daily data cap defined on a workspace and fires when the daily data cap is breached.'
    severity: 1
    enabled: metricAlertsEnabled
    evaluationFrequency: evalFrequency
    scopes: [
      resourceId('microsoft.operationalinsights/workspaces', 'la-${baseName}')
    ]
    windowSize: windowSize
    autoMitigate: false
    criteria: {
      allOf: [
        {
          query: '_LogOperation | where Operation == "Data collection Status" | where Detail contains "OverQuota"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    muteActionsDuration: 'P1D'
  }
}
// */
