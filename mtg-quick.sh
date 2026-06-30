#!/usr/bin/env bash
# ==============================================================
#  MTG (MTPROTO Proxy) 一键部署脚本
#  项目: https://github.com/9seconds/mtg
#  用法: bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/mtg-quick/main/mtg-quick.sh)
#  卸载: bash <(curl -sL ...) uninstall
# ==============================================================

set -o pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

FAILED=0
fail_handler() {
  if [ $? -ne 0 ] && [ $FAILED -eq 0 ]; then
    : # 由各步骤自行处理错误
  fi
}
trap fail_handler EXIT

# ---------- 卸载模式 ----------
if [ "${1:-}" = "uninstall" ]; then
  step "卸载 mtg"
  systemctl stop mtg 2>/dev/null || true
  systemctl disable mtg 2>/dev/null || true
  rm -f /etc/systemd/system/mtg.service
  systemctl daemon-reload
  rm -f /usr/local/bin/mtg /etc/mtg.toml
  info "mtg 已卸载"
  exit 0
fi

# ---------- Root 检查 ----------
if [ "$(id -u)" -ne 0 ]; then
  err "请以 root 运行 (sudo -i 或 su -)"
  exit 1
fi

# ---------- 系统检测 ----------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="linux-amd64"      ;;
  aarch64) BIN_ARCH="linux-arm64"       ;;
  armv7l)  BIN_ARCH="linux-armv7"       ;;
  armv6l)  BIN_ARCH="linux-armv6"       ;;
  armv5*)  BIN_ARCH="linux-armv5"       ;;
  i386|i686) BIN_ARCH="linux-386"       ;;
  mips)    BIN_ARCH="linux-mips"        ;;
  mipsle)  BIN_ARCH="linux-mipsle"      ;;
  *)
    err "不支持的架构: $ARCH"
    exit 1
    ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [ "$OS" != "linux" ]; then
  err "仅支持 Linux (当前: $OS)"
  exit 1
fi

# ---------- 预检查必要工具 ----------
step "预检查"
NEEDS="curl"
MISSING=""
for cmd in $NEEDS; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING="$MISSING $cmd"
  fi
done
if [ -n "$MISSING" ]; then
  err "缺少命令:$MISSING，请先安装"
  exit 1
fi
info "系统: $ARCH, $OS"

# 检查端口探测命令
PORT_CHECK="ss"
if ! command -v ss &>/dev/null; then
  if command -v netstat &>/dev/null; then
    PORT_CHECK="netstat"
  fi
fi
info "端口检测使用: $PORT_CHECK"

