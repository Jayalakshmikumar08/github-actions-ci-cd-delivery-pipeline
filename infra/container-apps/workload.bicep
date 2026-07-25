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
var suffix = uniqueString(subscription().id, resourceGroup().id, 'container-apps')
var registryName = take('${prefix}sharedca${suffix}', 50)
var logsName = take('${prefix}-shared-ca-logs-${suffix}', 63)
var environmentName = take('${prefix}-shared-cae-${suffix}', 60)
var runtimeIdentityName = take('${prefix}-shared-ca-pull-${suffix}', 128)
var appName = take('${prefix}-${stage}-ca-${suffix}', 32)
var stageResourceTags = {
  application: 'delivery-demo'
  environment: stage
  managedBy: 'bicep'
  profile: deploymentProfile
  strategy: 'canary'
}
var containerAppsContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '358470bc-b998-42bd-ab17-a7e34c199c0f')
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logsName
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: runtimeIdentityName
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: stageResourceTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentity.id}': {}
    }
  }
  properties: {
    environmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Multiple'
      ingress: {
        allowInsecure: false
        external: true
        targetPort: 8080
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        transport: 'auto'
      }
      registries: [
        {
          identity: runtimeIdentity.id
          server: acr.properties.loginServer
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'application'
          image: imageReference
          env: [
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'RELEASE_SHA'
              value: releaseSha
            }
            {
              name: 'DEPLOYMENT_STRATEGY'
              value: 'canary'
            }
            {
              name: 'DEPLOYMENT_STAGE'
              value: stage
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health/live'
                port: 8080
              }
              failureThreshold: 30
              periodSeconds: 2
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/ready'
                port: 8080
              }
              failureThreshold: 3
              periodSeconds: 5
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 8080
              }
              failureThreshold: 3
              periodSeconds: 10
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: isProduction ? (stage == 'prod' ? 2 : 1) : 0
        maxReplicas: isProduction && stage == 'prod' ? 5 : 2
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

resource pipelineDeploy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, deploymentPrincipalObjectId, containerAppsContributorRoleId)
  scope: app
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: containerAppsContributorRoleId
  }
}

resource pipelineMonitor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, deploymentPrincipalObjectId, monitoringReaderRoleId)
  scope: app
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringReaderRoleId
  }
}

output containerAppName string = app.name
output logAnalyticsWorkspaceId string = logs.id
output stage string = stage
