// This BICEP script will fully provision a functional federated learning sandbox
// based on simple internal silos secured with only UAI.

// IMPORTANT: This setup is intended only for demo purpose. The data is still accessible
// by the users when opening the storage accounts, and data exfiltration is easy.

// For a given set of regions, it will provision:
// - an AzureML workspace and compute cluster for orchestration
// - per region, a silo (1 storage with 1 dedicated containers, 1 compute, 1 UAI)

// The demo permission model is represented by the following matrix:
// |               | orch.compute | siloA.compute | siloB.compute |
// |---------------|--------------|---------------|---------------|
// | orch.storage  |     R/W      |      R/W      |      R/W      |
// | siloA.storage |      -       |      R/W      |       -       |
// | siloB.storage |      -       |       -       |      R/W      |

// Usage (sh):
// > az login
// > az account set --name <subscription name>
// > az group create --name <resource group name> --location <region>
// > az deployment group create --template-file .\mlops\bicep\vanilla_demo_setup.bicep \
//                              --resource-group <resource group name \
//                              --parameters demoBaseName="fldemo"

targetScope = 'resourceGroup'

// please specify the base name for all resources
@description('Base name of the demo, used for creating all resources as prefix')
param demoBaseName string = 'fldemo'

// below parameters are optionals and have default values
@description('Location of the orchestrator (workspace, central storage and compute).')
param orchestratorRegion string = resourceGroup().location

@description('List of each region in which to create an internal silo.')
param siloRegions array = ['westus', 'westus2', 'eastus2']

@description('The VM used for creating compute clusters in orchestrator and silos.')
param computeSKU string = 'Standard_DS13_v2'

@description('Tags to curate the resources in Azure.')
param tags object = {
  Owner: 'AzureML Samples'
  Project: 'azure-ml-federated-learning'
  Environment: 'dev'
  Toolkit: 'bicep'
  Docs: 'https://github.com/Azure-Samples/azure-ml-federated-learning'
}

module storageReadWriteRoleDeployment './modules/roles/role_storage_read_write.bicep' = {
  name: guid(subscription().subscriptionId, 'role_storage_read_write', demoBaseName)
  scope: subscription()
}

// Create Azure Machine Learning workspace for orchestration
// with an orchestration compute
module orchestratorDeployment './modules/orchestrators/orchestrator_open.bicep' = {
  name: '${demoBaseName}-deployorchestrator-${orchestratorRegion}'
  scope: resourceGroup()
  params: {
    machineLearningName: 'aml-${demoBaseName}'
    location: orchestratorRegion
    tags: tags

    orchestratorComputeName: 'cpu-cluster-orchestrator'
    orchestratorComputeSKU: computeSKU

    // RBAC role of orch compute -> orch storage
    orchToOrchRoleDefinitionId: storageReadWriteRoleDeployment.outputs.roleDefinitionId
  }
}

var siloCount = length(siloRegions)

// Create all vanilla silos using a provided bicep module
module siloDeployments './modules/silos/internal_blob_open.bicep' = [for i in range(0, siloCount): {
  name: '${demoBaseName}-deploysilo-${i}-${siloRegions[i]}'
  scope: resourceGroup()
  params: {
    siloBaseName: '${demoBaseName}-silo${i}-${siloRegions[i]}'
    workspaceName: 'aml-${demoBaseName}'
    region: siloRegions[i]
    tags: tags

    computeClusterName: 'cpu-silo${i}-${siloRegions[i]}'
    siloComputeSKU: computeSKU
    siloDatastoreName: 'datastore_silo${i}_${siloRegions[i]}'

    // reference of the orchestrator to set permissions
    orchestratorStorageAccountName: orchestratorDeployment.outputs.storage

    // RBAC role of silo compute -> silo storage
     // Storage Blob Data Contributor (read,write,delete)
    siloToSiloRoleDefinitionId: storageReadWriteRoleDeployment.outputs.roleDefinitionId

    // RBAC role of silo compute -> orch storage (to r/w model weights)
     // Storage Blob Data Contributor (read,write,delete)
    siloToOrchRoleDefinitionId: storageReadWriteRoleDeployment.outputs.roleDefinitionId
  }
  // scope: resourceGroup
  dependsOn: [
    orchestratorDeployment
  ]
}]