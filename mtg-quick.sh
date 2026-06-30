#!/usr/bin/env bash
# ==============================================================
#  MTG (MTPROTO Proxy) 一键部署脚本
#  项目: https://github.com/9seconds/mtg
#  用法: bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh)
#  卸载: bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh) uninstall
# ==============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---------- 卸载 ----------
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
  err "请以 root 运行（sudo -i 或 su -）"
  exit 1
fi

# ---------- 架构检测 ----------
step "系统检测"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="linux-amd64"    ;;
  aarch64) BIN_ARCH="linux-arm64"     ;;
  armv7l)  BIN_ARCH="linux-armv7"     ;;
  armv6l)  BIN_ARCH="linux-armv6"     ;;
  i386|i686) BIN_ARCH="linux-386"     ;;
  mips)    BIN_ARCH="linux-mips"      ;;
  mipsle)  BIN_ARCH="linux-mipsle"    ;;
  *)
    err "不支持的架构: $ARCH"
    exit 1
    ;;
esac

if [ "$(uname -s)" != "Linux" ]; then
  err "仅支持 Linux"
  exit 1
fi
info "架构: $ARCH"

# ---------- 获取最新版本 ----------
step "获取最新版本"
LATEST=$(curl -sL --max-time 15 "https://api.github.com/repos/9seconds/mtg/releases/latest" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null)
if [ -z "$LATEST" ]; then
  LATEST="v2.2.8"
  warn "无法获取最新版本，使用 $LATEST"
fi
V="${LATEST#v}"
info "版本: $LATEST"

# ---------- 下载 ----------
step "下载 mtg"
URL="https://github.com/9seconds/mtg/releases/download/${LATEST}/mtg-${V}-${BIN_ARCH}.tar.gz"
TMP_DIR=$(mktemp -d) || { err "创建临时目录失败"; exit 1; }
trap "rm -rf '$TMP_DIR'" EXIT

curl -fsSL --max-time 60 "$URL" -o "$TMP_DIR/pkg.tar.gz" || { err "下载失败"; exit 1; }

# 注意: 官方 tar.gz 解压后是 mtg-版本/ 目录，需 strip 顶层目录
tar xzf "$TMP_DIR/pkg.tar.gz" -C "$TMP_DIR" --strip-components=1 || { err "解压失败"; exit 1; }
[ ! -f "$TMP_DIR/mtg" ] && { err "找不到 mtg 二进制"; exit 1; }

install -m 755 "$TMP_DIR/mtg" /usr/local/bin/mtg
info "已安装: $(/usr/local/bin/mtg --version | head -1)"

# ---------- 获取公网 IP ----------
step "网络检测"
PUBLIC_IPV4=""
for src in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://checkip.amazonaws.com"; do
  v4=$(curl -s4 --max-time 5 "$src" 2>/dev/null || true)
  if [ -n "$v4" ] && expr "$v4" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
    PUBLIC_IPV4="$v4"; break
  fi
done
[ -n "$PUBLIC_IPV4" ] && info "IPv4: $PUBLIC_IPV4" || warn "未检测到 IPv4"

PUBLIC_IPV6=""
for src in "https://api6.ipify.org" "https://ipv6.icanhazip.com"; do
  v6=$(curl -s6 --max-time 5 "$src" 2>/dev/null || true)
  if [ -n "$v6" ] && [ "${v6#*%}" = "$v6" ]; then
    PUBLIC_IPV6="$v6"; break
  fi
done
[ -n "$PUBLIC_IPV6" ] && info "IPv6: $PUBLIC_IPV6" || warn "未检测到 IPv6"

# ---------- 选择伪装域名 ----------
step "选择伪装域名"
DOMAIN=""
if [ -t 0 ]; then
  echo ""
  echo "  例: digitalocean.com / aws.amazon.com / google.com / cloudflare.com"
  echo "  建议选一个跟你 VPS 同厂商的域名，流量更像真实 HTTPS"
  read -r -p "伪装域名: " DOMAIN || true
fi
if [ -z "$DOMAIN" ]; then
  DOMAIN="cloudflare.com"
  warn "未输入，默认使用 cloudflare.com"
fi
info "伪装域名: $DOMAIN"

step "生成 Secret"
SECRET=$(/usr/local/bin/mtg generate-secret "$DOMAIN" 2>/dev/null)
if [ -z "$SECRET" ]; then
  SECRET=$(/usr/local/bin/mtg generate-secret cloudflare.com 2>/dev/null)
  warn "域名生成失败，已回退 cloudflare.com"
