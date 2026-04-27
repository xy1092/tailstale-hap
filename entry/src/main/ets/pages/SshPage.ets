// SSH 终端页面 - 通过 Tailscale IP 访问 ttyd Web 终端

import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct SshPage {
  @State targetHost: string = '10.0.0.1';
  @State targetPort: string = '7681';
  @State useAuth: boolean = false;
  @State username: string = '';
  @State password: string = '';
  @State connected: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Column({ space: 0 }) {
      // 顶部工具栏
      Row() {
        Text('SSH')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)

        Blank()

        Button(this.connected ? '断开' : '连接')
          .fontSize(14)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.connected ? '#EF5350' : '#4CAF50')
          .onClick(() => {
            if (this.connected) {
              this.connected = false;
            } else {
              this.navigateToTerminal();
            }
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // 未连接时显示配置
      if (!this.connected) {
        Column({ space: 16 }) {
          Text('连接到远程终端')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .padding({ top: 32 })

          Row({ space: 12 }) {
            Text('主机')
              .fontSize(14)
              .width(60)
            TextInput({ text: this.targetHost, placeholder: '电脑的 Tailscale IP' })
              .onChange((v: string) => { this.targetHost = v })
              .layoutWeight(1)
              .height(48)
              .borderRadius(8)
              .backgroundColor('#FFFFFF')
          }.width('100%')

          Row({ space: 12 }) {
            Text('端口')
              .fontSize(14)
              .width(60)
            TextInput({ text: this.targetPort, placeholder: '7681' })
              .onChange((v: string) => { this.targetPort = v })
              .layoutWeight(1)
              .height(48)
              .borderRadius(8)
              .backgroundColor('#FFFFFF')
              .type(InputType.Number)
          }.width('100%')

          // 认证信息（如果 ttyd 开启了 -c 参数）
          if (this.useAuth) {
            Row({ space: 12 }) {
              Text('用户名')
                .fontSize(14)
                .width(60)
              TextInput({ text: this.username, placeholder: 'ttyd 用户名' })
                .onChange((v: string) => { this.username = v })
                .layoutWeight(1)
                .height(48)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }.width('100%')

            Row({ space: 12 }) {
              Text('密码')
                .fontSize(14)
                .width(60)
              TextInput({ text: this.password, placeholder: 'ttyd 密码' })
                .onChange((v: string) => { this.password = v })
                .type(InputType.Password)
                .layoutWeight(1)
                .height(48)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }.width('100%')
          }

          Row() {
            Toggle({ type: ToggleType.Switch, isOn: this.useAuth })
              .onChange((v: boolean) => { this.useAuth = v })
              .width(36)
            Text('使用认证')
              .fontSize(14)
              .padding({ left: 8 })
          }
          .width('100%')

          // 提示信息
          Text('请先在电脑上启动 ttyd:\nttyd -W -p 7681 -c user:pass bash\n\n或无需认证:\nttyd -W -p 7681 bash')
            .fontSize(12)
            .fontColor('#999')
            .textAlign(TextAlign.Start)
            .width('100%')
            .padding(12)
            .backgroundColor('#F0F0F0')
            .borderRadius(8)

          // 快速指南
          Column({ space: 4 }) {
            Text('电脑端一键设置脚本').fontWeight(FontWeight.Medium).fontSize(14)
            Text(
`# 在 CachyOS 终端执行：
# 1. 安装 ttyd
sudo pacman -S ttyd

# 2. 启动 (通过 Tailscale IP 访问)
ttyd -W -p 7681 -c myuser:mypass tmux new -A -s main

# 3. 在平板上连接
# 主机: 你的电脑 Tailscale IP
# 端口: 7681`
            )
              .fontSize(12)
              .fontColor('#555')
              .fontFamily('monospace')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .padding(24)
        .width('100%')
        .layoutWeight(1)
      }

      // 已连接时显示 WebView 终端
      if (this.connected) {
        Web({ src: this.buildUrl(), controller: this.controller })
          .layoutWeight(1)
          .width('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onErrorReceive((event) => {
            if (event?.error?.getErrorInfo()) {
              promptAction.showToast({ message: '连接失败，请确认电脑端 ttyd 已启动' });
              this.connected = false;
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  buildUrl(): string {
    let url = `http://${this.targetHost}:${this.targetPort}`;
    if (this.useAuth && this.username && this.password) {
      url = `http://${this.username}:${this.password}@${this.targetHost}:${this.targetPort}`;
    }
    return url;
  }

  navigateToTerminal(): void {
    // 检查 URL 格式
    if (!this.targetHost || !this.targetPort) {
      promptAction.showToast({ message: '请填写主机地址和端口' });
      return;
    }

    this.connected = true;
  }

  onPageHide(): void {
    // 页面隐藏时断开 WebView 连接，释放资源
    this.connected = false;
  }
}
