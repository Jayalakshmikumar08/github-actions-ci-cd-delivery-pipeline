param name string
param location string
param logAnalyticsWorkspaceId string
param tags object
@allowed([
  'Basic'
  'Standard'
])
param skuName string
param enableDiagnostics bool

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    roleAssignmentMode: 'AbacRepositoryPermissions'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'send-to-log-analytics'
  scope: registry
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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

output id string = registry.id
output loginServer string = registry.properties.loginServer
output name string = registry.name
