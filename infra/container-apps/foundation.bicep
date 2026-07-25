targetScope = 'resourceGroup'

@minLength(3)
@maxLength(12)
@description('Lowercase alphanumeric workload prefix.')
param prefix string
param location string = resourceGroup().location
param deploymentPrincipalObjectId string
param publisherPrincipalObjectId string
@allowed([
  'developer'
  'production'
])
param deploymentProfile string

var isProduction = deploymentProfile == 'production'
var suffix = uniqueString(subscription().id, resourceGroup().id, 'container-apps')
var registryName = take('${prefix}sharedca${suffix}', 50)
var logsName = take('${prefix}-shared-ca-logs-${suffix}', 63)
var environmentName = take('${prefix}-shared-cae-${suffix}', 60)
var runtimeIdentityName = take('${prefix}-shared-ca-pull-${suffix}', 128)
var sharedResourceTags = {
  application: 'delivery-demo'
  environment: 'shared'
  managedBy: 'bicep'
  profile: deploymentProfile
  strategy: 'canary'
}
var repositoryReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b93aa761-3e63-49ed-ac28-beffa264f7ac')
var repositoryWriterRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a1e307c-b015-4ebd-883e-5b7698a07328')

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

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: sharedResourceTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.outputs.customerId
        sharedKey: logs.outputs.primarySharedKey
      }
    }
    zoneRedundant: isProduction
  }
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: runtimeIdentityName
  location: location
  tags: sharedResourceTags
}

resource runtimePull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, runtimeIdentity.id, repositoryReaderRoleId)
  scope: acr
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: repositoryReaderRoleId
  }
  dependsOn: [registry]
}

resource infrastructurePush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, publisherPrincipalObjectId, repositoryWriterRoleId)
  scope: acr
  properties: {
    principalId: publisherPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: repositoryWriterRoleId
  }
  dependsOn: [registry]
}

resource applicationPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, deploymentPrincipalObjectId, repositoryWriterRoleId)
  scope: acr
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: repositoryWriterRoleId
  }
  dependsOn: [registry]
}

output acrName string = registry.outputs.name
output acrLoginServer string = registry.outputs.loginServer
output environmentId string = environment.id
output logAnalyticsWorkspaceId string = logs.outputs.id
output runtimeIdentityId string = runtimeIdentity.id
