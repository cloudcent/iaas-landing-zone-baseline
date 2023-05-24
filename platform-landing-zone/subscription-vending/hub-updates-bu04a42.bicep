targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The existing application landing zone network to which this regional hub will peer to. In this deployment guide it\'s assumed to be in the same subscription, but in reality would be in the landing zone subscription')
@minLength(79)
param spokeVirtualNetworkResourceId string

@allowed([
  'australiaeast'
  'canadacentral'
  'centralus'
  'eastus'
  'eastus2'
  'westus2'
  'francecentral'
  'germanywestcentral'
  'northeurope'
  'southafricanorth'
  'southcentralus'
  'uksouth'
  'westeurope'
  'japaneast'
  'southeastasia'
])
@description('The existing hub\'s regional affinity.')
param location string

@description('An existing IP Group that contains the application team\'s Linux compute IPs. IPs are maintained by the workload team.')
@minLength(79)
param linuxVmIpGroupResourceId string

@description('An existing IP Group that contains the application team\'s Windows compute IPs. IPs are maintained by the workload team.')
@minLength(79)
param windowsVmIpGroupResourceId string

// A designator that represents a business unit id and application id
var orgAppId = 'bu04a42'

/*** EXISTING HUB RESOURCES ***/

resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: 'vnet-${location}-hub'
}

@description('Existing Azure Firewall policy for this regional firewall.')
resource fwPolicy 'Microsoft.Network/firewallPolicies@2022-11-01' existing = {
  name: 'fw-policies-${location}'
}

/*** EXISTING SPOKE RESOURCES ***/

resource spokeVirtualNetworkResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription()
  name: split(spokeVirtualNetworkResourceId, '/')[4]
}

resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  scope: spokeVirtualNetworkResourceGroup
  name: split(spokeVirtualNetworkResourceId, '/')[8]
}

resource linuxVirtualMachineIpGroup 'Microsoft.Network/ipGroups@2022-11-01' existing = {
  scope: spokeVirtualNetworkResourceGroup
  name: split(linuxVmIpGroupResourceId, '/')[8]
}

resource windowsVirtualMachineIpGroup 'Microsoft.Network/ipGroups@2022-11-01' existing = {
  scope: spokeVirtualNetworkResourceGroup
  name: split(windowsVmIpGroupResourceId, '/')[8]
}


/*** RESOURCES ***/

resource appLzNetworkRulesCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-11-01' = {
  parent: fwPolicy
  name: 'alz-${orgAppId}'
  properties: {
    priority: 1001
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'alz-${orgAppId}-infra-n'
        action: {
          type: 'Allow'
        }
        priority: 100
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'ubuntu-time-sync'
            description: 'Allow outbound to support NTP time sync'
            destinationFqdns: [
              'ntp.ubuntu.com'
            ]
            ipProtocols: [
              'UDP'
            ]
            sourceIpGroups: [
              linuxVirtualMachineIpGroup.id
            ]
            destinationPorts: [
              '123'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'windows-time-sync'
            description: 'Allow outbound to support NTP time sync'
            destinationFqdns: [
              'time.windows.com'
            ]
            ipProtocols: [
              'UDP'
            ]
            sourceIpGroups: [
              windowsVirtualMachineIpGroup.id
            ]
            destinationPorts: [
              '123'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'alz-${orgAppId}-infra-a'
        action: {
          type: 'Allow'
        }
        priority: 200
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'ubuntu-package-upgrades'
            description: 'Allow outbound to support package upgrades'
            targetFqdns: [
              'azure.archive.ubuntu.com'
            ]
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
            ]
            httpHeadersToInsert: []
            terminateTLS: false
            sourceIpGroups: [
              linuxVirtualMachineIpGroup.id
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'windows-package-upgrades'
            description: 'Allow outbound to support package upgrades'
            targetFqdns: [
              'WindowsUpdate'
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            httpHeadersToInsert: []
            terminateTLS: false
            sourceIpGroups: [
              windowsVirtualMachineIpGroup.id
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'windows-diagnostics'
            description: 'Allow outbound to support windows diagnostics'
            targetFqdns: [
              'WindowsDiagnostics'
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            httpHeadersToInsert: []
            terminateTLS: false
            sourceIpGroups: [
              windowsVirtualMachineIpGroup.id
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'azure-monitor-extension'
            description: 'Supports required communication for the Azure Monitor extensions'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            webCategories: []
            targetFqdns: [
              'global.handler.control.monitor.azure.com'
              '${location}.handler.control.monitor.azure.com'
              '*.ods.opinsights.azure.com'
              '*.oms.opinsights.azure.com'
              '${location}.monitoring.azure.com'
            ]
            terminateTLS: false
            sourceIpGroups: [
              linuxVirtualMachineIpGroup.id
              windowsVirtualMachineIpGroup.id
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'alz-${orgAppId}-workload-a'
        priority: 250
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'github'
            description: 'Workload specific rule - provided by application team in subscription vending request.'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              'github.com'
              'api.github.com'
              'raw.githubusercontent.com'
              'nginx.org'
            ]
            targetUrls: []
            destinationAddresses: []
            terminateTLS: false
            sourceIpGroups: [
              linuxVirtualMachineIpGroup.id
              windowsVirtualMachineIpGroup.id
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'nginx'
            description: 'Workload specific rule - provided by application team in subscription vending request.'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              'nginx.org'
            ]
            targetUrls: []
            destinationAddresses: []
            terminateTLS: false
            sourceIpGroups: [
              linuxVirtualMachineIpGroup.id
              windowsVirtualMachineIpGroup.id
            ]
          }
        ]
      }
    ]
  }
}

// Peer to hub
resource peerToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-11-01' = {
  parent: hubVirtualNetwork
  name: take('peer-${hubVirtualNetwork.name}-to-${spokeVirtualNetwork.name}', 64)
  properties: {
    allowForwardedTraffic: false
    allowGatewayTransit: false
    allowVirtualNetworkAccess: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVirtualNetwork.id
    }
  }
}



