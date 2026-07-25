targetScope = 'resourceGroup'

param identityName string
param location string
param githubOrganization string
param githubRepository string
@minLength(1)
@maxLength(20)
param githubEnvironments array

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    managedBy: 'bicep'
    purpose: 'github-actions-oidc'
  }
}

@batchSize(1)
resource federatedCredentials 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [
  for githubEnvironment in githubEnvironments: {
    parent: identity
    name: take('github-${githubEnvironment}-${uniqueString(githubEnvironment)}', 120)
    properties: {
      audiences: [
        'api://AzureADTokenExchange'
      ]
      issuer: 'https://token.actions.githubusercontent.com'
      subject: 'repo:${githubOrganization}/${githubRepository}:environment:${githubEnvironment}'
    }
  }
]

output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId
output resourceId string = identity.id
output subjects array = [
  for (githubEnvironment, index) in githubEnvironments: federatedCredentials[index].properties.subject
]
