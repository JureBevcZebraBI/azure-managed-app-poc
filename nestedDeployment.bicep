param location string
param vmName string
param containerImage string
param pgConnectionString string
param registryServer string
param registryUsername string
@secure()
param registryPassword string

var publisherSubId = '51fe1c79-235d-42fc-b52f-b853dd080e58'
var publisherRgName = 'ZebraAIGeneral'
var keyVaultName = 'kv-zai-managed-app'
var secretName = 'TestSecret'

resource externalSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  name: '${keyVaultName}/${secretName}'
  scope: resourceGroup(publisherSubId, publisherRgName)
}

var publisherSecretValue = externalSecret.properties.value

var vmPayload = {
  containerImage: containerImage
  pgConnectionString: pgConnectionString
  registryServer: registryServer
  registryUsername: registryUsername
  registryPassword: registryPassword
  publisherSecret: publisherSecretValue
}

resource parentVm 'Microsoft.Compute/virtualMachines@2023-03-01' existing = {
  name: vmName
}

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: parentVm
  name: 'customScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    protectedSettings: {
      fileUris: [
        'https://raw.githubusercontent.com/JureBevcZebraBI/azure-managed-app-poc/main/setup.sh'
      ]
      commandToExecute: 'bash setup.sh ${base64(string(vmPayload))}'
    }
  }
}