/*

  // Network hub starts out with only supporting DNS. This is only being done for
  // simplicity in this deployment and is not guidance, please ensure all firewall
  // rules are aligned with your security standards.
  resource defaultNetworkRuleCollectionGroup 'ruleCollectionGroups@2021-05-01' = {
    name: 'DefaultNetworkRuleCollectionGroup'
    properties: {
      priority: 200
      ruleCollections: [
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'org-wide-allowed'
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
           
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'Vmss-Workload-Requirements'
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'NetworkRule'
              name: 'AllowAzureUbuntuArchive'
              description: 'Allow 80/443 outbound to azure.archive.ubuntu.com'
              ipProtocols: [
                'TCP'
              ]
              sourceAddresses: []
              sourceIpGroups: [
                ipgVmssSubnets.id
              ]
              destinationAddresses: []
              destinationIpGroups: []
              destinationFqdns: [
                'azure.archive.ubuntu.com'
              ]
              destinationPorts: [
                '80'
                '443'
              ]
            }
            {
              ruleType: 'NetworkRule'
              name: 'AllowAzureUbuntuArchiveUDP'
              description: 'Allow UDP outbound to azure.archive.ubuntu.com'
              ipProtocols: [
                'UDP'
              ]
              sourceAddresses: []
              sourceIpGroups: [
                ipgVmssSubnets.id
              ]
              destinationAddresses: []
              destinationIpGroups: []
              destinationFqdns: [
                'azure.archive.ubuntu.com'
              ]
              destinationPorts: [
                '123'
              ]
            }
          ]
        }
      ]
    }
  }

  // Network hub starts out with no allowances for appliction rules
  resource defaultApplicationRuleCollectionGroup 'ruleCollectionGroups@2021-05-01' = {
    name: 'DefaultApplicationRuleCollectionGroup'
    dependsOn: [
      defaultNetworkRuleCollectionGroup
    ]
    properties: {
      priority: 300
      ruleCollections: [
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'Vmss-Global-Requirements'
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'azure-monitor-extension'
              description: 'Supports required communication for the Azure Monitor extensions in Vmss'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                'global.handler.control.monitor.azure.com'
                '${location}.handler.control.monitor.azure.com'
                '*.ods.opinsights.azure.com'
                '*.oms.opinsights.azure.com'
                '${location}.monitoring.azure.com'
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgVmssSubnets.id
              ]
            }
            {
              ruleType: 'ApplicationRule'
              name: 'azure-policy'
              description: 'Supports required communication for the Azure Policy in Vmss'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                'data.policy.${environment().suffixes.storage}'
                'store.policy.${environment().suffixes.storage}'
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgVmssSubnets.id
              ]
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'GitOps-Traffic'
          priority: 300
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'github-origin'
              description: 'Supports pulling gitops configuration from GitHub.'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                'github.com'
                'api.github.com'
                'raw.githubusercontent.com'
                'nginx.org'
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgVmssSubnets.id
              ]
            }
          ]
        }
      ]
    }
  }
}

*/
/*** OUTPUTS ***/
/*
output hubVnetId string = vnetHub.id
output abName string = azureBastion.name*/
