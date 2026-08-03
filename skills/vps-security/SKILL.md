---
name: vps-security
description: VPS 基础安全防护技能 v2.0。为普通用户一键配置 SSH 加固、UFW 防火墙、fail2ban 9 个 jail（含 Nginx 扫描检测）、Nginx 加固、内核加固与每日安全巡检。适用于 Ubuntu/Debian。当用户需要：保护 VPS 安全、配置 SSH 防护、安装防火墙、防暴力破解、Nginx Web 扫描拦截时使用。
---

# VPS 基础安全防护（v2.0）

为 VPS 提供一键式安全加固，v2.0 已把生产环境实战验证过的防护策略整理成通用版，全程自动备份 + 语法检查，不怕把自己锁在门外。

## 功能特性

- 🔐 **SSH 硬化** — 修改默认端口（13521）、禁用密码登录、强制密钥认证、限制尝试次数
- 🔥 **UFW 防火墙** — 默认拒绝入站，支持 `--strict` 出站白名单模式
- 🚫 **fail2ban 9 个 jail** — SSH 暴力破解 + Nginx 扫描检测 6 类 + 机器人搜索 + 429 限流联动
- 🌐 **Nginx 加固** — 隐藏版本号、19 种恶意 UA 拦截、敏感路径 deny、限流、幽灵域名 444
- 🧠 **内核加固** — 关闭 `unprivileged_userns_clone`（防 DirtyFrag / Bad Epoll 本地提权）
- 📋 **日志审计** — 登录记录、失败尝试、封禁记录
- 🔍 **每日安全巡检 v2.0** — 登录审计 / Nginx 扫描 / 资源 / UFW / SSL 证书到期

## 快速开始

```bash
# 一键安装（默认 SSH 端口 13521）
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --port 13521 --email your@email.com
```

或下载脚本后执行：

```bash
sudo bash scripts/vps-secure.sh --port 13521 --email your@email.com
```

完整脚本见 `scripts/vps-secure.sh`（v2.0，561 行）。

## 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` | SSH 端口 | 13521 |
| `--email` | fail2ban/巡检告警邮箱 | root@localhost |
| `--strict` | UFW 出站白名单（仅 DNS/HTTP/HTTPS/NTP/SMTP） | 关闭 |
| `--skip-nginx` | 跳过 Nginx 加固 | 关闭 |
| `--skip-kernel` | 跳过内核加固 | 关闭 |
| `--no-upgrade` | 跳过 apt 系统升级 | 关闭 |

示例：

```bash
# 严格出站白名单 + 自定义端口
sudo bash scripts/vps-secure.sh --port 22022 --email you@email.com --strict

# 纯应用服务器（不装 Nginx）
sudo bash scripts/vps-secure.sh --skip-nginx
```

## 核心步骤

### 1. 系统更新与工具安装

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y ufw fail2ban curl mailutils iptables-persistent
```

### 2. SSH 硬化

```bash
# 修改端口（兼容已有/无 Port 行）
sed -i "s/^#\?Port .*/Port 13521/" /etc/ssh/sshd_config || echo "Port 13521" >> /etc/ssh/sshd_config

# 安全项：密钥认证、禁用密码、限制尝试
for opt in "PermitRootLogin prohibit-password" "PasswordAuthentication no" \
           "PermitEmptyPasswords no" "PubkeyAuthentication yes" \
           "MaxAuthTries 4" "LoginGraceTime 30" "X11Forwarding no"; do
    key="${opt%% *}"; val="${opt#* }"
    sed -i "s|^#\?$key .*|$key $val|" /etc/ssh/sshd_config || echo "$key $val" >> /etc/ssh/sshd_config
done

