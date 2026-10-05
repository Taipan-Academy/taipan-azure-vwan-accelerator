targetScope = 'subscription'

@description('Azure region for the dedicated Terraform-state resource group and storage account.')
param location string

@description('Dedicated resource group for Terraform state. Do not place workload resources in this group.')
param stateResourceGroupName string

@description('Globally unique StorageV2 account name, 3-24 lowercase alphanumeric characters.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Private blob container that holds Terraform state files.')
param containerName string = 'tfstate'

@description('Storage redundancy for the state account.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
])
param storageSkuName string = 'Standard_LRS'

@description('Allowed public egress IP CIDRs for POC or administrator access. Keep empty only when publicNetworkAccess is Disabled and a private endpoint is used.')
param allowedPublicIpCidrs array = []

@description('Set Disabled for private-endpoint-only production state access.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Optional Entra object ID for the Terraform operator or administrator.')
param operatorPrincipalId string = ''

@description('Optional Entra object ID for the CI/CD workload identity or managed identity.')
param pipelinePrincipalId string = ''

resource stateResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: stateResourceGroupName
  location: location
  tags: {
    purpose: 'terraform-state'
    managed_by: 'taipan-azure-vwan-accelerator'
  }
}

module stateStore './state-store.bicep' = {
  name: 'terraform-state-store'
  scope: stateResourceGroup
  params: {
    location: location
    storageAccountName: storageAccountName
    containerName: containerName
    storageSkuName: storageSkuName
    allowedPublicIpCidrs: allowedPublicIpCidrs
    publicNetworkAccess: publicNetworkAccess
    operatorPrincipalId: operatorPrincipalId
    pipelinePrincipalId: pipelinePrincipalId
  }
}

output backendResourceGroupName string = stateResourceGroup.name
output backendStorageAccountName string = stateStore.outputs.backendStorageAccountName
output backendContainerName string = stateStore.outputs.backendContainerName
output backendUseAzureAdAuth bool = true
