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
param imageReference string
@minLength(40)
@maxLength(40)
param releaseSha string
param deploymentPrincipalObjectId string
@allowed([
  'developer'
  'production'
])
param deploymentProfile string

var isProduction = deploymentProfile == 'production'
var suffix = uniqueString(subscription().id, resourceGroup().id, 'app-service')
var registryName = take('${prefix}sharedbg${suffix}', 50)
var logsName = take('${prefix}-shared-bg-logs-${suffix}', 63)
var planName = take('${prefix}-shared-asp-${suffix}', 40)
var runtimeIdentityName = take('${prefix}-shared-bg-pull-${suffix}', 128)
var appName = take('${prefix}-${stage}-web-${suffix}', 60)
var stageResourceTags = {
  application: 'delivery-demo'
  environment: stage
  managedBy: 'bicep'
  profile: deploymentProfile
  strategy: 'blue-green'
}
var websiteContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' existing = {
  name: planName
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logsName
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: runtimeIdentityName
}

var appSettings = [
  {
    name: 'PORT'
    value: '8080'
  }
  {
    name: 'WEBSITES_PORT'
    value: '8080'
  }
  {
    name: 'RELEASE_SHA'
    value: releaseSha
  }
  {
    name: 'DEPLOYMENT_STRATEGY'
    value: 'blue-green'
  }
  {
    name: 'DEPLOYMENT_STAGE'
    value: stage
  }
  {
    name: 'WEBSITE_HEALTHCHECK_MAXPINGFAILURES'
    value: '3'
  }
  {
    name: 'WEBSITE_ADD_SITENAME_BINDINGS_IN_APPHOST_CONFIG'
    value: '1'
  }
]

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: stageResourceTags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentity.id}': {}
    }
  }
  properties: {
    clientAffinityEnabled: false
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: plan.id
    siteConfig: {
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: runtimeIdentity.properties.clientId
      alwaysOn: true
      appSettings: appSettings
      ftpsState: 'Disabled'
      healthCheckPath: '/health/ready'
      http20Enabled: true
      linuxFxVersion: 'DOCKER|${imageReference}'
      minTlsVersion: '1.2'
    }
  }
}

resource staging 'Microsoft.Web/sites/slots@2024-04-01' = {
  parent: app
  name: 'staging'
  location: location
  tags: stageResourceTags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentity.id}': {}
    }
  }
  properties: {
    clientAffinityEnabled: false
    httpsOnly: true
    serverFarmId: plan.id
    siteConfig: {
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: runtimeIdentity.properties.clientId
      alwaysOn: true
      appSettings: appSettings
      ftpsState: 'Disabled'
      healthCheckPath: '/health/ready'
      http20Enabled: true
      linuxFxVersion: 'DOCKER|${imageReference}'
      minTlsVersion: '1.2'
    }
  }
}

resource pipelineDeploy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, deploymentPrincipalObjectId, websiteContributorRoleId)
  scope: app
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: websiteContributorRoleId
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (isProduction) {
  name: 'send-to-log-analytics'
  scope: app
  properties: {
    workspaceId: logs.id
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

output appServiceName string = app.name
output acrName string = acr.name
output stage string = stage
