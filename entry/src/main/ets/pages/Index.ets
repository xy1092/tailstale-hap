// 主页面 - HarmonyScale: 基于 Tailscale 协议的鸿蒙 VPN + SSH 客户端

import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';

import { TunnelService } from '../vpn/TunnelService';
import { NativeBridge } from '../vpn/NativeBridge';
import type { HeadscaleConfig } from '../vpn/types';
import type { NodeInfo, PeerConfig, TunnelStats } from 'headscale';

const TAG = 'Index';

@Entry
@Component
struct Index {
  @State serverUrl: string = 'http://10.0.0.1:8080';
  @State apiKey: string = '';
  @State nodeName: string = 'harmony-tablet';
  @State connected: boolean = false;
  @State statusText: string = '未连接';
  @State stats: TunnelStats | null = null;
  @State peers: PeerConfig[] = [];
  @State configured: boolean = false;
  @State myNodeId: string = '';

  private service: TunnelService | null = null;

  build() {
    Column({ space: 16 }) {
      // 标题栏
      Row() {
        Text('HarmonyScale')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a1a1a')

        Blank()

        if (this.configured) {
          Text(this.connected ? '已连接' : '已配置')
            .fontSize(14)
            .fontColor(this.connected ? '#4CAF50' : '#FF9800')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.connected ? '#E8F5E9' : '#FFF3E0')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Divider()

      // 未配置时显示设置表单
      if (!this.configured) {
        this.SetupForm()
      }

      // 已配置时显示主界面
      if (this.configured) {
        this.MainPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  // ── 设置表单 ──────────────────────────────

  @Builder
  SetupForm() {
    Column({ space: 12 }) {
      Text('Headscale 服务器配置')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)

      Column({ space: 8 }) {
        Text('服务器地址').fontSize(13).fontColor('#666')
        TextInput({ text: this.serverUrl, placeholder: 'http://100.x.x.x:8080' })
          .onChange((value: string) => { this.serverUrl = value })
          .height(48)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 8 }) {
        Text('API Key').fontSize(13).fontColor('#666')
        TextInput({ text: this.apiKey, placeholder: '输入 Headscale API Key' })
          .onChange((value: string) => { this.apiKey = value })
          .type(InputType.Password)
          .height(48)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 8 }) {
        Text('设备名称').fontSize(13).fontColor('#666')
        TextInput({ text: this.nodeName, placeholder: 'harmony-tablet' })
          .onChange((value: string) => { this.nodeName = value })
          .height(48)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Button('配置并注册')
        .width('100%')
        .height(48)
        .fontSize(16)
        .borderRadius(24)
        .backgroundColor('#1976D2')
        .onClick(() => { this.doSetup() })
    }
    .padding(16)
    .width('100%')
  }

  // ── 主面板 ──────────────────────────────

  @Builder
  MainPanel() {
    Column({ space: 16 }) {
      // 连接控制按钮
      Row({ space: 12 }) {
        Button(this.connected ? '断开连接' : '建立连接')
          .width('60%')
          .height(52)
          .fontSize(16)
          .borderRadius(26)
          .backgroundColor(this.connected ? '#EF5350' : '#4CAF50')
          .onClick(() => {
            if (this.connected) { this.doDisconnect() } else { this.doConnect() }
          })

        Button('SSH')
          .width('35%')
          .height(52)
          .fontSize(16)
          .borderRadius(26)
          .backgroundColor('#1976D2')
          .enabled(this.connected)
          .onClick(() => {
            if (this.connected) {
              router.pushUrl({ url: 'pages/SshPage' });
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 隧道状态
      if (this.stats) {
        this.StatsCard()
      }

      // 节点列表
      if (this.peers.length > 0) {
        this.PeerList()
      }

      // 状态文本
      Text(this.statusText)
        .fontSize(14)
        .fontColor('#888')
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  StatsCard() {
    Column({ space: 8 }) {
      Text('隧道状态').fontSize(16).fontWeight(FontWeight.Medium)
      Row() {
        Text('握手: ' + (this.stats!.handshakeCompleted ? '完成' : '未完成'))
        Blank()
        Text('TX: ' + this.formatBytes(this.stats!.txBytes))
      }.width('100%')
      Row() {
        Text('RX: ' + this.formatBytes(this.stats!.rxBytes))
        Blank()
        Text('节点: ' + this.stats!.peerEndpoint)
      }.width('100%')
    }
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .width('100%')
    .shadow({ radius: 4, color: '#10000000' })
  }

  @Builder
  PeerList() {
    Column({ space: 8 }) {
      Text('在线节点').fontSize(16).fontWeight(FontWeight.Medium)

      ForEach(this.peers, (peer: PeerConfig) => {
        Row() {
          Column({ space: 4 }) {
            Text(peer.publicKey.substring(0, 12) + '...')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
            Text(peer.endpoint)
              .fontSize(12)
              .fontColor('#999')
          }
          Blank()
          Text('在线')
            .fontSize(12)
            .fontColor('#4CAF50')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor('#E8F5E9')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FAFAFA')
        .borderRadius(8)
      }, (peer: PeerConfig) => peer.publicKey)
    }
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .width('100%')
    .shadow({ radius: 4, color: '#10000000' })
  }

  // ── 业务逻辑 ─────────────────────────────

  async doSetup(): Promise<void> {
    if (!this.serverUrl || !this.apiKey) {
      promptAction.showToast({ message: '请填写服务器地址和 API Key' });
      return;
    }

    try {
      const hsConfig: HeadscaleConfig = {
        serverUrl: this.serverUrl,
        apiKey: this.apiKey,
      };

      this.service = new TunnelService(hsConfig);

      // 注册节点到 Headscale
      const resp = await this.service.register(this.nodeName);
      this.myNodeId = resp.node.id;
      this.configured = true;
      this.statusText = `已注册: ${resp.node.name} (${resp.node.ipAddresses[0] ?? 'pending'})`;

      // 获取可用 peer 列表
      this.peers = await this.service.getPeers();

      promptAction.showToast({
        message: `注册成功，发现 ${this.peers.length} 个在线节点`,
      });
    } catch (e) {
      promptAction.showToast({ message: `注册失败: ${JSON.stringify(e)}` });
      console.error(TAG, 'setup error: ' + JSON.stringify(e));
    }
  }

  async doConnect(): Promise<void> {
    if (!this.service || this.peers.length === 0) {
      promptAction.showToast({ message: '没有可用的节点' });
      return;
    }

    try {
      // 连接到第一个可用 peer（通常是你的 CachyOS 电脑）
      const target = this.peers[0];
      const myNodeInfo = await this.service.getMyNode();
      const myIp = myNodeInfo?.ipAddresses[0] ?? '10.0.0.2';

      await this.service.connect(target, myIp);
      this.connected = true;
      this.statusText = '已连接到 ' + target.endpoint;

      // 定期刷新状态
      this.refreshStats();
    } catch (e) {
      promptAction.showToast({ message: `连接失败: ${JSON.stringify(e)}` });
    }
  }

  async doDisconnect(): Promise<void> {
    try {
      await this.service?.disconnect();
      this.connected = false;
      this.stats = null;
      this.statusText = '已断开连接';
    } catch (e) {
      promptAction.showToast({ message: `断开失败: ${JSON.stringify(e)}` });
    }
  }

  refreshStats(): void {
    if (this.service && this.connected) {
      this.stats = this.service.getStats();
      setTimeout(() => { this.refreshStats() }, 3000);
    }
  }

  formatBytes(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
  }
}
