#!/usr/bin/env bash
# ==============================================================
#  MTG-Quick — MTPROTO Proxy 一键部署脚本
#  原项目: https://github.com/9seconds/mtg
#  用法: bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh)
#  卸载: mtg-quick uninstall
#
#  特性:
#  - 支持 systemd (Debian/Ubuntu/CentOS) 和 OpenRC (Alpine)
#  - 交互式域名、端口、IP 模式选择
#  - 自动安装依赖
#  - 装完后可用 mtg-quick 命令管理
# ==============================================================

set -euo pipefail

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

CONF_DIR="/etc/mtg-quick"
BIN="/usr/local/bin/mtg"
SELF_URL="https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh"

# ======================== 卸载模式 ========================
if [ "${1:-}" = "uninstall" ]; then
  echo "卸载 mtg..."
  systemctl stop mtg 2>/dev/null || rc-service mtg stop 2>/dev/null || true
  systemctl disable mtg 2>/dev/null || rc-update del mtg 2>/dev/null || true
  rm -f /etc/systemd/system/mtg.service /etc/init.d/mtg
  systemctl daemon-reload 2>/dev/null || true
  rm -f "$BIN" /etc/mtg.toml
  rm -rf "$CONF_DIR" /usr/local/bin/mtg-quick
  info "mtg 已卸载"
  exit 0
fi

# ======================== Root 检查 ========================
[ "$(id -u)" -ne 0 ] && { err "请以 root 运行 (sudo -i 或 su -)"; exit 1; }

# ======================== 架构检测 ========================
step_info() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="linux-amd64"    ;;
  aarch64) BIN_ARCH="linux-arm64"     ;;
  armv7l)  BIN_ARCH="linux-armv7"     ;;
  armv6l)  BIN_ARCH="linux-armv6"     ;;
  i386|i686) BIN_ARCH="linux-386"     ;;
  mips)    BIN_ARCH="linux-mips"      ;;
  mipsle)  BIN_ARCH="linux-mipsle"    ;;
  *) err "不支持的架构: $ARCH"; exit 1 ;;
esac

OS_ID=""; PKG_MGR=""; INIT="systemd"
if [ -f /etc/os-release ]; then
  OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
fi
if [ -f /etc/alpine-release ]; then
  OS_ID="alpine"; PKG_MGR="apk"; INIT="openrc"
elif [[ "$OS_ID" =~ ^(debian|ubuntu)$ ]]; then
  PKG_MGR="apt"
elif [[ "$OS_ID" =~ ^(centos|rhel|rocky|almalinux|fedora)$ ]]; then
  PKG_MGR="yum"
else
  err "不支持的系统: $OS_ID"; exit 1
fi
info "系统: $OS_ID  架构: $ARCH  服务管理: $INIT"

# ======================== 安装依赖 ========================
step_info "安装依赖"
DEPS=(curl tar gawk coreutils openssl ca-certificates)
case "$PKG_MGR" in
  apk)
    apk update -q 2>/dev/null || { warn "apk update 失败，继续尝试"; }
    apk add -q "${DEPS[@]}" 2>&1 | tail -1 || { err "依赖安装失败"; exit 1; }
    ;;
  apt)
    apt-get update -qq 2>/dev/null || warn "apt update 失败（可能是网络问题），继续尝试安装"
    apt-get install -y -qq "${DEPS[@]}" 2>&1 | tail -1 || { err "依赖安装失败"; exit 1; }
    ;;
  yum)
    yum install -y -q "${DEPS[@]}" 2>&1 | tail -1 || { err "依赖安装失败"; exit 1; }
    ;;
esac
info "依赖检查完成"

# ======================== 获取版本 ========================
step_info "获取版本"
VERSION=$(curl -sL --max-time 15 "https://api.github.com/repos/9seconds/mtg/releases/latest" \
  | awk -F'"' '/tag_name/{print $4; exit}' 2>/dev/null)
[ -z "$VERSION" ] && VERSION="v2.2.8"
V="${VERSION#v}"
info "mtg $VERSION"

