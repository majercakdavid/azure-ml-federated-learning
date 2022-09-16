
# 0. Extract setup information, load dependencies, set subscription, created managed identity for the orchestrator compute
# 0.a Read the YAML file
[string[]]$fileContent = Get-Content "./YAML/setup_info.yml"
$content = ''
foreach ($line in $fileContent) { $content = $content + "`n" + $line }
$yaml = ConvertFrom-YAML $content
# 0.b Collect the values from the YAML file
$SubscriptionId = $yaml['subscription_id']
$WorkspaceName = $yaml['workspace']['name']
$WorkspaceResourceGroup = $yaml['workspace']['resource_group']
$WorkspaceRegion = $yaml['workspace']['region']
$OrchestratorComputeName = $yaml['workspace']['orchestrator_compute_name']
$Silos = $yaml['silos']
$NumSilos = $Silos.Count
# 0.c Some "global" variables
$SiloComputeNamePrefix = "cpu-"
$SharingContainerName = 'sharing'
# 0.d Load useful functions
. "$PSScriptRoot/../../external_silos/ps/AzureUtilities.ps1"
# 0.e Log in and make sure we're in the right subscription
az login --output none
az account set --subscription $SubscriptionId
# 0.f create a user-assigned managed identity for the orchestrator compute if it does not exist already
$OrchestratorIdentityName = $OrchestratorComputeName + "-identity"
$MatchingIdentities = az identity list --resource-group $WorkspaceResourceGroup --query "[?name=='$OrchestratorIdentityName']"  | ConvertFrom-Json
if ($MatchingIdentities.Length -eq 0){
    Write-Output "Creating user-assigned identity '$OrchestratorIdentityName'..."
    az identity create --name $OrchestratorIdentityName --resource-group $WorkspaceResourceGroup --location $WorkspaceRegion --subscription $SubscriptionId
}
else {
    Write-Output "Identity '$OrchestratorIdentityName' already exists."
}


