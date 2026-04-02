---
name: vps-security
description: VPS 基础安全防护技能。为不懂安全的普通用户自动配置 SSH 端口修改、密钥登录、防火墙（UFW 或 iptables）和 fail2ban 防暴力破解。适用于 Ubuntu/Debian 系统。当用户需要：保护 VPS 安全、配置 SSH 防护、安装防火墙、防暴力破解时使用。
---

# VPS 基础安全防护

本技能为 VPS 提供基础安全防护，适用于 Ubuntu/Debian 系统。

## 功能特性

- 🔐 修改 SSH 默认端口（默认 13521）
- 🔑 自动配置 SSH 公钥认证
- 🔥 智能防火墙（自动检测 UFW/iptables）
- 🚫 fail2ban 防暴力破解（封禁时间可配置，默认7天）
- 📋 日志审计（登录记录、失败尝试、封禁记录）
- 🔍 每日安全巡检（自动封禁异常IP）

## 执行脚本

完整脚本见：`scripts/vps-secure.sh`

### 使用方法

```bash
# 下载并执行
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --port 13521 --email your@email.com

# 或直接在服务器执行脚本内容
```

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

## 回滚命令

```bash
# 恢复 SSH 默认配置
sudo sed -i 's/^Port.*$/Port 22/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 关闭 UFW
sudo ufw disable
```

## 适用系统

- ✅ Ubuntu 20.04+ / Ubuntu 22.04+
- ✅ Debian 11+
