---
name: vps-security
description: VPS 基础安全防护技能。为不懂安全的普通用户自动配置 SSH 端口修改、密钥登录、防火墙（UFW 或 iptables）、fail2ban 防暴力破解，以及 Nginx 恶意扫描检测与拦截。适用于 Ubuntu/Debian 系统。当用户需要：保护 VPS 安全、配置 SSH 防护、安装防火墙、防暴力破解、Nginx Web 扫描拦截时使用。
---

# VPS 基础安全防护（v2.0）

本技能为 VPS 提供基础安全防护，适用于 Ubuntu/Debian 系统。v2.0 已同步生产环境实战策略。

## 功能特性

- 🔐 修改 SSH 默认端口（默认 13521，或 `--random-port` 随机生成高位端口）
- 🔑 自动配置 SSH 公钥认证（禁用密码登录）
- 🛡️ SSH 加密算法现代化（Kex/Cipher/MAC 移除老旧弱算法，只保留安全强度）
- 🔥 智能防火墙（UFW，支持 --strict 出站白名单）
- 🚫 fail2ban 防暴力破解（**9 个 jail**：sshd + nginx 扫描检测 6 类 + botsearch + 限流联动）
- 🌐 Nginx 加固（隐藏版本号 + 恶意 UA 黑名单 + 敏感路径 deny + 限流 + 幽灵域名 444）
- 🧠 内核加固（关闭 unprivileged userns，防 DirtyFrag/Bad Epoll 提权）
- 📋 日志审计（登录记录、失败尝试、封禁记录）
- 🔍 每日安全巡检（登录/Nginx 扫描/资源/证书自动检查）

## 执行脚本

完整脚本见：`scripts/vps-secure.sh`（v2.0，561 行）

### 使用方法

```bash
# 下载并执行（脚本在 scripts/vps-secure.sh）
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --port 13521 --email your@email.com

# 随机高位端口（推荐）—— 生成的端口记录到 /root/ssh_port.txt
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --random-port --email your@email.com

# 或直接在服务器执行脚本内容
sudo bash scripts/vps-secure.sh --port 13521 --email your@email.com
```

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` | SSH 端口（手动指定） | 13521 |
| `--random-port` | 随机生成高位 SSH 端口（40000-60000，带冲突检测，记录到 /root/ssh_port.txt） | 关闭 |
| `--email` | 告警邮箱 | root@localhost |
| `--strict` | UFW 出站白名单模式 | 关闭 |
| `--skip-nginx` | 跳过 Nginx 加固 | 关闭 |
| `--skip-kernel` | 跳过内核加固 | 关闭 |
| `--no-upgrade` | 跳过 apt 升级 | 关闭 |

> 核心步骤细节以 `scripts/vps-secure.sh` v2.0 为准（含 9 个 jail、Nginx 加固、内核加固、升级版巡检）。

## 核心步骤

### 1. 检测现有防火墙

```bash
if sudo iptables -L -n | grep -q "Chain INPUT"; then
  FIREWALL="iptables"
elif command -v ufw &> /dev/null; then
  FIREWALL="ufw"
else
  FIREWALL="none"
fi
```

### 2. 配置 SSH

```bash
# 修改端口
SSH_PORT=13521
sudo sed -i "s/^Port 22$/Port $SSH_PORT/" /etc/ssh/sshd_config

# 禁用 Root 登录和密码登录
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sudo sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
```

### 3. 防火墙配置

**UFW：**
```bash
sudo ufw allow $SSH_PORT/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
echo "y" | sudo ufw enable
```

**iptables：**
```bash
sudo iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```

### 4. fail2ban 配置（7天封禁）

```bash
sudo apt-get install -y fail2ban

# 封禁时间：7天 = 604800 秒
sudo cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 604800
findtime = 600
maxretry = 4
destemail = your@email.com
sender = fail2ban@yourserver.com
action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 4
bantime = 604800
chain = INPUT

[sshd-ddos]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 10
bantime = 604800
findtime = 60
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

### 5. 日志审计

定期检查以下日志，及时发现异常：

```bash
# 查看最近登录记录
echo "=== 最近登录记录 ==="
last -20

echo "=== 失败登录尝试 ==="
sudo grep "Failed password" /var/log/auth.log | tail -20

echo "=== fail2ban 封禁记录 ==="
sudo grep "Ban" /var/log/fail2ban.log | tail -10 2>/dev/null || sudo fail2ban-client banned

echo "=== 当前 SSH 端口 ==="
sudo grep "^Port" /etc/ssh/sshd_config

echo "=== 防火墙规则 ==="
sudo iptables -L -n --line-numbers
```

