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

// NSG
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: '${vmName}-nsg'
  location: resourceGroup().location
  properties: {
    securityRules: [
      {
        name: 'AllowFromMyIP'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '94.140.71.34'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 200
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// PostgreSQL Flexible Server
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
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Firewall rule
resource pgFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  name: '${pgServer.name}/AllowMyIP'
  properties: {
    startIpAddress: '94.140.71.34'
    endIpAddress: '94.140.71.34'
  }
  dependsOn: [
    pgServer
  ]
}

// Database
resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  name: '${pgServer.name}/${pgDbName}'
  properties: {}
  dependsOn: [
    pgServer
  ]
}

// Public IP
resource pip 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: '${vmName}-pip'
  location: resourceGroup().location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

// VNet
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: '${vmName}-vnet'
  location: resourceGroup().location
  dependsOn: [
    nsg
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// NIC
resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: resourceGroup().location
  dependsOn: [
    pip
    vnet
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'default')
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

// VM
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

// VM Extension
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  name: '${vm.name}/customScript'
  location: resourceGroup().location
  dependsOn: [
    vm
    pgDatabase
    pgFirewall
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