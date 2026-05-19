param vmName string = 'docker-vm'
param adminUsername string

@secure()
param adminPassword string

param containerImage string
param registryServer string
param registryUsername string

@secure()
param registryPassword string

// =========================
// Names
// =========================

var location = resourceGroup().location

var vnetName = '${vmName}-vnet'
var vmSubnetName = 'vm-subnet'
var dbSubnetName = 'db-subnet'

var pgServerName = toLower('${vmName}pg')
var pgDbName = 'appdb'

var pgAdminUser = 'pgadmin'
var pgAdminPassword = adminPassword

// IMPORTANT:
// With private DNS enabled, this hostname resolves privately inside VNet
var pgHost = '${pgServerName}.postgres.database.azure.com'

var pgConnectionString = 'postgresql+psycopg://${pgAdminUser}:${pgAdminPassword}@${pgHost}:5432/${pgDbName}?sslmode=require'

// =========================
// Network Security Group
// =========================

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

// =========================
// Virtual Network
// =========================

resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }

    subnets: [
      {
        name: vmSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }

      {
        name: dbSubnetName
        properties: {
          addressPrefix: '10.0.2.0/24'

          delegations: [
            {
              name: 'postgresDelegation'
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

// =========================
// Private DNS Zone
// =========================

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZone.name}/${vmName}-dnslink'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// =========================
// PostgreSQL Flexible Server
// =========================

resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: pgServerName
  location: location

  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }

  properties: {
    version: '15'

    administratorLogin: pgAdminUser
    administratorLoginPassword: pgAdminPassword

    storage: {
      storageSizeGB: 32
    }

    network: {
      delegatedSubnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, dbSubnetName)

      privateDnsZoneArmResourceId: privateDnsZone.id

      publicNetworkAccess: 'Disabled'
    }
  }

  dependsOn: [
    dnsLink
  ]
}

// =========================
// PostgreSQL Database
// =========================

resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  name: '${pgServer.name}/${pgDbName}'
}

// =========================
// Public IP (for SSH only)
// =========================

resource pip 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: '${vmName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// =========================
// NIC
// =========================

resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: location

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, vmSubnetName)
          }

          privateIPAllocationMethod: 'Dynamic'

          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

// =========================
// Virtual Machine
// =========================

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location

  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }

    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword

      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
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

// =========================
// VM Setup Payload
// =========================

var vmPayload = {
  containerImage: containerImage
  pgConnectionString: pgConnectionString
  registryServer: registryServer
  registryUsername: registryUsername
  registryPassword: registryPassword
}

// =========================
// Custom Script Extension
// =========================

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  name: '${vm.name}/customScript'
  location: location

  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'

    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/JureBevcZebraBI/azure-managed-app-poc/main/setup.sh'
      ]

      commandToExecute: 'bash setup.sh ${base64(string(vmPayload))}'
    }
  }

  dependsOn: [
    vm
    pgDatabase
  ]
}

// =========================
// Outputs
// =========================

output vmPublicIp string = pip.properties.ipAddress
output postgresHost string = pgHost
