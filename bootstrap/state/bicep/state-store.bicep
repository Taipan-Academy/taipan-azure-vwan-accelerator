@description('Azure region for the state storage account.')
param location string

@description('Globally unique StorageV2 account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Private blob container that holds Terraform state files.')
param containerName string

@allowed([
  'Standard_LRS'
  'Standard_ZRS'
])
param storageSkuName string

@description('Allowed public egress IP CIDRs for POC or administrator access.')
param allowedPublicIpCidrs array

@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string

@description('Optional Entra object ID for the Terraform operator or administrator.')
param operatorPrincipalId string

@description('Optional Entra object ID for the CI/CD workload identity or managed identity.')
param pipelinePrincipalId string

var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource stateStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: publicNetworkAccess
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [for cidr in allowedPublicIpCidrs: {
        action: 'Allow'
        value: cidr
      }]
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: stateStorage
  name: 'default'
  properties: {
    changeFeed: {
      enabled: true
    }
    containerDeleteRetentionPolicy: {
      days: 30
      enabled: true
    }
    deleteRetentionPolicy: {
      days: 30
      enabled: true
    }
    isVersioningEnabled: true
  }
}

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

resource operatorStateRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(operatorPrincipalId)) {
  scope: stateStorage
  name: guid(stateStorage.id, operatorPrincipalId, storageBlobDataContributorRoleDefinitionId)
  properties: {
    principalId: operatorPrincipalId
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
  }
}

resource pipelineStateRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(pipelinePrincipalId)) {
  scope: stateStorage
  name: guid(stateStorage.id, pipelinePrincipalId, storageBlobDataContributorRoleDefinitionId)
  properties: {
    principalId: pipelinePrincipalId
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
  }
}

output backendStorageAccountName string = stateStorage.name
output backendContainerName string = stateContainer.name
