轻量 VPS 状态监控脚本，支持 Ubuntu 22.04/24.04 和 Debian 12。

脚本直接通过 Telegram Bot API 发送通知，无需部署 Cloudflare Worker、数据库或中央控制器，也不提供远程重启、关机等高风险控制功能。每台 VPS 只运行短暂的 systemd 定时任务，没有常驻监控进程。

一键安装：

```bash
curl -fsSL https://raw.githubusercontent.com/bababoyi6/nihao/main/TG-check-notify.sh | sudo bash
```

安装时需要输入服务器名称和 Bot Token，并通过机器人发送的一次性启动链接绑定 Telegram 私聊。机器人不能配置 Webhook，也不能同时被其他程序读取消息；绑定完成后脚本只使用它发送通知。

安装后会自动执行：

- 每 5 分钟采集一次网卡流量和 CPU 计数。
- 每天中午 12:00（服务器本地时间）发送昨天的 TB 流量、平均速度和平均 CPU 利用率。
- 每周一 12:10 发送上一周流量及环比，每月发送上一月流量和平均 CPU 利用率。
- VPS 启动恢复后发送提醒。
- SSH 登录成功时发送登录用户、来源 IP 和时间。
- 每天检查一次 GitHub 更新；下载内容会经过版本、大小、脚本语法和 SHA-256 校验。

常用命令：

```bash
sudo vps-monitor status       # 查看运行状态、流量和待发报告
sudo vps-monitor doctor       # 全面自检并一键安全修复
sudo vps-monitor test         # 发送 Telegram 测试消息
sudo vps-monitor report       # 立即补发所有待发日报
sudo vps-monitor weekly       # 立即发送最早一份待发周报
sudo vps-monitor monthly      # 立即发送最早一份待发月报
sudo vps-monitor collect      # 立即采集一次统计数据
sudo vps-monitor rename       # 修改服务器名称
sudo vps-monitor update       # 安全更新或修复当前版本
sudo vps-monitor auto-update  # 立即检查 GitHub，有新版本才更新
vps-monitor --version         # 查看版本
sudo vps-monitor uninstall    # 完全卸载
```

安装损坏、命令入口缺失时，可使用一键卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/bababoyi6/nihao/main/TG-check-notify.sh | sudo bash -s -- --uninstall
```

Bot Token、Telegram UID 和统计数据只保存在 VPS 的受限目录中，不会写入源码或普通日志。

日报按服务器本地自然日累计，跨午夜的采集间隔会按时间比例拆分。网络暂时不可用时 systemd 会自动重试，未发送的完整日期会保留等待补发。由旧版升级后无法反推升级前没有保存的每日明细，因此第一份完整日报会从升级后的下一个自然日开始。
