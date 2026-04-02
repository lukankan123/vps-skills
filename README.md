# VPS Skills

开源 VPS 安全防护技能集合 🤖

## 关于

本项目收集和整理实用的 VPS 安全防护技能，帮助普通用户快速配置服务器安全。

## 技能列表

### 🔐 vps-security - VPS 基础安全防护

为 VPS 提供一键安全配置，包括：

- 修改 SSH 默认端口（防扫描）
- 配置 SSH 公钥认证
- 智能防火墙（UFW/iptables）
- fail2ban 防暴力破解（7天封禁）
- 每日安全巡检（自动封禁异常IP）

**适用系统：** Ubuntu 20.04+ / Debian 11+

**使用方法：** 将 `skills/vps-security/SKILL.md` 复制到 OpenClaw 的 `skills/` 目录

**详细文档：** [skills/vps-security/SKILL.md](skills/vps-security/SKILL.md)

## 贡献

欢迎提交 Issue 和 Pull Request！

## 开源协议

MIT License