# ---------- 获取最新版本 ----------
step "获取最新版本"
LATEST=$(curl -sL --max-time 15 "https://api.github.com/repos/9seconds/mtg/releases/latest" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name',''))" 2>/dev/null || echo "")
if [ -z "$LATEST" ]; then
  # fallback: 写死已知版本
  LATEST="v2.2.8"
  warn "无法从 GitHub API 获取最新版本，使用已知版本 $LATEST"
else
  info "最新版本: $LATEST"
fi

# ---------- 下载 ----------
step "下载 mtg $LATEST"
V="${LATEST#v}"
TARBALL="mtg-${V}-${BIN_ARCH}.tar.gz"
URL="https://github.com/9seconds/mtg/releases/download/${LATEST}/${TARBALL}"

TMP_DIR=$(mktemp -d) || { err "创建临时目录失败"; exit 1; }
trap "rm -rf '$TMP_DIR'" EXIT

if ! curl -fsSL --max-time 60 "$URL" -o "$TMP_DIR/$TARBALL"; then
  err "下载失败: $URL"
  warn "请检查网络或访问 https://github.com/9seconds/mtg/releases 手动下载"
  exit 1
fi

if ! tar xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"; then
  err "解压失败，文件可能损坏"
  exit 1
fi

if [ ! -f "$TMP_DIR/mtg" ]; then
  err "解压后找不到 mtg 二进制"
  exit 1
fi
info "下载解压完成"

# ---------- 安装二进制 ----------
step "安装到 /usr/local/bin/mtg"
install -m 755 "$TMP_DIR/mtg" /usr/local/bin/mtg
INSTALLED_VER=$(/usr/local/bin/mtg --version 2>&1 | head -1)
info "已安装: $INSTALLED_VER"

# ---------- 生成 fake TLS secret ----------
step "生成 Secret（基于伪装域名）"

# 尝试根据 IP 反查 AS 来选择伪装域名
DOMAIN="cloudflare.com"
PUBLIC_IPV4=""
for src in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://checkip.amazonaws.com"; do
  v4=$(curl -s4 --max-time 5 "$src" 2>/dev/null || true)
  if [ -n "$v4" ] && expr "$v4" : '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$' >/dev/null; then
    PUBLIC_IPV4="$v4"
    break
  fi
done
PUBLIC_IPV6=""
for src in "https://api6.ipify.org" "https://ipv6.icanhazip.com"; do
  v6=$(curl -s6 --max-time 5 "$src" 2>/dev/null || true)
  if [ -n "$v6" ] && [ "${v6#*%}" = "$v6" ]; then
    PUBLIC_IPV6="$v6"
    break
  fi
done

if [ -n "$PUBLIC_IPV4" ]; then
  ASN_ORG=$(curl -s4 --max-time 5 "https://ipapi.co/${PUBLIC_IPV4}/org/" 2>/dev/null || true)
  if echo "$ASN_ORG" | grep -qi "digitalocean"; then
    DOMAIN="digitalocean.com"
  elif echo "$ASN_ORG" | grep -qi "aws\|amazon"; then
    DOMAIN="aws.amazon.com"
  elif echo "$ASN_ORG" | grep -qi "google\|gcp\|cloud.google"; then
    DOMAIN="google.com"
  elif echo "$ASN_ORG" | grep -qi "azure\|microsoft"; then
    DOMAIN="azure.microsoft.com"
  elif echo "$ASN_ORG" | grep -qi "vultr"; then
    DOMAIN="vultr.com"
  elif echo "$ASN_ORG" | grep -qi "ovh\|soyoustart\|kimsufi"; then
    DOMAIN="ovh.com"
  elif echo "$ASN_ORG" | grep -qi "linode\|akamai"; then
    DOMAIN="linode.com"
  elif echo "$ASN_ORG" | grep -qi "hetzner"; then
    DOMAIN="hetzner.com"
  elif echo "$ASN_ORG" | grep -qi "oracle\|oracle cloud"; then
    DOMAIN="oracle.com"
  fi
fi
info "伪装域名: $DOMAIN"

SECRET=$(/usr/local/bin/mtg generate-secret "$DOMAIN" 2>&1 || echo "")
if [ -z "$SECRET" ] || [ "${#SECRET}" -lt 20 ]; then
  SECRET=$(/usr/local/bin/mtg generate-secret cloudflare.com 2>&1)
fi
info "Secret: $SECRET"

# ---------- 选择端口 ----------
step "选择端口"
DEFAULT_PORT=443
PORT_PROMPT="选择端口 [1-4] (默认 1): "
echo ""
echo "  [1] 443 (推荐 - 伪装 HTTPS 流量)"
echo "  [2] 8443 (备用 HTTPS)"
echo "  [3] 3128 (HTTP 代理风格)"
echo "  [4] 自定义端口"

# 尝试交互式输入，超时或非 TTY 则用默认
PORT=""
if [ -t 0 ]; then
  read -r -t 10 -p "$PORT_PROMPT" PORT_CHOICE || PORT_CHOICE=""
else
  PORT_CHOICE=""
fi

case "${PORT_CHOICE:-1}" in
  2) PORT=8443  ;;
  3) PORT=3128  ;;
  4)
    if [ -t 0 ]; then
      read -r -p "输入端口号: " PORT
    else
      PORT=$DEFAULT_PORT
    fi
    ;;
  *) PORT=$DEFAULT_PORT ;;
esac
: "${PORT:=$DEFAULT_PORT}"

# 检查端口占用
PORT_IN_USE=0
case "$PORT_CHECK" in
  ss)
    if ss -tlnp "sport = :$PORT" 2>/dev/null | grep -q LISTEN; then
      PORT_IN_USE=1
    fi
    ;;
  netstat)
    if netstat -tlnp 2>/dev/null | grep -q ":$PORT "; then
      PORT_IN_USE=1
    fi
    ;;
esac

if [ "$PORT_IN_USE" -eq 1 ]; then
  warn "端口 $PORT 已被占用"
  if [ -t 0 ]; then
    read -r -p "输入其他端口，或直接回车跳过: " NEW_PORT
    [ -n "$NEW_PORT" ] && PORT="$NEW_PORT"
  else
    warn "非交互模式，继续使用 $PORT（可能冲突）"
  fi
fi
info "监听端口: $PORT"

# ---------- 写入配置 ----------
step "写入配置 /etc/mtg.toml"
cat > /etc/mtg.toml <<TOML
secret = "$SECRET"
bind-to = "[::]:${PORT}"
debug = false
concurrency = 8192
prefer-ip = "prefer-ipv6"
TOML

# 如果有公网 IP，追加（方便 mtg access 命令生成正确链接）
if [ -n "$PUBLIC_IPV4" ]; then
  echo "public-ipv4 = \"$PUBLIC_IPV4\"" >> /etc/mtg.toml
