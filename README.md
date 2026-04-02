# VPS Skills

🤖 开源 Skills 技能集合

## 关于

本项目收集和整理实用的 Skills 技能，帮助用户快速实现各种自动化功能。

## 技能列表

### 🔐 安全防护类

#### vps-security - VPS 基础安全防护
- SSH 端口修改（防扫描）
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
