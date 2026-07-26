targetScope = 'resourceGroup'

@minLength(3)
@maxLength(12)
@description('Lowercase alphanumeric workload prefix.')
param prefix string
@allowed([
  'dev'
  'test'
  'preprod'
  'prod'
])
param stage string
param location string = resourceGroup().location
param deploymentPrincipalObjectId string
@allowed([
  'developer'
  'production'
])
param deploymentProfile string

var isProduction = deploymentProfile == 'production'
var suffix = uniqueString(subscription().id, resourceGroup().id, 'aks')
var registryName = take('${prefix}sharedaks${suffix}', 50)
var logsName = take('${prefix}-shared-aks-logs-${suffix}', 63)
var clusterName = take('${prefix}-shared-aks-${suffix}', 63)
var controlIdentityName = take('${prefix}-shared-aks-control-${suffix}', 128)
var kubeletIdentityName = take('${prefix}-shared-aks-kubelet-${suffix}', 128)
var namespaceName = 'delivery-demo-${stage}'
var sharedResourceTags = {
  application: 'delivery-demo'
  environment: 'shared'
  managedBy: 'bicep'
  profile: deploymentProfile
  strategy: 'rolling'
}
var repositoryReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b93aa761-3e63-49ed-ac28-beffa264f7ac')
var repositoryWriterRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a1e307c-b015-4ebd-883e-5b7698a07328')
var clusterUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f')
var rbacWriterRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a7ffa36f-339b-4b5c-8bdf-e2c188b2c0eb')
var identityOperatorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f1a07417-d97a-45cb-824c-7a7467783830')

module logs '../modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: logsName
    location: location
    tags: sharedResourceTags
    dailyQuotaGb: isProduction ? -1 : 1
  }
}

module registry '../modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    name: registryName
    location: location
    logAnalyticsWorkspaceId: logs.outputs.id
    tags: sharedResourceTags
    skuName: isProduction ? 'Standard' : 'Basic'
    enableDiagnostics: isProduction
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

resource controlIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: controlIdentityName
  location: location
  tags: sharedResourceTags
}

resource kubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: kubeletIdentityName
  location: location
  tags: sharedResourceTags
}

resource identityOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kubeletIdentity.id, controlIdentity.id, identityOperatorRoleId)
  scope: kubeletIdentity
  properties: {
    principalId: controlIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: identityOperatorRoleId
  }
}

resource runtimePull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, kubeletIdentity.id, repositoryReaderRoleId)
  scope: acr
  properties: {
    principalId: kubeletIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: repositoryReaderRoleId
  }
  dependsOn: [registry]
}

resource cluster 'Microsoft.ContainerService/managedClusters@2025-10-01' = {
  name: clusterName
  location: location
  tags: sharedResourceTags
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlIdentity.id}': {}
    }
  }
  properties: {
    aadProfile: {
      enableAzureRBAC: true
      managed: true
      tenantID: tenant().tenantId
    }
    agentPoolProfiles: isProduction ? [
      {
        name: 'system'
        availabilityZones: ['1', '2', '3']
        count: 3
        enableAutoScaling: true
        maxCount: 5
        maxPods: 50
        minCount: 3
        mode: 'System'
        osDiskSizeGB: 64
        osSKU: 'AzureLinux'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        upgradeSettings: {
          maxSurge: '1'
        }
        vmSize: 'Standard_D4ds_v5'
      }
    ] : [
      {
        name: 'system'
        count: 1
        enableAutoScaling: false
        maxPods: 50
        mode: 'System'
        osDiskSizeGB: 32
        osSKU: 'AzureLinux'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        upgradeSettings: {
          maxSurge: '1'
        }
        vmSize: 'Standard_D2s_v4'
      }
    ]
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
      upgradeChannel: 'stable'
    }
    disableLocalAccounts: true
    dnsPrefix: take('${prefix}-aks-${suffix}', 54)
    enableRBAC: true
    identityProfile: {
      kubeletidentity: {
        clientId: kubeletIdentity.properties.clientId
        objectId: kubeletIdentity.properties.principalId
        resourceId: kubeletIdentity.id
      }
    }
    networkProfile: {
      loadBalancerSku: 'standard'
      networkDataplane: 'azure'
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      outboundType: 'loadBalancer'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      imageCleaner: {
        enabled: true
        intervalHours: 48
      }
      workloadIdentity: {
        enabled: true
      }
    }
  }
  dependsOn: [identityOperator, runtimePull]
}

resource namespace 'Microsoft.ContainerService/managedClusters/managedNamespaces@2025-10-01' = {
  parent: cluster
  name: namespaceName
  location: location
  properties: {
    adoptionPolicy: 'Never'
    defaultNetworkPolicy: {
      ingress: 'AllowSameNamespace'
      egress: 'AllowAll'
    }
    defaultResourceQuota: {
      // Managed Namespace CPU quotas require Kubernetes milliCPU notation.
      cpuLimit: isProduction ? '4000m' : '1000m'
      cpuRequest: isProduction ? '2000m' : '500m'
      memoryLimit: isProduction ? '8Gi' : '2Gi'
      memoryRequest: isProduction ? '4Gi' : '1Gi'
    }
    deletePolicy: 'Keep'
    labels: {
      'app.kubernetes.io/managed-by': 'bicep'
      'delivery-demo/stage': stage
    }
  }
}

resource pipelinePush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, deploymentPrincipalObjectId, repositoryWriterRoleId)
  scope: acr
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: repositoryWriterRoleId
  }
  dependsOn: [registry]
}

resource pipelineClusterUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cluster.id, deploymentPrincipalObjectId, clusterUserRoleId)
  scope: cluster
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: clusterUserRoleId
  }
}

resource pipelineNamespaceWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(namespace.id, deploymentPrincipalObjectId, rbacWriterRoleId)
  scope: namespace
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: rbacWriterRoleId
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (isProduction) {
  name: 'send-to-log-analytics'
  scope: cluster
  properties: {
    workspaceId: logs.outputs.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output acrName string = registry.outputs.name
output aksName string = cluster.name
output logAnalyticsWorkspaceId string = logs.outputs.id
output stage string = stage
