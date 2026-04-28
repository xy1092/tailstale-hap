// 隧道管理服务 - 协调 Headscale + WireGuard + VPN Extension

import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';

import { HeadscaleClient } from 'headscale';
import type { NodeInfo, PeerConfig, RegisterResponse } from 'headscale';

import { NativeBridge, type KeyPair } from './NativeBridge';
import type { TunnelConfig, HeadscaleConfig } from './types';

const TAG = 'TunnelService';

export class TunnelService {
  private headscale: HeadscaleClient;
  private hsConfig: HeadscaleConfig;
  private keyPair: KeyPair | null = null;
  private nodeId: string | null = null;
  private connected: boolean = false;

  constructor(hsConfig: HeadscaleConfig) {
    this.hsConfig = hsConfig;
    this.headscale = new HeadscaleClient({
      serverUrl: hsConfig.serverUrl,
      apiKey: hsConfig.apiKey,
    });
  }

  // 生成密钥对并注册到 Headscale
  async register(nodeName: string): Promise<RegisterResponse> {
    this.keyPair = NativeBridge.generateKeypair();
    console.info(TAG, 'generated keypair, public=' + this.keyPair.publicKey);

    const resp = await this.headscale.registerNode({
      nodeKey: this.keyPair.publicKey,
      name: nodeName,
      user: 'default',
    });

    this.nodeId = resp.node.id;
    console.info(TAG, 'node registered, id=' + this.nodeId);
    return resp;
  }

  // 获取所有在线 peer
  async getPeers(): Promise<PeerConfig[]> {
    return this.headscale.buildPeerConfig(this.keyPair?.publicKey ?? '');
  }

  // 获取节点信息
  async getMyNode(): Promise<NodeInfo | null> {
    if (!this.nodeId) return null;
    return this.headscale.getNode(this.nodeId);
  }

  // 启动 VPN 连接
  async connect(targetPeer: PeerConfig, myIp: string): Promise<void> {
    if (!this.keyPair) {
      throw new Error('not registered');
    }

    // 构建 WireGuard 隧道配置
    const config: TunnelConfig = {
      privateKey: this.keyPair.privateKey,
      peerPublicKey: targetPeer.publicKey,
      peerEndpoint: targetPeer.endpoint || this.hsConfig.serverUrl.replace(/\/\/.*?:/, '//') + ':51820',
      addresses: [myIp + '/32'],
      dnsServers: ['114.114.114.114'],
      mtu: 1400,
      keepaliveSeconds: 25,
    };

    // 通过 VPN Extension 启动隧道
    const want: Want = {
      deviceId: '',
      bundleName: 'com.example.hmtailscale',
      abilityName: 'WireGuardVpnAbility',
      parameters: {
        tunnelConfig: JSON.stringify(config),
      },
    };

    try {
      await vpnExtension.startVpnExtensionAbility(want);
      this.connected = true;
      console.info(TAG, 'VPN started');
    } catch (e) {
      console.error(TAG, 'VPN start failed: ' + JSON.stringify(e));
      throw new Error(String(e));
    }
  }

  // 断开 VPN
  async disconnect(): Promise<void> {
    try {
      const want: Want = {
        deviceId: '',
        bundleName: 'com.example.hmtailscale',
        abilityName: 'WireGuardVpnAbility',
      };
      await vpnExtension.stopVpnExtensionAbility(want);
      this.connected = false;
      console.info(TAG, 'VPN stopped');
    } catch (e) {
      console.error(TAG, 'VPN stop failed: ' + JSON.stringify(e));
      throw new Error(String(e));
    }
  }

  // 获取隧道状态
  getStats() {
    return NativeBridge.getStats();
  }

  isConnected(): boolean {
    return this.connected;
  }

  getNodeId(): string | null {
    return this.nodeId;
  }

  getKeyPair() {
    return this.keyPair;
  }
}