# ======================== 下载 ========================
step_info "下载 mtg"
URL="https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${V}-${BIN_ARCH}.tar.gz"
TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
curl -fsSL --max-time 60 "$URL" -o "$TMP/pkg.tar.gz" || { err "下载失败: $URL"; exit 1; }
tar xzf "$TMP/pkg.tar.gz" -C "$TMP" --strip-components=1 || { err "解压失败"; exit 1; }
[ ! -f "$TMP/mtg" ] && { err "解压后找不到 mtg 二进制"; exit 1; }
install -m 755 "$TMP/mtg" "$BIN"

# 验证二进制可用
$BIN --version &>/dev/null || { err "安装的 mtg 二进制不可执行"; exit 1; }
info "已安装: $($BIN --version | head -1)"

# ======================== 获取公网 IP ========================
step_info "检测公网 IP"
PUBLIC_IPV4=""
for src in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://checkip.amazonaws.com"; do
  v4=$(curl -s4 --max-time 5 "$src" 2>/dev/null || true)
  if [ -n "$v4" ] && echo "$v4" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    PUBLIC_IPV4="$v4"; break
  fi
done
[ -n "$PUBLIC_IPV4" ] && info "IPv4: $PUBLIC_IPV4" || warn "未检测到公网 IPv4"

PUBLIC_IPV6=""
for src in "https://api6.ipify.org" "https://ipv6.icanhazip.com"; do
  v6=$(curl -s6 --max-time 5 "$src" 2>/dev/null || true)
  if [ -n "$v6" ] && [ "${v6#*%}" = "$v6" ]; then
    PUBLIC_IPV6="$v6"; break
  fi
done
[ -n "$PUBLIC_IPV6" ] && info "IPv6: $PUBLIC_IPV6" || warn "未检测到公网 IPv6"

# ======================== 伪装域名 ========================
step_info "伪装域名"
DOMAIN=""
if [ -t 0 ]; then
  echo "  建议选跟你 VPS 同厂商的域名，流量更像真实 HTTPS"
  echo "  例: digitalocean.com aws.amazon.com google.com cloudflare.com"
  echo "       azure.microsoft.com vultr.com linode.com hetzner.com"
  read -r -p "  伪装域名 (默认 cloudflare.com): " DOMAIN || true
fi
[ -z "$DOMAIN" ] && DOMAIN="cloudflare.com"
info "伪装域名: $DOMAIN"

# ======================== Secret ========================
step_info "生成 Secret"
SECRET=$($BIN generate-secret "$DOMAIN" 2>/dev/null)
if [ -z "$SECRET" ]; then
  SECRET=$($BIN generate-secret cloudflare.com 2>/dev/null)
  warn "域名 $DOMAIN 验证失败，已回退 cloudflare.com"
fi
[ -z "$SECRET" ] && { err "Secret 生成失败"; exit 1; }
info "Secret: $SECRET"

# ======================== IP 模式 ========================
step_info "IP 模式"
if [ -t 0 ]; then
  echo ""
  echo "  [1] IPv4 仅 (默认，兼容性最好)"
  echo "  [2] IPv6 仅"
  echo "  [3] 双栈 (IPv4+IPv6)"
  read -r -t 15 -p "  选择 [1-3] (默认 1): " ip_choice || ip_choice=""
fi
case "${ip_choice:-1}" in
  2) IP_MODE="v6"     ;;
  3) IP_MODE="dual"   ;;
  *) IP_MODE="v4"     ;;
esac

# 双栈模式兜底
if [ "$IP_MODE" = "dual" ] && [ -z "$PUBLIC_IPV6" ]; then
  warn "未检测到 IPv6，降级为 IPv4 仅"
  IP_MODE="v4"
fi
if [ "$IP_MODE" = "v6" ] && [ -z "$PUBLIC_IPV6" ]; then
  err "未检测到 IPv6，无法使用 IPv6 模式"
  exit 1
fi

