# tailscale-hap

鸿蒙平板 Tailscale/Headscale VPN 客户端，通过 WireGuard 协议接入 Tailscale 网络，实现平板 SSH 远程控制电脑。

## 架构

```
┌──────────── HarmonyOS 平板 ────────────┐     ┌── CachyOS PC ──────────┐
│                                        │     │                        │
│  ArkUI / ArkTS                         │     │  Headscale :8080       │
│  ├─ TunnelService                      │ WG │  Tailscale (系统服务)    │
│  ├─ VpnExtensionAbility                │◄───►│  ttyd :7681 (Web终端)   │
│  ├─ NAPI Bridge (NativeBridge.ts)      │     │                        │
│  └─ Rust boringtun ← libhm_tailscale_native.so                        │
└────────────────────────────────────────┘     └────────────────────────┘
```

## 技术栈

| 层 | 技术 |
|---|---|
| WireGuard 隧道 | boringtun 0.7 (Rust) |
| 原生桥接 | Rust C-ABI → NAPI C bridge → ArkTS |
| VPN 框架 | `@ohos.net.vpnExtension` |
| 协调服务 | Headscale REST API |
| SSH 终端 | ttyd + WebView |
| UI | ArkTS / ArkUI |

## 项目结构

```
tailscale-hap/
├── native/                  # Rust WireGuard 核心
│   ├── Cargo.toml
│   ├── build.sh             # 交叉编译脚本
│   └── src/
│       ├── lib.rs           # C-ABI 导出
│       ├── wireguard.rs     # boringtun 隧道
│       ├── loop.rs          # TUN/UDP I/O 循环
│       ├── config.rs        # 密钥/配置
│       └── napi_bridge.c    # NAPI C 桥接
├── entry/                   # 主模块
│   ├── libs/arm64-v8a/      # 交叉编译好的 .so
│   └── src/main/ets/
│       ├── pages/           # Index, SshPage
│       ├── vpn/             # VpnExtAbility, TunnelService, NativeBridge
│       └── entryability/
├── headscale/               # Headscale REST 客户端
├── ssh/                     # SSH 终端组件
└── scripts/                 # CachyOS 端部署脚本
```

## 开发流程

### Linux（日常开发）

```bash
# Rust 代码修改后重新编译 .so
cd native && ./build.sh

# 产物自动复制到 entry/libs/arm64-v8a/
# 提交推送
git add entry/libs/arm64-v8a/ && git commit -m "update .so" && git push
```

### Windows（HAP 打包）

```bash
git pull
# DevEco Studio → 打开项目 → Build → Build HAP
```

> 也可以从 DevEco Studio 安装目录复制 `command-line-tools/` 和 `sdk/` 到 Linux，实现全 Linux 开发。

### CachyOS PC 部署

```bash
cd scripts && chmod +x setup-cachyos.sh && ./setup-cachyos.sh
```

## NAPI 接口

| 函数 | 说明 |
|---|---|
| `wg_generate_keypair` | 生成 WireGuard 密钥对 |
| `wg_init_tunnel` | 初始化隧道 |
| `wg_create_socket` | 创建受保护 UDP socket |
| `wg_start_loop` | 启动后台 I/O 循环 |
| `wg_stop_loop` | 停止循环 |
| `wg_get_stats` | 获取隧道状态 |
| `wg_close_tunnel` | 关闭隧道 |

## 状态

- [x] Rust boringtun 隧道核心
- [x] ARM64 交叉编译 (.so 已产出)
- [x] NAPI C 桥接
- [x] Headscale API 客户端
- [x] VPN Extension Ability
- [x] ArkUI 主界面 + SSH 页面
- [x] CachyOS 部署脚本
- [x] GitHub 推送
- [ ] HAP 打包 (需 Windows DevEco Studio 或 CLI 工具)
- [ ] 真机测试
- [ ] DERP 中继支持
