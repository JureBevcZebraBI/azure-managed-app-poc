param vmName string = 'docker-vm'
param adminUsername string
@secure()
param adminPassword string

param containerImage string
param registryServer string
param registryUsername string
@secure()
param registryPassword string

var pgServerName = '${vmName}-pg'
var pgDbName = 'appdb'
var pgAdminUser = 'pgadmin'
var pgAdminPassword = adminPassword

var pgConnectionString = 'postgresql+psycopg://${pgAdminUser}:${pgAdminPassword}@${pgServerName}.postgres.database.azure.com:5432/${pgDbName}?sslmode=require'

/* -----------------------
   NSG
------------------------*/
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: '${vmName}-nsg'
  location: resourceGroup().location
}

/* -----------------------
   VNET
------------------------*/
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: '${vmName}-vnet'
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'pg-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'pgDelegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

/* -----------------------
   PRIVATE DNS (FIXED API VERSION)
------------------------*/
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: '${vmName}-dns-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

/* -----------------------
   POSTGRESQL (PRIVATE ONLY)
------------------------*/
resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: pgServerName
  location: resourceGroup().location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: pgAdminUser
    administratorLoginPassword: pgAdminPassword
    version: '15'
    storage: {
      storageSizeGB: 32
    }
    network: {
      publicNetworkAccess: 'Disabled'
      delegatedSubnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'pg-subnet')
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
  }
  dependsOn: [
    vnet
    privateDnsZone
  ]
}

/* DNS zone group */
resource pgDnsZoneGroup 'Microsoft.DBforPostgreSQL/flexibleServers/privateDnsZoneGroups@2023-06-01-preview' = {
  name: '${pgServer.name}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    pgServer
  ]
}

/* -----------------------
   DATABASE
------------------------*/
resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  name: '${pgServer.name}/${pgDbName}'
  properties: {}
  dependsOn: [
    pgServer
  ]
}

/* -----------------------
   VM (NO PUBLIC IP)
------------------------*/
resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'vm-subnet')
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
  dependsOn: [
    nic
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

/* -----------------------
   VM EXTENSION
------------------------*/
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  name: '${vm.name}/customScript'
  location: resourceGroup().location
  dependsOn: [
    vm
    pgDatabase
  ]
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/JureBevcZebraBI/azure-managed-app-poc/refs/heads/main/setup.sh'
      ]
      commandToExecute: 'bash setup.sh ${base64(containerImage)} ${base64(pgConnectionString)} ${base64(registryServer)} ${base64(registryUsername)} ${base64(registryPassword)}'
    }
  }
}