fi
if [ -n "$PUBLIC_IPV6" ]; then
  echo "public-ipv6 = \"$PUBLIC_IPV6\"" >> /etc/mtg.toml
fi

# 追加可选优化
cat >> /etc/mtg.toml <<'TOML'

[stats.prometheus]
enabled = true
bind-to = "127.0.0.1:9999"
TOML

info "配置文件已生成"

# ---------- 配置验证（不阻断） ----------
step "配置验证"
/usr/local/bin/mtg doctor /etc/mtg.toml 2>&1 || warn "doctor 有警告（不影响运行）"

# ---------- systemd 服务 ----------
step "安装 systemd 服务"
cat > /etc/systemd/system/mtg.service <<UNIT
[Unit]
Description=mtg - MTProto proxy server
Documentation=https://github.com/9seconds/mtg
After=network.target

[Service]
ExecStart=/usr/local/bin/mtg run /etc/mtg.toml
Restart=always
RestartSec=5
DynamicUser=true
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

if ! systemctl enable mtg --now 2>/dev/null; then
  err "systemctl enable/start 失败"
  journalctl -u mtg -n 20 --no-pager || true
  exit 1
fi

sleep 2
if ! systemctl is-active --quiet mtg; then
  err "mtg 服务启动失败"
  systemctl status mtg --no-pager || true
  journalctl -u mtg -n 30 --no-pager || true
  exit 1
fi
info "mtg 服务运行中，已设置为开机自启"

# ---------- 防火墙 ----------
step "防火墙"
if command -v ufw &>/dev/null; then
  ufw allow "$PORT/tcp" comment 'mtg-proxy' 2>/dev/null && info "UFW 已放行端口 $PORT" || true
fi
if command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
  firewall-cmd --permanent --add-port="$PORT/tcp" 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
  info "firewalld 已放行端口 $PORT"
fi

# ---------- 生成链接 ----------
step "代理信息"
echo ""
echo -e "${BOLD}${GREEN}========== MTG 代理部署完成 ==========${NC}"
echo ""

ACCESS_OUTPUT=$(/usr/local/bin/mtg access /etc/mtg.toml 2>/dev/null || true)
if [ -n "$ACCESS_OUTPUT" ]; then
  echo "$ACCESS_OUTPUT"
else
  # fallback：手动拼链接
  SECRET_HEX="$SECRET"
  if [ -n "$PUBLIC_IPV4" ]; then
    TG_URL="tg://proxy?server=${PUBLIC_IPV4}&port=${PORT}&secret=${SECRET_HEX}"
    echo -e "${BOLD}IPv4${NC}"
    echo -e "  Telegram: ${CYAN}${TG_URL}${NC}"
    echo -e "  二维码:   ${CYAN}https://api.qrserver.com/v1/create-qr-code/?data=${TG_URL//&/%26}&size=300x300${NC}"
  fi
  if [ -n "$PUBLIC_IPV6" ]; then
    TG_URL6="tg://proxy?server=${PUBLIC_IPV6}&port=${PORT}&secret=${SECRET_HEX}"
    echo -e "${BOLD}IPv6${NC}"
    echo -e "  Telegram: ${CYAN}${TG_URL6}${NC}"
    echo -e "  二维码:   ${CYAN}https://api.qrserver.com/v1/create-qr-code/?data=${TG_URL6//&/%26}&size=300x300${NC}"
  fi
fi

echo ""
echo -e "${BOLD}Secret:${NC}    ${YELLOW}$SECRET${NC}"
echo -e "${BOLD}端口:${NC}      $PORT"
echo -e "${BOLD}伪装域名:${NC}  $DOMAIN"
echo -e "${BOLD}公网 IPv4:${NC} ${PUBLIC_IPV4:-未检测到}"
echo -e "${BOLD}公网 IPv6:${NC} ${PUBLIC_IPV6:-未检测到}"
echo ""
echo -e "${YELLOW}━━━ 管理命令 ━━━${NC}"
echo -e "  状态:  ${GREEN}systemctl status mtg${NC}"
echo -e "  日志:  ${GREEN}journalctl -u mtg -n 30 -f --no-pager${NC}"
echo -e "  重启:  ${GREEN}systemctl restart mtg${NC}"
echo -e "  卸载:  ${GREEN}systemctl stop mtg && systemctl disable mtg && rm -f /etc/systemd/system/mtg.service /usr/local/bin/mtg /etc/mtg.toml && systemctl daemon-reload${NC}"
echo ""
info "部署完毕！把上面的 Telegram 链接发给自己即可使用 🚀"
