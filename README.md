# HarmonyScale

鸿蒙平板 Tailscale 兼容 VPN + SSH 客户端。

通过 WireGuard 协议将鸿蒙平板接入 Tailscale/Headscale 网络，实现从平板 SSH 到电脑。

## 架构

```
┌─────────────────────────┐     ┌──────────────────────────┐
│  鸿蒙平板 (HarmonyOS)    │     │  CachyOS 电脑             │
│                         │     │                          │
│  ┌─────────────────┐    │     │  ┌───────────────────┐   │
│  │ ArkUI 主界面     │    │     │  │ Headscale 服务器   │   │
│  │ - 配置/连接/SSH  │    │     │  │ (协调节点)         │   │
│  └───────┬─────────┘    │     │  └─────────┬─────────┘   │
│          │              │     │            │             │
│  ┌───────┴─────────┐    │     │  ┌─────────┴─────────┐   │
│  │ TunnelService   │    │     │  │ Tailscale/WG     │   │
│  │ (ArkTS)         │    │WireG│  │ (系统服务)        │   │
│  └───────┬─────────┘    │uard │  └─────────┬─────────┘   │
│          │              │     │            │             │
│  ┌───────┴─────────┐    │     │  ┌─────────┴─────────┐   │
│  │ NAPI Bridge     │    │     │  │ ttyd Web 终端     │   │
│  └───────┬─────────┘    │     │  │ :7681             │   │
│          │              │     │  └───────────────────┘   │
│  ┌───────┴─────────┐    │     │                          │
│  │ Rust (boringtun) │    │     │                          │
│  │ WireGuard 协议   │    │     │                          │
│  │ TUN I/O Loop    │    │     │                          │
│  └───────┬─────────┘    │     │                          │
│          │              │     │                          │
│  ┌───────┴─────────┐    │     │                          │
│  │ VPN Extension   │    │     │                          │
│  │ (系统 API)       │    │     │                          │
│  └─────────────────┘    │     │                          │
└─────────────────────────┘     └──────────────────────────┘
```

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| VPN 隧道 | boringtun 0.7 | Cloudflare 用户态 WireGuard |
| 原生桥接 | Rust C-ABI → NAPI | ArkTS ↔ Rust 互操作 |
| VPN 框架 | `@ohos.net.vpnExtension` | 鸿蒙 VPN API |
| 协调协议 | Headscale REST API | Tailscale 兼容协调服务器 |
| SSH 终端 | ttyd WebView | Web SSH 终端 |
| UI | ArkTS / ArkUI | 鸿蒙声明式 UI |

## 快速开始

### 1. CachyOS 电脑端设置

```bash
cd scripts
chmod +x setup-cachyos.sh
./setup-cachyos.sh
```

脚本会自动安装配置：ttyd Web SSH 终端 + Headscale 协调服务器。

### 2. 鸿蒙平板端

安装 DevEco Studio 5.0+ (Linux 版可用)：

```bash
# 下载 DevEco Studio
# https://developer.huawei.com/consumer/cn/download/deveco-studio

# 安装完成后设置环境变量
export OHOS_NDK_HOME=/path/to/DevEco-Studio/sdk/default/openharmony
```

### 3. 安装 Rust 工具链

```bash
# 安装 rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 添加 HarmonyOS target
rustup target add aarch64-unknown-linux-ohos

# 安装 ohos-rs CLI
cargo install ohrs
```

### 4. 编译 Rust 原生库

```bash
cd native

# 在 Linux 上测试编译
cargo check

# 交叉编译到鸿蒙目标
ohrs build --arch aarch64 --release
```

### 5. 在 DevEco Studio 中构建

1. 打开项目 `/home/xy/项目/hm-tailscale`
2. 将编译好的 `.so` 放入 `entry/libs/arm64-v8a/`
3. 连接鸿蒙平板或启动模拟器
4. 运行项目

### 6. App 配置

在 App 中填写：
- **服务器地址**: Headscale 地址 (`http://100.78.229.11:8080`)
- **API Key**: `hskey-api-i0QthQT-o_8A-91PJOwd0Wx1mKz1EZrlTd44zy1Jm3YWzRRQA1UPWQ7dRoxHIL-y7mJRsf149Wa6m`
- **设备名称**: `harmony-tablet`

点击「配置并注册」，然后「建立连接」。

### 7. SSH 连接

连接成功后，点击「SSH」按钮，输入：
- **主机**: `100.78.229.11`
- **端口**: `7681` (ttyd 端口)

## 项目结构

```
hm-tailscale/
├── native/                    # Rust WireGuard 原生库
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs             # C-ABI 导出函数
│       ├── wireguard.rs       # boringtun 隧道核心
│       ├── loop.rs            # TUN/UDP I/O 循环
│       ├── config.rs          # 密钥/配置管理
│       └── error.rs           # 错误类型
├── entry/                     # ArkTS 主入口模块
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/  # UIAbility
│       │   ├── pages/         # Index, SshPage
│       │   └── vpn/           # VpnExtAbility, TunnelService, NativeBridge
│       ├── module.json5       # 模块配置(含 VPN 权限)
│       └── resources/
├── headscale/                 # Headscale API 客户端模块
│   └── src/main/ets/
│       ├── HeadscaleClient.ts # REST API 封装
│       └── types.ts           # 类型定义
├── ssh/                       # SSH 终端模块
├── scripts/
│   └── setup-cachyos.sh       # CachyOS 端一键部署脚本
├── AppScope/app.json5
├── build-profile.json5
└── hvigor/
```

## NAPI 函数接口

| 函数 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `wg_generate_keypair` | - | JSON (priv/pub key) | 生成 WireGuard 密钥对 |
| `wg_init_tunnel` | config JSON | `{"ok":true/false}` | 初始化隧道 |
| `wg_create_socket` | "ip:port" | fd | 创建受保护 UDP socket |
| `wg_start_loop` | tunFd, sockFd | `{"ok":true/false}` | 启动后台 I/O 循环 |
| `wg_stop_loop` | - | `{"ok":true}` | 停止循环 |
| `wg_get_stats` | - | JSON 统计 | 获取隧道状态 |
| `wg_close_tunnel` | - | `{"ok":true/false}` | 关闭隧道 |

## 当前状态

- [x] Rust boringtun 隧道核心
- [x] TUN/UDP I/O 循环
- [x] Headscale API 客户端
- [x] VPN Extension Ability
- [x] ArkUI 主界面 + SSH 页面
- [x] CachyOS 部署脚本
- [ ] NAPI 模块注册 (需 DevEco Studio)
- [ ] 真机联调测试
- [ ] 后台保活优化
- [ ] DERP 中继支持 (NAT 穿透 fallback)
