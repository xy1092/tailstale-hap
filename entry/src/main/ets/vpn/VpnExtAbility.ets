// VPN Extension Ability - WireGuard 隧道生命周期

import { VpnExtensionAbility } from '@kit.NetworkKit';
import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';

import { NativeBridge } from './NativeBridge';
import type { TunnelConfig } from './types';

const TAG = 'VpnExtAbility';

export default class WireGuardVpnAbility extends VpnExtensionAbility {
  private tunFd: number = -1;
  private sockFd: number = -1;
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunnelConfig: TunnelConfig | null = null;

  onCreate(want: Want): void {
    console.info(TAG, 'VPN creating, want=' + JSON.stringify(want));

    // 从启动参数获取隧道配置
    const cfgJson = want?.parameters?.['tunnelConfig'] as string;
    if (cfgJson) {
      this.tunnelConfig = JSON.parse(cfgJson) as TunnelConfig;
    }

    this.setupVpn();
  }

  private async setupVpn(): Promise<void> {
    try {
      const context: vpnExtension.VpnExtensionContext =
        this.context as vpnExtension.VpnExtensionContext;
      this.vpnConnection = vpnExtension.createVpnConnection(context);

      // 1. 初始化 WireGuard 隧道
      const cfg = this.tunnelConfig;
      if (!cfg) {
        console.error(TAG, 'no tunnel config');
        return;
      }

      const cfgJson = JSON.stringify({
        private_key: cfg.privateKey,
        peer_public_key: cfg.peerPublicKey,
        peer_endpoint: cfg.peerEndpoint,
        addresses: cfg.addresses,
        dns_servers: cfg.dnsServers,
        mtu: cfg.mtu,
        keepalive_seconds: cfg.keepaliveSeconds,
      });

      if (!NativeBridge.initTunnel(cfgJson)) {
        console.error(TAG, 'failed to init WireGuard tunnel');
        return;
      }

      // 2. 创建 WireGuard 通信用的 UDP socket
      this.sockFd = NativeBridge.createSocket(cfg.peerEndpoint);
      if (this.sockFd <= 0) {
        console.error(TAG, 'failed to create UDP socket');
        return;
      }

      // 3. 保护 UDP socket (使其绕过 VPN 路由，避免环路)
      try {
        await this.vpnConnection.protect(this.sockFd);
        console.info(TAG, 'protected socket fd=' + this.sockFd);
      } catch (e) {
        console.error(TAG, 'failed to protect socket: ' + JSON.stringify(e));
      }

      // 4. 创建 VPN 虚拟网卡 (TUN)
      const vpnConfig: vpnExtension.VpnConfig = {
        addresses: cfg.addresses.map(addr => {
          const [ip, prefix] = addr.split('/');
          return {
            address: { address: ip, family: 1 },
            prefixLength: parseInt(prefix) || 32,
          };
        }),
        mtu: cfg.mtu,
        dnsAddresses: cfg.dnsServers,
        isIPv4Accepted: true,
        isIPv6Accepted: false,
        isBlocking: true,
        trustedApplications: [],
        blockedApplications: [],
      };

      this.tunFd = await this.vpnConnection.create(vpnConfig);
      console.info(TAG, 'VPN created, tun fd=' + this.tunFd);

      // 5. 启动后台 I/O 循环 (TUN ↔ WireGuard ↔ UDP)
      if (!NativeBridge.startLoop(this.tunFd, this.sockFd)) {
        console.error(TAG, 'failed to start I/O loop');
        return;
      }

      console.info(TAG, 'VPN tunnel fully established');
    } catch (err) {
      console.error(TAG, 'setupVpn error: ' + JSON.stringify(err));
      this.cleanup();
    }
  }

  onDestroy(): void {
    console.info(TAG, 'VPN destroying');
    this.cleanup();
  }

  private async cleanup(): Promise<void> {
    // 停止 I/O 循环
    NativeBridge.stopLoop();

    // 关闭 WireGuard 隧道
    NativeBridge.closeTunnel();

    // 销毁 VPN 虚拟网卡
    if (this.vpnConnection && this.tunFd >= 0) {
      try {
        await this.vpnConnection.destroy();
        console.info(TAG, 'VPN connection destroyed');
      } catch (e) {
        console.error(TAG, 'destroy error: ' + JSON.stringify(e));
      }
    }

    this.tunFd = -1;
    this.sockFd = -1;
    this.vpnConnection = null;
  }
}