# ⚠️ 语法检查通过才重启，失败自动回滚备份
sshd -t && systemctl restart sshd
```

### 3. UFW 防火墙

```bash
ufw default deny incoming
ufw default allow outgoing          # 或 --strict 白名单模式
ufw allow 13521/tcp                 # 先放行 SSH 新端口！
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp                   # QUIC/HTTP3
echo "y" | ufw enable
```

**`--strict` 出站白名单模式：** 默认 deny outgoing，仅放行 `53/80/123/443/25/587`（DNS/HTTP/HTTPS/NTP/SMTP）。

### 4. fail2ban（9 个 jail）

关键配置：`backend = polling`（适配 nginx 日志）、`dbpurgeage = 0`（重启不丢封禁记录）。

| Jail | 监控目标 | 封禁策略 |
|------|---------|---------|
| `sshd` / `sshd-ddos` | SSH 暴力破解 | 4 次失败封 7 天 |
| `nginx-envscan` | `.env`/`.git`/`.aws` 扫描 | **永久封禁**（bantime=-1） |
| `nginx-secscan` | 综合安全扫描（22 种模式） | 7 天 |
| `nginx-wpscan` | WordPress 漏洞扫描 | **1 次即封**（防 IPv6 单扫） |
| `nginx-phpscan` | PHP 漏洞扫描 | 7 天 |
| `nginx-botsearch` | 机器人搜索 | 7 天 |
| `nginx-bad-request` | 恶意请求（SQLi/路径穿越） | 7 天 |
| `nginx-http-auth` | HTTP 认证暴力 | 7 天 |
| `nginx-ratelimit` | 429 限流联动 | 5 次/5 分钟封 1 小时 |

脚本会自动写入 8 个 filter 文件（`/etc/fail2ban/filter.d/`）和 `jail.local`。未装 Nginx 时自动只启用 sshd jail，避免 logpath 不存在报错。

### 5. Nginx 加固

**隐藏版本号：**
```nginx
# nginx.conf http 块
server_tokens off;
```

**恶意 UA 黑名单（map 指令，http 块）：**
```nginx
map $http_user_agent $bad_bot {
    default 0;
    ~*pathscan 1;  ~*zgrab 1;  ~*nmap 1;  ~*masscan 1;
    ~*sqlmap 1;    ~*nikto 1;  ~*gobuster 1; ~*dirbuster 1;
    ~*wpscan 1;    ~*nessus 1; ~*acunetix 1; ~*whatweb 1;
    ~*hydra 1;     ~*medusa 1; ~*jorgee 1;   ~*fimap 1;
    ~*"ZmEu" 1;
}
```

**server 级加固片段（每个 server 块 include）：**
```nginx
if ($bad_bot) { return 444; }   # 恶意 UA 直接断连

# 敏感路径拒绝
location ~ /\.(git|env|md|aws|svn|hg|htaccess|htpasswd|DS_Store) {
    deny all; access_log off; log_not_found off; return 444;
}
location ~ \.(sql|bak|tar|gz|zip|log|ini|conf|old|swp)$ {
    deny all; access_log off; log_not_found off;
}

# 限流：全局 10 请求/秒 + 单 IP 并发 10
limit_req zone=global_limit burst=20 nodelay;
limit_conn addr_limit 10;
```

**限流区（http 块）：**
```nginx
limit_req_zone $binary_remote_addr zone=global_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=sensitive_limit:10m rate=3r/m;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_conn_zone $binary_remote_addr zone=addr_limit:10m;
```

**幽灵域名 444（default_server）：**
```nginx
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    location ~ /\.(git|env|md) { deny all; }
    location / { return 444; }
}
```

### 6. 内核加固

```bash
echo "kernel.unprivileged_userns_clone=0" >> /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf
# 验证
cat /proc/sys/kernel/unprivileged_userns_clone   # 应为 0
```

关闭非特权用户创建 namespace，切断 DirtyFrag / Bad Epoll 系列本地提权路径。Docker 以 root 运行不受影响。

### 7. 每日安全巡检 v2.0

脚本写入 `/usr/local/bin/security-scan.sh`，crontab 每天 2:00 执行，检查项：

1. **登录失败检测** — 今日失败 ≥3 次的 IP 自动封禁
2. **Nginx 扫描检测** — 今日 `.env`/`.git`/`wp-login`/`phpmyadmin`/`actuator` 等敏感路径请求 TOP
3. **fail2ban 封禁统计** — 各 jail 当前封禁数
4. **系统资源** — 负载 / 磁盘 / 内存
5. **UFW 状态**
6. **SSL 证书到期** — 剩余天数（有 certbot 时）

日志：`/var/log/security-scan.log`

### 8. 日志审计（手动）

```bash
last -20                                    # 最近登录
grep "Failed password" /var/log/auth.log | tail -20   # 失败尝试
fail2ban-client banned                      # 全部封禁列表
grep -E "(\.env|\.git)" /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -rn   # 扫描者
```

## ⚠️ 操作前必读

1. **保持一个 SSH 会话不要关闭**，直到用新端口验证能连上
2. 建议配合云控制台（腾讯云/阿里云 VNC）一起操作，连不上时可用 VNC 恢复
3. 脚本全程自动备份（`*.bak.时间戳`），SSH 改错会自动回滚
4. 安装前确保已有 SSH 公钥登录配置

## 验证命令

```bash
grep "^Port" /etc/ssh/sshd_config          # SSH 端口
ufw status verbose                          # 防火墙
fail2ban-client status                      # 9 个 jail
curl -o /dev/null -w "%{http_code}" http://127.0.0.1/.env   # 敏感路径 → 403/444
cat /proc/sys/kernel/unprivileged_userns_clone               # 内核 → 0
bash /usr/local/bin/security-scan.sh        # 手动巡检
```

## 回滚命令

```bash
# SSH 恢复默认
sed -i 's/^Port.*$/Port 22/' /etc/ssh/sshd_config && systemctl restart sshd

# 防火墙关闭
ufw disable
systemctl stop fail2ban

# 内核恢复
sysctl -w kernel.unprivileged_userns_clone=1
```

## 适用系统

- ✅ Ubuntu 20.04+ / 22.04+ / 24.04+
- ✅ Debian 11+ / 12+
