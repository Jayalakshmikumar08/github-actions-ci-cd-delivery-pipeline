param name string
param location string
param tags object
@minValue(-1)
param dailyQuotaGb int = -1

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
  }
}

output id string = workspace.id
output customerId string = workspace.properties.customerId
@secure()
output primarySharedKey string = workspace.listKeys().primarySharedKey
