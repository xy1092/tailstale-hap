// SSH 终端组件 - 可复用的 WebView 终端

import { webview } from '@kit.ArkWeb';

export interface SshConnection {
  host: string
  port: number
  username?: string
  password?: string
}

@Component
export struct SshTerminal {
  @Prop connection: SshConnection;
  @State url: string = '';
  @State loading: boolean = true;
  @State errorText: string = '';
  controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.buildUrl();
  }

  buildUrl(): void {
    let u = `http://${this.connection.host}:${this.connection.port}`;
    if (this.connection.username && this.connection.password) {
      u = `http://${this.connection.username}:${this.connection.password}@${this.connection.host}:${this.connection.port}`;
    }
    this.url = u;
  }

  build() {
    Column() {
      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#1976D2')
          Text('正在连接终端...')
            .fontSize(14)
            .fontColor('#666')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }

      if (this.errorText) {
        Column({ space: 16 }) {
          Text('连接失败')
            .fontSize(18)
            .fontColor('#EF5350')
          Text(this.errorText)
            .fontSize(13)
            .fontColor('#999')
            .textAlign(TextAlign.Center)
          Button('重试')
            .onClick(() => {
              this.errorText = '';
              this.loading = true;
              this.buildUrl();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }

      Web({ src: this.url, controller: this.controller })
        .layoutWeight(1)
        .width('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onPageBegin(() => {
          this.loading = true;
        })
        .onPageEnd(() => {
          this.loading = false;
        })
        .onErrorReceive((event) => {
          this.loading = false;
          this.errorText = event?.error?.getErrorInfo() ?? '无法连接到终端服务';
        })
    }
    .width('100%')
    .height('100%')
  }
}
