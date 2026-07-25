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
@description('Immutable image in the platform private ACR.')
param imageReference string
@minLength(40)
@maxLength(40)
param releaseSha string
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
  profile: deploymentProfile
  strategy: 'canary'
}

resource platformResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: resourceTags
}

module workload './workload.bicep' = {
  name: 'container-apps-workload-${stage}'
  scope: platformResourceGroup
  params: {
    prefix: prefix
    stage: stage
    location: location
    imageReference: imageReference
    releaseSha: releaseSha
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    deploymentProfile: deploymentProfile
  }
}

output containerAppName string = workload.outputs.containerAppName
output resourceGroupName string = platformResourceGroup.name
output stage string = stage
