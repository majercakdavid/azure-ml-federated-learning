// This BICEP script will create a custom RBAC role with write-only actions.

// resource group must be specified as scope in az cli or module call
targetScope = 'resourceGroup'

// Array of actions for the roleDefinition'
var singleDirectionWriteActions = [
  'Microsoft.Storage/storageAccounts/blobServices/containers/read'
]
var singleDirectionWriteDataActions = [
  'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
  //'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action',
  'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'
]

// Array of notActions for the roleDefinition
var singleDirectionWriteNotActions = [
  'Microsoft.Storage/storageAccounts/blobServices/containers/delete'
  //'Microsoft.Storage/storageAccounts/blobServices/containers/write'
]
var singleDirectionWriteNotDataActions = [
  'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'
  'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'
]

// get a guid
var sinlgleDirectionWriteRoleDefName = guid(
  subscription().id,
  string(singleDirectionWriteActions),
  string(singleDirectionWriteDataActions),
  string(singleDirectionWriteNotActions),
  string(singleDirectionWriteNotDataActions)
)

resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: sinlgleDirectionWriteRoleDefName
  // scope: resourceGroup()
  properties: {
    roleName: 'FL Demo - Single Direction Write'
    description: 'Can write+delete a blob into a storage container, but not read.'
    type: 'customRole'
    permissions: [
      {
        actions: singleDirectionWriteActions
        notActions: singleDirectionWriteNotActions
        dataActions: singleDirectionWriteDataActions
        notDataActions: singleDirectionWriteNotDataActions
      }
    ]
    assignableScopes: [
      // NOTE: restricting this role to the resource group
      resourceGroup().id
    ]
  }
}

// return role id
output roleDefinitionId string = roleDefinition.id