case "$IP_MODE" in
  v4)   BIND_HINT="0.0.0.0:端口"     ;;
  v6)   BIND_HINT="[::]:端口"         ;;
  dual) BIND_HINT="[::]:端口"         ;;
esac
info "模式: $IP_MODE → $BIND_HINT"

# ======================== 端口 ========================
step_info "端口"
DEFAULT_PORT=443
if [ -t 0 ]; then
  echo ""
  echo "  [1] 443  (推荐)"
  echo "  [2] 8443"
  echo "  [3] 3128"
  echo "  [4] 自定义"
  read -r -t 15 -p "  选择 [1-4] (默认 1): " PORT_CHOICE || PORT_CHOICE=""
fi
case "${PORT_CHOICE:-1}" in
  2) PORT=8443  ;;
  3) PORT=3128  ;;
  4)
    if [ -t 0 ]; then
      read -r -p "  输入端口: " PORT
    else
      PORT=$DEFAULT_PORT
    fi
    ;;
  *) PORT=$DEFAULT_PORT ;;
esac
: "${PORT:=$DEFAULT_PORT}"

# 端口占用检测
PORT_IN_USE=0
if command -v ss &>/dev/null; then
  ss -tlnp "sport = :$PORT" 2>/dev/null | grep -q LISTEN && PORT_IN_USE=1
elif command -v netstat &>/dev/null; then
  netstat -tlnp 2>/dev/null | grep -q ":$PORT " && PORT_IN_USE=1
fi
if [ "$PORT_IN_USE" -eq 1 ]; then
  warn "端口 $PORT 已被占用"
  if [ -t 0 ]; then
    read -r -p "  输入其他端口，或直接回车保持 $PORT: " NEW_PORT
    [ -n "$NEW_PORT" ] && PORT="$NEW_PORT"
  fi
fi
info "端口: $PORT"

# 计算绑定地址和 IP 偏好
case "$IP_MODE" in
  v4)   BIND="0.0.0.0:$PORT";  PREFER="only-ipv4"   ;;
  v6)   BIND="[::]:$PORT";      PREFER="only-ipv6"   ;;
  dual) BIND="[::]:$PORT";      PREFER="prefer-ipv6" ;;
esac

# ======================== 写入配置 ========================
step_info "配置"
cat > /etc/mtg.toml <<EOF
secret = "$SECRET"
bind-to = "$BIND"
debug = false
concurrency = 8192
prefer-ip = "$PREFER"
dns = "https://1.1.1.1"
tolerate-time-skewness = "5s"

[defense.anti-replay]
max-size = "1mib"

[defense.blocklist]
urls = [ "https://iplists.firehol.org/files/firehol_level1.netset" ]
update-each = "24h"

[stats.prometheus]
enabled = true
bind-to = "127.0.0.1:9999"
EOF
[ -n "$PUBLIC_IPV4" ] && echo "public-ipv4 = \"$PUBLIC_IPV4\"" >> /etc/mtg.toml
[ -n "$PUBLIC_IPV6" ] && echo "public-ipv6 = \"$PUBLIC_IPV6\"" >> /etc/mtg.toml

# 保存安装参数（供 mtg-quick 管理命令读取）
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/setup.conf" <<EOF
PORT=$PORT
SECRET=$SECRET
DOMAIN=$DOMAIN
IP_MODE=$IP_MODE
EOF
info "配置已写入 /etc/mtg.toml"

# ======================== 验证 ========================
step_info "验证配置"
$BIN doctor /etc/mtg.toml 2>&1 | sed 's/^/  /' || warn "doctor 有警告（不影响运行）"

# ======================== 安装服务 ========================
step_info "服务"
if [ "$INIT" = "systemd" ]; then
  # 检测 systemd 版本——DynamicUser 需要 v235+
  SYSTEMD_VER=$(systemctl --version 2>/dev/null | head -1 | grep -oP '\d+' | head -1 || echo 0)
  cat > /etc/systemd/system/mtg.service <<UNIT