# SECURE SILOS
$SiloIndex = 1
foreach ($Silo in $Silos)
{
    $SiloName = $Silo['name']
    $SiloRegion = $Silo['region']
    $SiloInputStorageAccount = $Silo['storage_account']
    $SiloContainer = $Silo['container']
    $SiloDatastoreName = $SiloName.replace('-', '') + "ds"
    Write-Output "Securing silo '$SiloName'..."

    # 1. create silo input datastore if it does not exist already
    $MatchingSiloDatastores = az ml datastore list --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --query "[?name=='$SiloDatastoreName']"  | ConvertFrom-Json
    if ($MatchingSiloDatastores.Length -eq 0){
        Write-Output "Creating silo input datastore '$SiloDatastoreName'..."
        # 1.1 build the definition in YAML 
        $DatastoreYAML="`$schema: https://azuremlschemas.azureedge.net/latest/azureBlob.schema.json
name: $SiloDatastoreName
type: azure_blob
description: Credential-less datastore pointing to a blob container.
account_name: $SiloInputStorageAccount
container_name: $SiloContainer"
        # 1.2 write the YAML
        $DatastoreYAML | Out-File -FilePath ./datastore.yml
        # 1.3 use the CLI to create the datastore
        az ml datastore create --file datastore.yml --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName
        # 1.4 delete the temporary YAML file
        Remove-Item -Path ./datastore.yml
    }
    else {
        Write-Output "Silo input datastore '$SiloDatastoreName' already exists."
    }
    
    # 2. create data assets if they don't exist already
    # 2.a. Training
    $TrainingDatasetName = "mnist-train-$SiloRegion"
    $MatchingTrainingDatasets = az ml data list --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --query "[?name=='$TrainingDatasetName']"  | ConvertFrom-Json
    if ($MatchingTrainingDatasets.Length -eq 0){
        Write-Output "Creating training data asset '$TrainingDatasetName'..."
        # 2.a.1 build the definitions in YAML
        $TrainingDataYAML="`$schema: https://azuremlschemas.azureedge.net/latest/data.schema.json
name: $TrainingDatasetName
description: Data asset created from file in cloud.
type: uri_file
path: azureml://datastores/$SiloDatastoreName/paths/train.csv" # adjust path and type accordingly
        # 2.a.2 write the YAML's into 2 files
        $TrainingDataYAML | Out-File -FilePath ./mnist_train.yml
        # 2.a.3 use the CLI to create the data assets
        az ml data create --file ./mnist_train.yml --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --subscription $SubscriptionId
        # 2.a.4 and finally we delete the temporary files
        Remove-Item -Path ./mnist_train.yml
    }
    else {
        Write-Output "Training data asset '$TrainingDatasetName' already exists."
    }
    # 2.b. Test
    $TestDatasetName = "mnist-test-$SiloRegion"
    $MatchingTestDatasets = az ml data list --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --query "[?name=='$TestDatasetName']"  | ConvertFrom-Json
    if ($MatchingTestDatasets.Length -eq 0){
        Write-Output "Creating test data asset '$TestDatasetName'..."
        # 2.b.1 build the definitions in YAML
        $TestDataYAML="`$schema: https://azuremlschemas.azureedge.net/latest/data.schema.json
name: $TestDatasetName
description: Data asset created from file in cloud.
type: uri_file
path: azureml://datastores/$SiloDatastoreName/paths/t10k.csv" # adjust path and type accordingly
        # 2.b.2 write the YAML's into 2 files
        $TestDataYAML | Out-File -FilePath ./mnist_test.yml
        # 2.b.3 use the CLI to create the data assets
        az ml data create --file ./mnist_test.yml --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --subscription $SubscriptionId
        # 2.b.4 and finally we delete the temporary files
        Remove-Item -Path ./mnist_test.yml
    }
    else {
        Write-Output "Training data asset '$TestDatasetName' already exists."
    }
    
    # 3. create a user-assigned managed identity if it does not exist already
    $SiloIdentityName = $SiloName + "-identity"
    $MatchingIdentities = az identity list --resource-group $WorkspaceResourceGroup --query "[?name=='$SiloIdentityName']"  | ConvertFrom-Json
    if ($MatchingIdentities.Length -eq 0){
        Write-Output "Creating user-assigned identity '$SiloIdentityName'..."
        az identity create --name $SiloIdentityName --resource-group $WorkspaceResourceGroup --location $SiloRegion --subscription $SubscriptionId
    }
    else {
        Write-Output "Identity '$SiloIdentityName' already exists."
    }
    
    # 4. give managed identity to the silo compute, if it does not have it already
    $SiloComputeName = $SiloComputeNamePrefix + $SiloName
    $IdentityResourceId = "/subscriptions/$SubscriptionId/resourcegroups/$WorkspaceResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$SiloIdentityName"
    $Compute = az ml compute show --name $SiloComputeName --resource-group $WorkspaceResourceGroup --workspace $WorkspaceName | ConvertFrom-Json
    if ($Compute.identity.user_assigned_identities.resource_id -contains $IdentityResourceId){
        Write-Output "The silo compute '$SiloComputeName' has already been given the user-assigned identity '$SiloIdentityName'."
    }
    else{
        Write-Output "Giving the user-assigned identity '$SiloIdentityName' to silo compute '$SiloComputeName'..."
        az ml compute update --name $SiloComputeName --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --identity-type UserAssigned --user-assigned-identities $IdentityResourceId --subscription $SubscriptionId
    }

    # 5. create a "sharing" storage account if it does not exist already and if the inferred name is valid; inside it, create a sharing container
    $SiloSharingStorageAccountName = $SiloName.replace('-', '') + "sharingstacc"
    $NameCheck = az storage account check-name --name $SiloSharingStorageAccountName --subscription $SubscriptionId | ConvertFrom-Json
    $Message = $NameCheck.message
    $NameAvailable = $NameCheck.nameAvailable
    $Reason = $NameCheck.reason
    if ($NameAvailable -eq $true){
        Write-Output "Creating sharing storage account '$SiloSharingStorageAccountName'..."
        az storage account create --name $SiloSharingStorageAccountName --resource-group $WorkspaceResourceGroup --location $WorkspaceRegion --sku Standard_LRS --subscription $SubscriptionId --access-tier Hot --allow-blob-public-access false
        az storage container create -n $SharingContainerName --account-name $SiloSharingStorageAccountName --subscription $SubscriptionId
    }
    else {
        if ($Reason -eq "AlreadyExists"){
            Write-Output "Sharing storage account '$SiloSharingStorageAccountName' already exists. Not creating a new one."
        }
        else {
            Write-Output "Sharing storage account name '$SiloSharingStorageAccountName' is not valid. $Message"
        }
    }

    # 6. create a "sharing" datastore if it does not exist already
    $SharingDatastoreName = $SiloName.replace('-', '') + "sharing"
    $MatchingSharingDatastores = az ml datastore list --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --query "[?name=='$SharingDatastoreName']"  | ConvertFrom-Json
    if ($MatchingSharingDatastores.Length -eq 0){
        Write-Output "Creating sharing silo datastore '$SiloDatastoreName'..."
        # 6.1 build the definition in YAML 
        $DatastoreYAML="`$schema: https://azuremlschemas.azureedge.net/latest/azureBlob.schema.json
name: $SharingDatastoreName
type: azure_blob
description: Credential-less datastore pointing to a blob container.
account_name: $SiloSharingStorageAccountName
container_name: $SharingContainerName"
        # 6.2 write the YAML
        $DatastoreYAML | Out-File -FilePath ./datastore.yml
        # 6.3 use the CLI to create the datastore
        az ml datastore create --file datastore.yml --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName
        # 6.4 delete the temporary YAML file
        Remove-Item -Path ./datastore.yml
    }
    else {
        Write-Output "Silo sharing datastore '$SharingDatastoreName' already exists."
    }

    # 7. give the silo and orchestrator compute identities write access to the sharing datastore
    Write-Output "Giving the silo identity '$SiloIdentityName' and orchestrator identity '$OrchestratorIdentityName' write access to the sharing storage account '$SiloSharingStorageAccountName'..."
    # 7.1 let's get the silo's and orchestrator's identities' Principal ID's (needed to create the role assignments)
    $Identity = az identity list --resource-group $WorkspaceResourceGroup --query "[?name=='$SiloIdentityName']" | ConvertFrom-Json
    $PrincipalId = $Identity.principalId
    $Identity_Orchestrator = az identity list --resource-group $WorkspaceResourceGroup --query "[?name=='$OrchestratorIdentityName']" | ConvertFrom-Json
    $PrincipalId_Orchestrator = $Identity_Orchestrator.principalId
    # 7.2 build the resource ID of the storage account (also needed to create the role assignment)
    $StorageAccountResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$WorkspaceResourceGroup/providers/Microsoft.Storage/storageAccounts/$SiloSharingStorageAccountName"
    # 7.3 actually create the role assignments
    az role assignment create --role "Storage Blob Data Contributor" --scope $StorageAccountResourceId --assignee-object-id $PrincipalId --subscription $SubscriptionId
    az role assignment create --role "Storage Blob Data Contributor" --scope $StorageAccountResourceId --assignee-object-id $PrincipalId_Orchestrator --subscription $SubscriptionId

    # Increment the silo index to keep it accurate
    Write-Output "Done securing silo '$SiloName'."
    Write-Output ""
    $SiloIndex=$SiloIndex+1
}