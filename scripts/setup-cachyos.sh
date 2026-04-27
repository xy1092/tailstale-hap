#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# CachyOS 端配置脚本
# 用途: 一键安装 Headscale + ttyd，为鸿蒙平板提供
#       Tailscale 兼容 VPN + Web SSH 终端
# ─────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

echo "========================================"
echo "  HarmonyScale - CachyOS Server Setup"
echo "========================================"
echo ""

# ── 1. 检查 Tailscale ─────────────────────────────────
if command -v tailscale &>/dev/null; then
  log "Tailscale 已安装: $(tailscale version | head -1)"
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "未知")
  log "Tailscale IPv4: $TAILSCALE_IP"
else
  warn "Tailscale 未安装，请先安装:"
  echo "  sudo pacman -S tailscale"
  echo "  sudo systemctl enable --now tailscaled"
  echo "  tailscale up"
  exit 1
fi

# ── 2. 安装 ttyd (Web SSH 终端) ─────────────────────
if command -v ttyd &>/dev/null; then
  log "ttyd 已安装"
else
  log "安装 ttyd..."
  sudo pacman -S --noconfirm ttyd || {
    warn "pacman 安装失败，尝试从源码编译..."
    sudo pacman -S --noconfirm cmake openssl libwebsockets json-c
    git clone https://github.com/tsl0922/ttyd.git /tmp/ttyd-build
    cd /tmp/ttyd-build
    mkdir build && cd build
    cmake ..
    make -j$(nproc)
    sudo make install
    cd && rm -rf /tmp/ttyd-build
  }
fi

# ── 3. 安装 Headscale ──────────────────────────────
HEADSCALE_PORT=${HEADSCALE_PORT:-8080}

if command -v headscale &>/dev/null; then
  log "Headscale 已安装"
else
  log "安装 Headscale (使用 Docker)..."
  if ! command -v docker &>/dev/null; then
    warn "Docker 未安装，跳过 Headscale Docker 部署"
    warn "你可以稍后手动安装 Headscale 或使用 Tailscale 官方服务"
  else
    sudo docker pull headscale/headscale:latest
  fi
fi

# ── 4. 创建 systemd 服务 ──────────────────────────
log "创建 ttyd systemd 服务..."

TTYD_PASS=${TTYD_PASS:-"myterm123"}
TTYD_PORT=${TTYD_PORT:-7681}

sudo tee /etc/systemd/system/ttyd-ssh.service > /dev/null <<SYSTEMD
[Unit]
Description=ttyd - Web SSH Terminal
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
ExecStart=$(which ttyd) -W -p ${TTYD_PORT} -c ${USER}:${TTYD_PASS} tmux new -A -s main
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD

sudo systemctl daemon-reload
sudo systemctl enable --now ttyd-ssh.service

log "ttyd 服务已启动在端口 ${TTYD_PORT}"
log "访问地址: http://${TAILSCALE_IP}:${TTYD_PORT}"
log "用户名: ${USER}"
log "密码: ${TTYD_PASS}"

# ── 5. Headscale Docker 部署 ──────────────────────
if command -v docker &>/dev/null; then
  log "配置 Headscale Docker..."

  HEADSCALE_DIR="${HOME}/headscale"
  mkdir -p "${HEADSCALE_DIR}/config"

  # 默认配置
  cat > "${HEADSCALE_DIR}/config/config.yaml" <<YAML
server_url: http://${TAILSCALE_IP}:${HEADSCALE_PORT}
listen_addr: 0.0.0.0:${HEADSCALE_PORT}
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: true

noise:
  private_key_path: /etc/headscale/noise_private.key

ip_prefixes:
  - 100.64.0.0/10
  - fd7a:115c:a1e0::/48

derp:
  server:
    enabled: false
  urls: []
  paths: []

disable_check_updates: true
database:
  type: sqlite3
  sqlite3:
    path: /etc/headscale/db.sqlite

acl_policy_path: ""
dns_config:
  override_local_dns: true
  nameservers:
    - 1.1.1.1
  magic_dns: true
  domains: []
  base_domain: tailnet.local
YAML

  # 生成 Headscale API Key (首次启动后)
  log "启动 Headscale Docker 容器..."
  sudo docker rm -f headscale 2>/dev/null || true
  sudo docker run -d \
    --name headscale \
    --restart always \
    -v "${HEADSCALE_DIR}/config:/etc/headscale" \
    -p 127.0.0.1:${HEADSCALE_PORT}:${HEADSCALE_PORT} \
    headscale/headscale:latest \
    headscale serve

  sleep 3
  log "生成 Headscale API Key..."
  API_KEY=$(sudo docker exec headscale headscale apikeys create -e 365d 2>/dev/null | tail -1 || echo "")
  if [ -n "$API_KEY" ]; then
    echo ""
    echo "========================================"
    echo "  API Key (重要！请保存):"
    echo "  ${API_KEY}"
    echo "========================================"
    echo ""
    log "API Key 已生成，请在鸿蒙 App 配置中使用"
  else
    warn "API Key 生成可能需要容器完全启动后重试"
    warn "手动执行: sudo docker exec headscale headscale apikeys create -e 365d"
  fi
fi

# ── 6. 配置防火墙 ─────────────────────────────────
log "配置防火墙 (如果启用)..."

if command -v ufw &>/dev/null; then
  sudo ufw allow from 100.64.0.0/10 to any port ${TTYD_PORT} comment 'ttyd via Tailscale'
fi

# ── 7. 总结 ────────────────────────────────────────
echo ""
echo "========================================"
echo "  配置完成！"
echo "========================================"
echo ""
echo "电脑端已就绪："
echo "  ttyd Web 终端:  http://${TAILSCALE_IP}:${TTYD_PORT}"
echo "  Headscale API:  http://${TAILSCALE_IP}:${HEADSCALE_PORT}"
echo ""
echo "平板端配置："
echo "  服务器地址:  http://${TAILSCALE_IP}:${HEADSCALE_PORT}"
echo "  API Key:      上面生成的 Key"
echo "  设备名称:     harmony-tablet"
echo ""
echo "SSH 终端配置："
echo "  主机:  ${TAILSCALE_IP}"
echo "  端口:  ${TTYD_PORT}"
echo "  用户:  ${USER}"
echo "  密码:  ${TTYD_PASS}"
echo ""
