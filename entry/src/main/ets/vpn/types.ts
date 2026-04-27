// VPN Extension 内部类型

export interface TunnelConfig {
  privateKey: string
  peerPublicKey: string
  peerEndpoint: string
  addresses: string[]
  dnsServers: string[]
  mtu: number
  keepaliveSeconds: number
}

export interface HeadscaleConfig {
  serverUrl: string
  apiKey: string
}