### 6. 每日安全巡检脚本

创建自动巡检脚本，自动封禁异常IP并发送报告：

```bash
# 创建巡检脚本
sudo cat > /usr/local/bin/security-scan.sh << 'SCRIPT'
#!/bin/bash
# VPS 每日安全巡检
# 使用方法：添加到 crontab
# crontab -e
# 0 9 * * * /usr/local/bin/security-scan.sh

LOG_FILE="/var/log/security-scan.log"
ALERT_EMAIL="your@email.com"
BAN_IP=""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== 开始每日安全巡检 =========="

# 1. 检测今日登录失败的IP（3次以上失败）
FAILED_IPS=$(sudo grep "Failed password" /var/log/auth.log | \
    grep "$(date '+%b %d')" | \
    awk '{print $NF}' | sort | uniq -c | \
    awk '$1 >= 3 {print $2}')

if [ -n "$FAILED_IPS" ]; then
    log "检测到可疑IP："
    for IP in $FAILED_IPS; do
        log "  - $IP (失败次数: $(echo $FAILED_IPS | grep $IP | awk '{print $1}'))"
        
        # 获取IP基本信息
        IP_INFO=$(curl -s "http://ip-api.com/json/$IP?fields=country,city,org,isp" 2>/dev/null)
        COUNTRY=$(echo $IP_INFO | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        CITY=$(echo $IP_INFO | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
        ISP=$(echo $IP_INFO | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
        
        log "    国家: ${COUNTRY:-未知}"
        log "    城市: ${CITY:-未知}"
        log "    ISP: ${ISP:-未知}"
        
        # 检查是否已在封禁列表
        if ! sudo fail2ban-client status sshd | grep -q "$IP"; then
            log "    -> 正在封禁此IP..."
            sudo fail2ban-client set sshd banip "$IP" 2>/dev/null
            BAN_IP="$BAN_IP $IP"
        else
            log "    -> 此IP已在封禁列表中"
        fi
    done
else
    log "未检测到异常登录失败"
fi

# 2. 检查当前封禁列表
BANNED=$(sudo fail2ban-client status sshd | grep "Banned IP" | cut -d: -f2 | tr -d ' ')
log "当前封禁IP数量: $(echo $BANNED | wc -w)"
if [ -n "$BANNED" ]; then
    log "封禁IP列表: $BANNED"
fi

# 3. 发送邮件报告
if [ -n "$BAN_IP" ] || [ -n "$FAILED_IPS" ]; then
    REPORT="VPS安全巡检报告 - $(date '+%Y-%m-%d %H:%M:%S')\n\n"
    REPORT+="封禁IP:$BAN_IP\n"
    REPORT+="可疑IP:$FAILED_IPS\n"
    REPORT+="封禁总数:$(echo $BANNED | wc -w)\n"
    echo -e "$REPORT" | mail -s "[VPS安全] 检测到异常登录" "$ALERT_EMAIL"
    log "已发送邮件报告到 $ALERT_EMAIL"
fi

log "========== 巡检完成 =========="
SCRIPT

sudo chmod +x /usr/local/bin/security-scan.sh
log "安全巡检脚本已创建"

# 添加到 crontab（每天早上9点执行）
(crontab -l 2>/dev/null | grep -v "security-scan.sh"; echo "0 9 * * * /usr/local/bin/security-scan.sh") | crontab -
log "已添加定时任务：每天9点自动巡检"
```

⚠️ **操作前必读：**

1. **保持一个 SSH 会话不要关闭**，直到确认新配置能用
2. **建议配合云控制台（如腾讯云 Console）一起操作**
3. 如果 SSH 配置错误导致无法连接，可通过云控制台修复

### 7. Nginx 恶意扫描检测与拦截

有两层防护策略：

**第一层（推荐）：Nginx 配置层 — 直接拒绝敏感路径**
在 Nginx server block 中直接 deny 敏感路径，连请求都不会落到后端：

```nginx
location ~ /\.env {
    deny all;
    access_log off;
    log_not_found off;
    return 444;  # 不返回任何内容，让扫描器困惑
}

location ~ /\.git {
    deny all;
    access_log off;
    log_not_found off;
    return 444;
}

location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
    return 444;
}

# 如果 Nginx 有多个 server block，每个都要加
# 检查所有启用的站点配置：
# grep -r "server_name" /etc/nginx/sites-enabled/
# 然后在每个 server block 中添加上述 location 块
```

