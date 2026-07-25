targetScope = 'subscription'

@description('Name of the resource group that holds GitHub trust identities.')
param identityResourceGroupName string
param identityName string
param location string
param githubOrganization string
param githubRepository string
@minLength(1)
@maxLength(20)
@description('Exact GitHub Environment names that may obtain a token for this identity.')
param githubEnvironments array
@description('Grant subscription deployment roles. Use only for an infrastructure identity in a dedicated stage subscription.')
param grantInfrastructureDeploymentRoles bool = false
@description('Grant read-only subscription validation and what-if permissions without deployment write access.')
param grantPlanRoles bool = false

var contributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b24988ac-6180-42a0-ab88-20f7382dd24c'
)
var rbacAdministratorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
)
var planRoleDefinitionId = guid(subscription().id, 'github-plan-validate-what-if')

resource identityResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: identityResourceGroupName
  location: location
  tags: {
    managedBy: 'bicep'
    purpose: 'github-actions-trust'
  }
}

module oidcIdentity './oidc-identity.bicep' = {
  name: identityName
  scope: identityResourceGroup
  params: {
    identityName: identityName
    location: location
    githubOrganization: githubOrganization
    githubRepository: githubRepository
    githubEnvironments: githubEnvironments
  }
}

resource infrastructureContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantInfrastructureDeploymentRoles) {
  name: guid(subscription().id, identityResourceGroupName, identityName, contributorRoleId)
  properties: {
    principalId: oidcIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRoleId
  }
}

resource infrastructureRbacAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantInfrastructureDeploymentRoles) {
  name: guid(subscription().id, identityResourceGroupName, identityName, rbacAdministratorRoleId)
  properties: {
    principalId: oidcIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: rbacAdministratorRoleId
  }
}

resource planRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = if (grantPlanRoles) {
  name: planRoleDefinitionId
  properties: {
    roleName: 'GitHub Plan Validate and What-If'
    description: 'Read-only resource inspection plus ARM validation and what-if; cannot create deployments or resources.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          '*/read'
          'Microsoft.Resources/deployments/validate/action'
          'Microsoft.Resources/deployments/whatIf/action'
        ]
        notActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

resource planRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantPlanRoles) {
  name: guid(subscription().id, identityResourceGroupName, identityName, planRoleDefinitionId)
  properties: {
    principalId: oidcIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: planRoleDefinition.id
  }
}

output azureClientId string = oidcIdentity.outputs.clientId
output azurePrincipalObjectId string = oidcIdentity.outputs.principalId
output azureSubscriptionId string = subscription().subscriptionId
output azureTenantId string = tenant().tenantId
output federatedSubjects array = oidcIdentity.outputs.subjects
