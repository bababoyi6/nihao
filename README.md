# MTG Quick — MTPROTO 代理一键部署脚本

一键在 Linux VPS 上部署 [mtg](https://github.com/9seconds/mtg)（MTPROTO Telegram 代理）。

## 用法

### 部署
```bash
bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh)
```
粘贴到 SSH 执行即可。支持交互选端口，非交互环境自动用 443。

### 卸载
```bash
bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh) uninstall
```

## 脚本功能

- 自动检测 CPU 架构，从 GitHub Releases 下载对应 mtg 二进制
- 自动检测公网 IPv4/IPv6
- 根据 VPS 厂商自动选择 Telgram 伪装域名（DigitalOcean/AWS/GCP/Vultr/Hetzner 等）
- 生成 FakeTLS Secret
- 交互选择端口（默认 443），非交互自动默认
- 写入配置、安装 systemd 服务（开机自启 + 自动重启）
- 自动放行防火墙（UFW / firewalld）
- 输出可直接点击的 tg:// 代理链接和二维码链接

## 管理命令

```bash
systemctl status mtg          # 查看状态
systemctl restart mtg         # 重启
journalctl -u mtg -n 30 -f    # 查看实时日志
/usr/local/bin/mtg doctor /etc/mtg.toml  # 诊断配置
```

## 原项目

- [9seconds/mtg](https://github.com/9seconds/mtg)
- 最新版本: v2.2.8
