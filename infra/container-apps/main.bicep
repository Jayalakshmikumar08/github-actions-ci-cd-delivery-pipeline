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
@description('Object ID of the Container Apps application-delivery identity.')
param deploymentPrincipalObjectId string
@description('Object ID of the infrastructure identity that publishes the first private image.')
param publisherPrincipalObjectId string
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

module foundation './foundation.bicep' = {
  name: 'container-apps-foundation-${stage}'
  scope: platformResourceGroup
  params: {
    prefix: prefix
    location: location
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    publisherPrincipalObjectId: publisherPrincipalObjectId
    deploymentProfile: deploymentProfile
  }
}

output acrName string = foundation.outputs.acrName
output acrLoginServer string = foundation.outputs.acrLoginServer
output resourceGroupName string = platformResourceGroup.name
output runtimeIdentityId string = foundation.outputs.runtimeIdentityId
output stage string = stage
