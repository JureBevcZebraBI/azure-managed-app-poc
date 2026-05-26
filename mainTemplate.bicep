param vmName string = 'docker-vm'
param adminUsername string

@secure()
param adminPassword string

param containerImage string
param registryServer string
param registryUsername string

@secure()
param registryPassword string

var location = resourceGroup().location
var vnetName = '${vmName}-vnet'
var vmSubnetName = 'vm-subnet'
var dbSubnetName = 'db-subnet'
var pgServerName = toLower('${vmName}pg')
var pgDbName = 'appdb'
var pgAdminUser = 'pgadmin'
var pgAdminPassword = adminPassword
var pgHost = '${pgServerName}.postgres.database.azure.com'
var pgConnectionString = 'postgresql+psycopg://${pgAdminUser}:${pgAdminPassword}@${pgHost}:5432/${pgDbName}?sslmode=require'

// Publisher Key Vault Target Details
var publisherSubId = '51fe1c79-235d-42fc-b52f-b853dd080e58'
var publisherRgName = 'ZebraAIGeneral'
var keyVaultName = 'kv-zai-managed-app'
var secretName = 'TestSecret'

// ==========================================
// Infrastructure Resources
// ==========================================
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      { name: vmSubnetName, properties: { addressPrefix: '10.0.1.0/24', networkSecurityGroup: { id: nsg.id } } }
      {
        name: dbSubnetName
        properties: {
          addressPrefix: '10.0.2.0/24'
          delegations: [
            { name: 'postgresDelegation', properties: { serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers' } }
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZone.name}/${vmName}-dnslink'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }, registrationEnabled: false }
}

resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: pgServerName
  location: location
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '15'
    administratorLogin: pgAdminUser
    administratorLoginPassword: pgAdminPassword
    storage: { storageSizeGB: 32 }
    network: {
      delegatedSubnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, dbSubnetName)
      privateDnsZoneArmResourceId: privateDnsZone.id
      publicNetworkAccess: 'Disabled'
    }
  }
  dependsOn: [dnsLink]
}

resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  name: '${pgServer.name}/${pgDbName}'
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: '${vmName}-pip'
  location: location
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, vmSubnetName) }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: { disablePasswordAuthentication: false }
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: 'latest' }
      osDisk: { createOption: 'FromImage' }
    }
    networkProfile: { networkInterfaces: [{ id: nic.id }] }
  }
}

// ==========================================================
// THE FIXED NESTED DEPLOYMENT RESOURCE 
// ==========================================================
resource dynamicSecretDeployment 'Microsoft.Resources/deployments@2022-09-01' = {
  name: 'nestedSecretFetchDeployment'
  properties: {
    mode: 'Incremental'
    expressionEvaluationOptions: {
      scope: 'inner'
    }
    parameters: {
      location: { value: location }
      vmName: { value: vmName }
      containerImage: { value: containerImage }
      pgConnectionString: { value: pgConnectionString }
      registryServer: { value: registryServer }
      registryUsername: { value: registryUsername }
      registryPassword: { value: registryPassword }

      // The Engine-Level Reference Object that bypasses cross-subscription RBAC blocks
      publisherSecretValue: {
        reference: {
          keyVault: {
            id: resourceId(publisherSubId, publisherRgName, 'Microsoft.KeyVault/vaults', keyVaultName)
          }
          secretName: secretName
        }
      }
    }
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        location: { type: 'string' }
        vmName: { type: 'string' }
        containerImage: { type: 'string' }
        pgConnectionString: { type: 'string' }
        registryServer: { type: 'string' }
        registryUsername: { type: 'string' }
        registryPassword: { type: 'securestring' }
        publisherSecretValue: { type: 'securestring' }
      }
      variables: {
        // Constructing the payload object here keeps the execution block highly compact
        vmPayload: {
          containerImage: '[parameters(\'containerImage\')]'
          pgConnectionString: '[parameters(\'pgConnectionString\')]'
          registryServer: '[parameters(\'registryServer\')]'
          registryUsername: '[parameters(\'registryUsername\')]'
          registryPassword: '[parameters(\'registryPassword\')]'
          publisherSecret: '[parameters(\'publisherSecretValue\')]'
        }
      }
      resources: [
        {
          type: 'Microsoft.Compute/virtualMachines/extensions'
          apiVersion: '2023-03-01'
          name: '[concat(parameters(\'vmName\'), \'/customScript\')]'
          location: '[parameters(\'location\')]'
          properties: {
            publisher: 'Microsoft.Azure.Extensions'
            type: 'CustomScript'
            typeHandlerVersion: '2.1'
            protectedSettings: {
              fileUris: [
                'https://raw.githubusercontent.com/JureBevcZebraBI/azure-managed-app-poc/main/setup.sh'
              ]
              commandToExecute: '[concat(\'bash setup.sh \', base64(string(variables(\'vmPayload\'))))]'
            }
          }
        }
      ]
    }
  }
  dependsOn: [
    vm
    pgDatabase
  ]
}

output vmPublicIp string = pip.properties.ipAddress
output postgresHost string = pgHost
