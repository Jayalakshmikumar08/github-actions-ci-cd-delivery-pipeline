targetScope = 'subscription'

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
param location string
param resourceGroupName string
param deploymentPrincipalObjectId string
@allowed([
  'developer'
  'production'
])
param deploymentProfile string = 'developer'

var resourceTags = {
  application: 'delivery-demo'
  environment: 'shared'
  managedBy: 'bicep'
  strategy: 'rolling'
}

resource stageResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: resourceTags
}

module platform './platform.bicep' = {
  name: 'aks-${stage}'
  scope: stageResourceGroup
  params: {
    prefix: prefix
    stage: stage
    location: location
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    deploymentProfile: deploymentProfile
  }
}

output acrName string = platform.outputs.acrName
output aksName string = platform.outputs.aksName
output resourceGroupName string = stageResourceGroup.name
output stage string = stage
