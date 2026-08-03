# VPS Skills

🤖 Robot × Human 开源 Skills 技能库

## 关于

由 **Robot** 🤖 和 **lukankan123** 👤 共同开发维护的开源 Skills 技能库，所有技能都来自真实生产环境的实战验证。

## 理念

- 🚀 **简单易用** — 面向普通用户，降低使用门槛
- 🔒 **安全可靠** — 所有技能经过安全设计
- 💡 **实用为主** — 解决实际问题，注重效率
- 🌱 **持续更新** — 不断迭代完善，欢迎反馈

## 技能列表

### 🔐 安全防护

#### vps-security — VPS 基础安全防护（v2.0）

为 Ubuntu/Debian VPS 提供一键式安全加固：

- 🔐 SSH 硬化（自定义端口、仅密钥登录、限制尝试次数）
- 🔥 UFW 防火墙（默认拒绝入站，支持 `--strict` 出站白名单）
- 🚫 fail2ban **9 个 jail**（SSH 暴力破解 + Nginx 扫描检测 6 类 + 限流联动）
- 🌐 Nginx 加固（隐藏版本号、19 种恶意 UA 黑名单、敏感路径 deny、限流、幽灵域名 444）
- 🧠 内核加固（关闭 unprivileged userns，防 DirtyFrag / Bad Epoll 提权）
- 🔍 每日安全巡检（登录审计 / Nginx 扫描 / 资源 / SSL 证书到期）

**文档：** [中文](skills/vps-security/SKILL.md) · [English](skills/vps-security/SKILL.en.md)

**快速开始：**
```bash
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --port 13521 --email your@email.com
```

**适用系统：** Ubuntu 20.04+ / Debian 11+

## 目录结构

```
skills/
├── vps-security/                 # VPS 安全防护
│   ├── SKILL.md                  # 中文文档
│   ├── SKILL.en.md               # 英文文档
│   └── scripts/
│       └── vps-secure.sh         # v2.0 加固脚本（561 行）
└── README.md
```

## 许可

MIT License - 可自由使用、修改、分发
