# MTG Quick — MTPROTO 代理一键部署

在 Linux VPS 上一键部署 [mtg](https://github.com/9seconds/mtg) Telegram MTPROTO 代理。

## 用法

```bash
bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh)
```

卸载：

```bash
bash <(curl -sL https://raw.githubusercontent.com/bababoyi6/nihao/main/mtg-quick.sh) uninstall
```

## 工作原理

1. 从 [9seconds/mtg](https://github.com/9seconds/mtg/releases) GitHub Releases 下载对应架构的二进制
2. 根据 VPS 公网 IP 反查厂商，选匹配的伪装域名（DigitalOcean/AWS/GCP/Vultr/Hetzner 等）
3. 用 `mtg generate-secret <domain>` 生成 FakeTLS Secret
4. 写入 TOML 配置，安装 systemd 服务
5. 运行 `mtg doctor` 验证配置
6. 输出 `tg://proxy?` 链接和二维码

## 管理

```bash
systemctl status mtg                      # 状态
systemctl restart mtg                     # 重启
journalctl -u mtg -n 30 -f                # 日志
/usr/local/bin/mtg doctor /etc/mtg.toml   # 诊断
```

## 原项目

[9seconds/mtg](https://github.com/9seconds/mtg) — Highly opinionated MTPROTO proxy for Telegram