[Unit]
Description=mtg - MTProto proxy server
Documentation=https://github.com/9seconds/mtg
After=network.target

[Service]
ExecStart=$BIN run /etc/mtg.toml
Restart=always
RestartSec=3
$(if [ "$SYSTEMD_VER" -ge 235 ] 2>/dev/null; then
  echo "DynamicUser=true"
  echo "AmbientCapabilities=CAP_NET_BIND_SERVICE"
fi)
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable mtg 2>/dev/null || true
  systemctl start mtg 2>/dev/null || { err "服务启动失败"; journalctl -u mtg -n 20 --no-pager; exit 1; }
  # 轮询等待最多 10 秒
  i=0; while [ $i -lt 10 ]; do systemctl is-active --quiet mtg && break; sleep 1; i=$((i+1)); done
  systemctl is-active --quiet mtg || { err "mtg 未运行"; journalctl -u mtg -n 30 --no-pager; exit 1; }

elif [ "$INIT" = "openrc" ]; then
  cat > /etc/init.d/mtg <<'INIT'
#!/sbin/openrc-run
name="mtg"
description="MTProto proxy"
command="/usr/local/bin/mtg"
command_args="run /etc/mtg.toml"
command_background=true
pidfile="/run/mtg.pid"
respawn_delay=5
respawn_max=0
rc_ulimit="-n 65536"

depend() {
  need net
  after firewall
}
INIT
  chmod +x /etc/init.d/mtg
  rc-update add mtg default 2>/dev/null || true
  rc-service mtg restart 2>/dev/null || { err "服务启动失败"; tail -10 /var/log/mtg.log 2>/dev/null; exit 1; }
  i=0; while [ $i -lt 10 ]; do rc-service mtg status 2>/dev/null | grep -q "started" && break; sleep 1; i=$((i+1)); done
  rc-service mtg status 2>/dev/null | grep -q "started" || { err "mtg 未运行"; tail -20 /var/log/mtg.log 2>/dev/null; exit 1; }
fi
info "服务已运行，已设置开机自启"

# ======================== 防火墙 ========================
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qi active; then
  ufw allow "$PORT/tcp" comment 'mtg-proxy' 2>/dev/null && info "UFW 已放行端口 $PORT" || true
fi
if command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
  firewall-cmd --permanent --add-port="$PORT/tcp" 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
  info "firewalld 已放行端口 $PORT"
fi

# ======================== 注册管理命令 ========================
# 管道安装时 $0=/dev/fd/63，硬复制一份到 /usr/local/bin
if [ "$0" != "/usr/local/bin/mtg-quick" ] && [ "$0" != "/bin/mtg-quick" ] && [ ! -f /usr/local/bin/mtg-quick ]; then
  curl -fsSL "$SELF_URL" -o /usr/local/bin/mtg-quick 2>/dev/null && chmod +x /usr/local/bin/mtg-quick
fi

# ======================== 输出链接 ========================
echo ""
echo "━━━ MTG 部署完成 ━━━"
echo ""
{
  [ "$IP_MODE" != "v6" ] && [ -n "$PUBLIC_IPV4" ] && echo "tg://proxy?server=$PUBLIC_IPV4&port=$PORT&secret=$SECRET"
  [ "$IP_MODE" != "v4" ] && [ -n "$PUBLIC_IPV6" ] && echo "tg://proxy?server=$PUBLIC_IPV6&port=$PORT&secret=$SECRET"
}
echo ""
echo "  Secret: $SECRET"
echo "  端口:   $PORT"
echo "  伪装:   $DOMAIN"
echo "  IP:     $([ -n "$PUBLIC_IPV4" ] && echo -n "$PUBLIC_IPV4 ")$([ -n "$PUBLIC_IPV6" ] && echo -n "$PUBLIC_IPV6")"
echo ""
echo "把上面的 tg://proxy 链接发到 Telegram 即可使用 🚀"
echo "管理命令: mtg-quick uninstall   # 一键卸载"
echo ""