验证配置后 reload：
```bash
nginx -t && systemctl reload nginx
```

**第二层：fail2ban 层 — 检测并封禁扫描者**（备用/补充）

Nginx 网站服务器经常会遭受自动化工具扫描 `.env`、`.git/config`、`wp-content/debug.log` 等敏感路径。本技能包含自动检测和封禁机制。

#### 7.1 创建自定义扫描检测过滤器

```bash
sudo cat > /etc/fail2ban/filter.d/nginx-secscan.conf << 'EOF'
# 自定义过滤器：检测安全扫描尝试
# 匹配访问 .env、.git、wp-content、config、admin 等敏感路径的请求

[Definition]
failregex = ^<HOST> \- \- \[.*\] "(GET|POST|HEAD) \/((\.env|\.git|wp-content|config|backend|public|laravel|admin|v1\/public|v1\/admin))

ignoreregex =
EOF
```

**关键点：** 日志格式是 `IP - - [时间] "请求"`（有两个 dash），正则必须匹配 `<HOST> - -` 而非 `<HOST> -`。

#### 7.2 验证正则是否匹配

```bash
# 测试过滤器是否能匹配现有日志
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-secscan.conf
```

如果匹配数为 0，说明正则有问题。常见错误：
- 日志格式与正则不匹配（检查 `- -` 的数量）
- 日期格式与 datepattern 不匹配

#### 7.3 添加到 jail.local

```bash
sudo cat >> /etc/fail2ban/jail.local << 'EOF'

[nginx-secscan]
enabled = true
port = http,https
backend = polling
filter = nginx-secscan
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 604800
findtime = 600
EOF

sudo fail2ban-client reload
```

#### 7.4 常用 Nginx 扫描检测规则

| 扫描类型 | 过滤关键词 |
|----------|-----------|
| 敏感文件 | `.env`、`.git`、`config/` |
| 管理后台 | `admin`、`wp-login`、`phpmyadmin` |
| 备份文件 | `.sql`、`.bak`、`.zip`、`.tar` |
| 日志文件 | `.log`、`.ini`、`.conf` |

#### 7.5 快速封禁可疑IP（手动）

```bash
# 方法1：通过 fail2ban 封禁
sudo fail2ban-client set sshd banip <IP>

# 方法2：直接通过 iptables 封禁（立即生效）
sudo iptables -I INPUT -s <IP> -j DROP

# 保存规则防止重启丢失
sudo iptables-save > /etc/iptables/rules.v4
```

#### 7.6 分析 Nginx 日志找出可疑IP

```bash
# 按请求数排序的IP（排除正常爬虫）
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# 查找扫描敏感路径的IP
grep -E "(\.env|\.git\/config|wp-content)" /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -rn

# 查找扫描者 User-Agent
grep -E "(\.env|\.git)" /var/log/nginx/access.log | grep -oP '"[^"]+"$' | sort | uniq -c | sort -rn
```

#### 7.7 已封禁IP查询

```bash
# fail2ban 已封禁列表
sudo fail2ban-client banned

# iptables 已封禁IP
sudo iptables -L INPUT -n | grep DROP
```

---

## 回滚命令

```bash
# 恢复 SSH 默认配置
sudo sed -i 's/^Port.*$/Port 22/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 关闭 UFW
sudo ufw disable
```

### 8. Default Server 444 — 阻止幽灵域名

未配置 server_name 的域名（"幽灵域名"）可能因 DNS 记录过期、IP 重用或恶意指向而打到服务器的默认站点。配置 default_server 返回 444（直接断连），让扫描器连 HTTP 头都拿不到：

```nginx
# /etc/nginx/sites-enabled/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    server_name _;

    # 自签名证书（SSL 握手必须）
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    # 禁止访问敏感文件
    location ~ /\.(git|env|md) {
        deny all;
    }

    # 未绑定域名直接断开连接
    location / {
        return 444;
    }
}
```

验证：
```bash
nginx -t && systemctl reload nginx
# 模拟未绑定域名 → 应返回空响应
curl -s -o /dev/null -w "%{http_code}" -H "Host: 随便一个域名" http://127.0.0.1/
# 返回 000 或 Empty reply → 444 生效
```

**如何发现幽灵域名：** 巡检时检查 nginx access.log 中非本站域名的请求，用 `dig +short 域名 @8.8.8.8` 确认是否解析到本服务器。

## 适用系统

- ✅ Ubuntu 20.04+ / Ubuntu 22.04+
- ✅ Debian 11+
