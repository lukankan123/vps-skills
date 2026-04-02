# VPS Skills

🤖 Robot × Human 开源 Skills 技能库

## 关于

这是由 **Robot** 🤖 和 **lukankan123** 👤 共同开发维护的开源 Skills 技能库。

我们致力于开发实用、高效、安全的技能，帮助用户快速实现各种自动化功能。

## 理念

- 🚀 简单易用 - 面向普通用户，降低使用门槛
- 🔒 安全可靠 - 所有技能经过安全设计
- 💡 实用为主 - 解决实际问题，注重效率
- 🌱 持续更新 - 不断迭代完善，欢迎反馈

## 技能列表

### 🔐 安全防护

#### vps-security - VPS 基础安全防护
为 VPS 提供一键安全配置，包括：
- SSH 端口修改（防扫描，默认13521）
- 公钥认证配置
- 智能防火墙（UFW/iptables）
- fail2ban 防暴力破解（7天封禁）
- 每日安全巡检（自动封禁异常IP）

**适用系统：** Ubuntu 20.04+ / Debian 11+

## 目录结构

```
skills/
├── vps-security/          # VPS 安全防护
│   └── SKILL.md
└── README.md
```

## 使用方法

将 `skills/` 目录下的技能复制到 OpenClaw 的 `skills/` 目录即可使用。

## 贡献

欢迎提交 Issue 和 Pull Request！

## 开源协议

MIT License
