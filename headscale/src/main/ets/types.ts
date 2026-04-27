// Headscale API 类型定义

export interface NodeInfo {
  id: string
  name: string
  givenName: string
  ipAddresses: string[]
  publicKey: string
  endpoints: string[]
  online: boolean
  lastSeen: string
  user: string
}

export interface RegisterRequest {
  nodeKey: string
  name: string
  user: string
}

export interface RegisterResponse {
  node: NodeInfo
  machineKey: string
}

export interface PeerConfig {
  publicKey: string
  endpoint: string
  allowedIps: string[]
}

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
  serverUrl: string     // e.g. "http://100.x.x.x:8080"
  apiKey: string         // Headscale API key
}

export interface AppState {
  connected: boolean
  nodeInfo: NodeInfo | null
  tunnelConfig: TunnelConfig | null
  stats: TunnelStats | null
  error: string | null
}

export interface TunnelStats {
  handshakeCompleted: boolean
  txBytes: number
  rxBytes: number
  lastHandshakeSecsAgo: number | null
  peerEndpoint: string
}
