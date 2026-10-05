using './main.bicep'

param location = 'westeurope'
param stateResourceGroupName = 'rg-example-tfstate-weu'
param storageAccountName = 'stexampletfstate001'
param containerName = 'tfstate'
param storageSkuName = 'Standard_LRS'

// Replace with the trusted public egress IP range of the administrator or CI runner.
param allowedPublicIpCidrs = [
  '203.0.113.0/24'
]

// Use Disabled only after a private endpoint and private DNS path are available.
param publicNetworkAccess = 'Enabled'

// Use object IDs, never user names, access keys, or secrets.
param operatorPrincipalId = '00000000-0000-0000-0000-000000000000'
param pipelinePrincipalId = ''