fi
info "Secret: $SECRET"

# ---------- 选择端口 ----------
step "选择端口"
DEFAULT_PORT=443
PORT_CHOICE=
if [ -t 0 ]; then
  echo ""
  echo "  [1] 443  （推荐，伪装 HTTPS）"
  echo "  [2] 8443"
  echo "  [3] 3128"
  echo "  [4] 自定义"
  read -r -t 10 -p "端口 [1-4]（默认 1）: " PORT_CHOICE || PORT_CHOICE=
fi

case "${PORT_CHOICE:-1}" in
  2) PORT=8443  ;;
  3) PORT=3128  ;;
  4)
    if [ -t 0 ]; then
      read -r -p "输入端口: " PORT
    else
      PORT=$DEFAULT_PORT
    fi
    ;;
  *) PORT=$DEFAULT_PORT ;;
esac
: "${PORT:=$DEFAULT_PORT}"
info "端口: $PORT"

# ---------- 写配置 ----------
step "写入配置 /etc/mtg.toml"
cat > /etc/mtg.toml <<EOF
secret = "$SECRET"
bind-to = "[::]:${PORT}"
debug = false
concurrency = 8192
prefer-ip = "prefer-ipv6"
EOF
[ -n "$PUBLIC_IPV4" ] && echo "public-ipv4 = \"$PUBLIC_IPV4\"" >> /etc/mtg.toml
[ -n "$PUBLIC_IPV6" ] && echo "public-ipv6 = \"$PUBLIC_IPV6\"" >> /etc/mtg.toml
info "配置已写入"

# ---------- 验证配置 ----------
/usr/local/bin/mtg doctor /etc/mtg.toml 2>&1 | sed 's/^/  /' || warn "doctor 有警告（不影响运行）"

# ---------- systemd ----------
step "安装系统服务"
cat > /etc/systemd/system/mtg.service <<UNIT
[Unit]
Description=mtg - MTProto proxy server
Documentation=https://github.com/9seconds/mtg
After=network.target

[Service]
ExecStart=/usr/local/bin/mtg run /etc/mtg.toml
Restart=always
RestartSec=3
DynamicUser=true
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable mtg --now 2>/dev/null || { err "服务启动失败"; journalctl -u mtg -n 20 --no-pager; exit 1; }

for i in 1 2 3 4 5 6 7 8 9 10; do
  systemctl is-active --quiet mtg && break
  sleep 1
done
systemctl is-active --quiet mtg || { err "mtg 未运行"; journalctl -u mtg -n 30 --no-pager; exit 1; }
info "服务运行中，已设置开机自启"

# ---------- 防火墙 ----------
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qi active; then
  ufw allow "$PORT/tcp" comment 'mtg-proxy' 2>/dev/null && info "UFW 已放行端口 $PORT" || true
fi
if command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
  firewall-cmd --permanent --add-port="$PORT/tcp" 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
  info "firewalld 已放行端口 $PORT"
fi

# ---------- 输出链接 ----------
step "代理信息"
echo ""
echo -e "${BOLD}${GREEN}========== MTG 代理部署完成 ==========${NC}"
echo ""

/usr/local/bin/mtg access /etc/mtg.toml 2>/dev/null || {
  # fallback: 手动生成
  S=$SECRET
  [ -n "$PUBLIC_IPV4" ] && echo -e "IPv4: ${CYAN}tg://proxy?server=$PUBLIC_IPV4&port=$PORT&secret=$S${NC}"
  [ -n "$PUBLIC_IPV6" ] && echo -e "IPv6: ${CYAN}tg://proxy?server=$PUBLIC_IPV6&port=$PORT&secret=$S${NC}"
}

echo ""
echo -e "  ${BOLD}Secret:${NC}  $SECRET"
echo -e "  ${BOLD}端口:${NC}    $PORT"
echo -e "  ${BOLD}伪装域名:${NC} $DOMAIN"
echo ""
echo -e "${YELLOW}━━━ 管理 ━━━${NC}"
echo -e "  ${GREEN}systemctl status mtg${NC}         查看状态"
echo -e "  ${GREEN}journalctl -u mtg -n 30 -f${NC}   实时日志"
echo -e "  ${GREEN}systemctl restart mtg${NC}         重启"
echo -e "  ${GREEN}bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh) uninstall${NC}  卸载"
echo ""
info "把上面的 tg://proxy 链接发到 Telegram 即可使用 🚀"
