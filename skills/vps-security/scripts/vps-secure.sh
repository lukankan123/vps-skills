#!/bin/bash
#================================================================
# VPS 安全加固脚本 v2.0
# 适用系统：Ubuntu 20.04+ / Debian 11+（支持 Debian 12）
# 用法：
#   curl -fsSL https://vodka1.eu.cc/skills/vps-security.sh | sudo bash -s -- --port 13521 --email you@example.com
#
# 可选参数：
#   --port <端口>          SSH 端口（默认 13521）
#   --email <邮箱>         fail2ban/巡检告警邮箱（可选但推荐）
#   --strict               启用 UFW 出站白名单（仅允许 DNS/HTTP/HTTPS/NTP/SMTP）
#   --skip-nginx           跳过 Nginx 加固（服务器上没装 Nginx 时自动跳过）
#   --skip-kernel          跳过内核加固（sysctl 参数）
#   --no-upgrade           跳过 apt 系统升级
#
# v2.0 新增：
#   - fail2ban 9 个 jail（sshd + nginx 扫描检测 6 类 + botsearch + 限流联动）
#   - Nginx 加固：隐藏版本号 / 敏感路径 deny / 恶意 UA 拦截 / 幽灵域名 444
#   - Nginx 限流：全局 10r/s + 敏感路径 3r/m + 429 联动封禁
#   - 内核加固：关闭 unprivileged userns（防 DirtyFrag / Bad Epoll 提权）
#   - 巡检脚本升级：登录审计 + Nginx 扫描检测 + 磁盘/负载/证书检查
#   - 全程备份 + 配置语法检查，避免把自己锁在门外
#================================================================

set -e

# 默认参数
SSH_PORT="${SSH_PORT:-13521}"
EMAIL="${EMAIL:-}"
STRICT_MODE=0
SKIP_NGINX=0
SKIP_KERNEL=0
DO_UPGRADE=1

# 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --port) SSH_PORT="$2"; shift 2 ;;
        --email) EMAIL="$2"; shift 2 ;;
        --strict) STRICT_MODE=1; shift ;;
        --skip-nginx) SKIP_NGINX=1; shift ;;
        --skip-kernel) SKIP_KERNEL=1; shift ;;
        --no-upgrade) DO_UPGRADE=0; shift ;;
        *) error "未知参数: $1（可用 --port/--email/--strict/--skip-nginx/--skip-kernel/--no-upgrade）" ;;
    esac
done

# 检查 root
[[ $EUID -ne 0 ]] && error "请使用 sudo 或以 root 用户运行此脚本"

# 系统检测
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian) log "系统: $PRETTY_NAME" ;;
            *) error "仅支持 Ubuntu/Debian，当前: $ID" ;;
        esac
    else
        error "无法识别系统版本"
    fi
}

# 备份文件
backup() {
    local f="$1"
    [[ -f "$f" ]] && cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" && warn "已备份 $f"
}

# 检查当前 SSH 连接是否安全（防止改端口后把自己锁外面）
check_ssh_session() {
    if [[ -n "$SSH_CONNECTION" ]]; then
        log "检测到当前通过 SSH 连接（$SSH_CONNECTION），改端口前先放行新端口"
    else
        warn "未检测到 SSH 连接环境变量。如果你是通过 SSH 操作，请务必保持当前会话不要关闭！"
    fi
}

# ============================================================
log "开始 VPS 安全加固 v2.0 ..."
detect_os
log "SSH 端口: $SSH_PORT | 严格模式: $([ $STRICT_MODE -eq 1 ] && echo ON || echo OFF)"

# 1. 更新系统
if [[ $DO_UPGRADE -eq 1 ]]; then
    log "更新系统包..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get upgrade -y
fi

# 2. 安装必要工具
log "安装必要工具..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y ufw fail2ban curl mailutils iptables-persistent > /dev/null 2>&1 || \
apt-get install -y ufw fail2ban curl mailutils

# 3. 配置 SSH
log "配置 SSH 安全设置..."
check_ssh_session

SSHD_CONF=/etc/ssh/sshd_config
backup "$SSHD_CONF"

# 端口修改（兼容已有 Port 行/无 Port 行的情况）
if grep -qE "^#?Port " "$SSHD_CONF"; then
    sed -i "s/^#\?Port .*/Port $SSH_PORT/" "$SSHD_CONF"
else
    echo "Port $SSH_PORT" >> "$SSHD_CONF"
fi

# 关键安全项（先追加再覆盖，保证生效）
for opt in "PermitRootLogin prohibit-password" "PasswordAuthentication no" "PermitEmptyPasswords no" "PubkeyAuthentication yes" "MaxAuthTries 4" "LoginGraceTime 30" "X11Forwarding no"; do
    key="${opt%% *}"; val="${opt#* }"
    if grep -qE "^#?$key " "$SSHD_CONF"; then
        sed -i "s|^#\?$key .*|$key $val|" "$SSHD_CONF"
    else
        echo "$key $val" >> "$SSHD_CONF"
    fi
done

# 语法检查，防止改坏 sshd
if ! sshd -t 2>/dev/null; then
    warn "sshd 配置语法错误，恢复备份！"
    cp "$SSHD_CONF.bak."* "$SSHD_CONF" 2>/dev/null || true
    error "SSH 配置回滚完成，请检查后重试"
fi
systemctl restart sshd
log "SSH 硬化完成（端口 $SSH_PORT，密钥登录，禁用密码）"

# 4. 配置 UFW 防火墙
log "配置 UFW 防火墙..."
if command -v ufw > /dev/null; then
    ufw --force reset > /dev/null 2>&1 || true
    ufw default deny incoming
    if [[ $STRICT_MODE -eq 1 ]]; then
        # 严格模式：出站白名单
        ufw default deny outgoing
        for p in 53 80 443 123 25 587; do
            ufw allow out $p/tcp  > /dev/null 2>&1 || true
            ufw allow out $p/udp  > /dev/null 2>&1 || true
        done
        # 53/123 需要 tcp+udp；80/443 主要 tcp，443/udp 给 QUIC
        ufw allow out 53/udp > /dev/null 2>&1 || true
        ufw allow out 123/udp > /dev/null 2>&1 || true
        log "出站白名单模式已启用（DNS/HTTP/HTTPS/NTP/SMTP）"
    else
        ufw default allow outgoing
    fi
    ufw allow "$SSH_PORT"/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp > /dev/null 2>&1 || true   # QUIC/HTTP3
    # 防把自己锁死：先确保 SSH 放行后再 enable
    ufw allow "$SSH_PORT"/tcp > /dev/null 2>&1
    echo "y" | ufw enable
    ufw status verbose | head -20
    log "UFW 防火墙配置完成"
fi

# 5. 配置 fail2ban（9 个 jail）
log "配置 fail2ban 防暴力破解 + Nginx 扫描检测..."

# 5.1 通用 nginx 扫描过滤器（综合 22 种模式）
cat > /etc/fail2ban/filter.d/nginx-secscan.conf << 'EOF'
# 综合安全扫描检测：.env/.git/wp/phpmyadmin/actuator/swagger/api 等
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD|PUT|DELETE) \/((\.env|\.git|\.aws|\.config|\.svn|\.hg|wp-content|wp-includes|wp-login|wp-admin|phpmyadmin|pma|mysql|admin|administrator|backend|public|laravel|actuator|swagger|api-docs|openapi\.json|\.bak|\.sql|\.tar|\.zip|\.log|\.ini|\.conf|debug\.log|composer\.json|package\.json|server-status|\.htaccess|\.htpasswd|robots\.txt\?|xmlrpc\.php|\.DS_Store|\.well-known\/acme-challenge\/[^/]+)\/?.*)
ignoreregex =
EOF

# 5.2 .env / .git 专用（永久封禁）
cat > /etc/fail2ban/filter.d/nginx-envscan.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) \/((\.env|\.git|\.aws|\.config|\.svn)(\/|\?|$).*)
ignoreregex =
EOF

# 5.3 WordPress 扫描
cat > /etc/fail2ban/filter.d/nginx-wpscan.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) \/(wp-content|wp-includes|wp-login|wp-admin|xmlrpc\.php)(\/|\?|$).*)
ignoreregex =
EOF

# 5.4 PHP 漏洞扫描
cat > /etc/fail2ban/filter.d/nginx-phpscan.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) \/((phpmyadmin|pma|mysql|adminer|\.php\?|\.php$|index\.php\?.*(cmd|exec|eval|system|passthru))\/?.*)
ignoreregex =
EOF

# 5.5 机器人/爬虫扫描
cat > /etc/fail2ban/filter.d/nginx-botsearch.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) \/(search|index\.php\?s=|\.html\?s=|\?s=).*
ignoreregex =
EOF

# 5.6 恶意/异常请求
cat > /etc/fail2ban/filter.d/nginx-bad-request.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD|PUT|DELETE|OPTIONS) \/(\.\.|%00|%0d|%0a|\\x00|union.*select|select.*from|insert.*into|eval\(|base64_decode|wget |curl ).*
ignoreregex =
EOF

# 5.7 HTTP 认证暴力破解
cat > /etc/fail2ban/filter.d/nginx-http-auth.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD).*" 401 .*
ignoreregex =
EOF

# 5.8 限流联动过滤器（429 → 封禁）
cat > /etc/fail2ban/filter.d/nginx-ratelimit.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD).*" 429 .*
ignoreregex =
EOF

# jail.local：9 个 jail + 关键配置
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 604800
findtime = 600
maxretry = 4
destemail = ${EMAIL:-root@localhost}
sender = fail2ban@localhost
action = %(action_mwl)s
backend = polling
dbpurgeage = 0

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 4
bantime = 604800

[sshd-ddos]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 10
bantime = 604800
findtime = 60

[nginx-envscan]
enabled = true
port = http,https
filter = nginx-envscan
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = -1
findtime = 600

[nginx-secscan]
enabled = true
port = http,https
filter = nginx-secscan
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 604800
findtime = 600

[nginx-wpscan]
enabled = true
port = http,https
filter = nginx-wpscan
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 604800
findtime = 600

[nginx-phpscan]
enabled = true
port = http,https
filter = nginx-phpscan
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 604800
findtime = 600

[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 604800
findtime = 600

[nginx-bad-request]
enabled = true
port = http,https
filter = nginx-bad-request
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 604800
findtime = 600

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 604800
findtime = 600

[nginx-ratelimit]
enabled = true
port = http,https
filter = nginx-ratelimit
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 3600
findtime = 300
EOF

# 只有装了 nginx 才启 nginx jail，否则会因 logpath 不存在报错
if [[ -d /var/log/nginx ]]; then
    systemctl enable fail2ban > /dev/null 2>&1 || true
    systemctl restart fail2ban
    log "fail2ban 已启用（9 个 jail）"
else
    # 禁用 nginx 相关 jail（没装 nginx 时）
    sed -i 's/^enabled = true/enabled = false/' /etc/fail2ban/jail.local
    sed -i '0,/enabled = false/s//enabled = true/' /etc/fail2ban/jail.local
    systemctl enable fail2ban > /dev/null 2>&1 || true
    systemctl restart fail2ban
    warn "未检测到 Nginx，nginx 相关 jail 已禁用（仅启用 sshd）"
fi

# 6. Nginx 加固
if [[ $SKIP_NGINX -eq 0 ]] && command -v nginx > /dev/null 2>&1; then
    log "配置 Nginx 加固..."

    # 6.1 隐藏版本号
    if ! grep -q "server_tokens" /etc/nginx/nginx.conf; then
        backup /etc/nginx/nginx.conf
        sed -i '/^http {/a\    server_tokens off;' /etc/nginx/nginx.conf
        log "server_tokens off 已启用"
    fi

    # 6.2 恶意 UA 黑名单 + 限流区（map/limit_req_zone 必须放 http 块）
    cat > /etc/nginx/conf.d/security-map.conf << 'EOF'
# 恶意扫描器 UA 黑名单（匹配即断连）
map $http_user_agent $bad_bot {
    default 0;
    ~*pathscan 1;
    ~*zgrab 1;
    ~*nmap 1;
    ~*masscan 1;
    ~*sqlmap 1;
    ~*nikto 1;
    ~*gobuster 1;
    ~*dirbuster 1;
    ~*wpscan 1;
    ~*nessus 1;
    ~*acunetix 1;
    ~*whatweb 1;
    ~*hydra 1;
    ~*medusa 1;
    ~*jorgee 1;
    ~*nessus 1;
    ~*fimap 1;
    ~*"ZmEu" 1;
}

# 限流区
limit_req_zone $binary_remote_addr zone=global_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=sensitive_limit:10m rate=3r/m;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_conn_zone $binary_remote_addr zone=addr_limit:10m;
EOF

    # 6.3 server 级加固片段（敏感路径 + UA 拦截 + 限流）
    cat > /etc/nginx/snippets/security-hardening.conf << 'EOF'
# 恶意 UA 直接断连
if ($bad_bot) { return 444; }

# 敏感路径拒绝访问
location ~ /\.(git|env|md|aws|svn|hg|htaccess|htpasswd|DS_Store) {
    deny all;
    access_log off;
    log_not_found off;
    return 444;
}

# 备份/配置文件
location ~ \.(sql|bak|tar|gz|zip|log|ini|conf|old|swp)$ {
    deny all;
    access_log off;
    log_not_found off;
}

# 全局限流：10 请求/秒
limit_req zone=global_limit burst=20 nodelay;

# 单 IP 并发上限
limit_conn addr_limit 10;
EOF

    # 6.4 把加固片段 include 进所有已启用的 server 块
    INCLUDED=0
    for f in /etc/nginx/sites-enabled/*; do
        [[ -f "$f" ]] || continue
        if ! grep -q "security-hardening.conf" "$f"; then
            backup "$f"
            # 在每个 server { 后插入 include
            awk -v inc='    include /etc/nginx/snippets/security-hardening.conf;' '
                /^[[:space:]]*server[[:space:]]*\{/ && !done { print; print inc; done=1; next }
                { print }
            ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
            INCLUDED=1
        fi
    done

    # 语法检查 + reload
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log "Nginx 加固完成（版本隐藏 + UA 黑名单 + 敏感路径 + 限流）"
        [[ $INCLUDED -eq 1 ]] && log "已为 $INCLUDED 个站点配置加固"
    else
        warn "Nginx 配置语法有问题，跳过 reload（请手动检查 /etc/nginx/）"
    fi

    # 6.5 幽灵域名处理（default_server 444）
    if [[ ! -f /etc/nginx/sites-enabled/default ]] && [[ -d /etc/nginx/sites-enabled ]]; then
        cat > /etc/nginx/sites-available/zz-default-444 << 'EOF'
# 幽灵域名：未绑定的域名直接断开连接
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    location ~ /\.(git|env|md) { deny all; }
    location / { return 444; }
}
EOF
        ln -sf /etc/nginx/sites-available/zz-default-444 /etc/nginx/sites-enabled/zz-default-444
        nginx -t 2>/dev/null && systemctl reload nginx && log "幽灵域名 444 已启用" || warn "default_server 配置跳过（已有默认站点）"
    fi
else
    [[ $SKIP_NGINX -eq 0 ]] && log "跳过 Nginx 加固（未安装或已指定 --skip-nginx）"
fi

# 7. 内核加固
if [[ $SKIP_KERNEL -eq 0 ]]; then
    log "配置内核加固..."
    SYSCTL_FILE=/etc/sysctl.d/99-security.conf
    if ! grep -q "unprivileged_userns_clone" "$SYSCTL_FILE" 2>/dev/null; then
        backup "$SYSCTL_FILE"
        echo "kernel.unprivileged_userns_clone=0" >> "$SYSCTL_FILE"
        sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1 || sysctl -w kernel.unprivileged_userns_clone=0
        log "已关闭非特权 userns（防 DirtyFrag / Bad Epoll 提权）"
    else
        log "内核加固已存在，跳过"
    fi
fi

# 8. 每日安全巡检脚本（升级版）
log "创建每日安全巡检脚本..."

cat > /usr/local/bin/security-scan.sh << 'SCAN_SCRIPT'
#!/bin/bash
# VPS 每日安全巡检 v2.0
LOG_FILE="/var/log/security-scan.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "========== 开始每日安全巡检 =========="

# 1. 登录失败检测
FAILED_IPS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | \
    grep "$(date '+%b %d')" | awk '{print $NF}' | sort | uniq -c | \
    awk '$1 >= 3 {print $2}')

if [ -n "$FAILED_IPS" ]; then
    log "检测到异常登录失败IP:"
    for IP in $FAILED_IPS; do
        log "  - $IP"
        fail2ban-client set sshd banip "$IP" 2>/dev/null && log "  -> 已封禁"
    done
else
    log "登录失败检测: 无异常"
fi

# 2. Nginx 扫描检测（今日敏感路径请求）
if [ -f /var/log/nginx/access.log ]; then
    SCAN_IPS=$(grep "$(date '+%d/%b/%Y')" /var/log/nginx/access.log | \
        grep -E "(\.env|\.git|wp-login|phpmyadmin|actuator|swagger|union select)" | \
        awk '{print $1}' | sort | uniq -c | sort -rn | head -10)
    if [ -n "$SCAN_IPS" ]; then
        log "今日 Nginx 扫描请求 TOP:"
        echo "$SCAN_IPS" | while read cnt ip; do
            log "  $ip (${cnt}次)"
        done
    else
        log "Nginx 扫描检测: 无"
    fi
fi

# 3. fail2ban 封禁统计
for jail in sshd nginx-envscan nginx-secscan nginx-wpscan nginx-phpscan nginx-ratelimit; do
    BANNED=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP" | cut -d: -f2 | tr -d ' ')
    [ -n "$BANNED" ] && log "$jail 封禁: $(echo $BANNED | wc -w) 个IP"
done

# 4. 系统资源
LOAD=$(uptime | awk -F'load average:' '{print $2}')
DISK=$(df -h / | awk 'NR==2{print $5}')
MEM=$(free -m | awk 'NR==2{printf "%d/%dMB (%.0f%%)", $3, $2, $3/$2*100}')
log "负载:$LOAD | 磁盘:$DISK | 内存:$MEM"

# 5. UFW 状态
UFW=$(ufw status 2>/dev/null | head -1)
log "UFW: $UFW"

# 6. SSL 证书到期检查
if command -v certbot > /dev/null 2>&1 && [ -d /etc/letsencrypt/live ]; then
    for d in /etc/letsencrypt/live/*/; do
        DAYS=$(openssl x509 -enddate -noout -in "$d/fullchain.pem" 2>/dev/null | \
            cut -d= -f2 | date -f - +%s 2>/dev/null | \
            awk -v now=$(date +%s) '{printf "%.0f", ($1-now)/86400}')
        log "证书 $(basename $d): 剩余 ${DAYS} 天"
    done
fi

log "========== 巡检完成 =========="
SCAN_SCRIPT

chmod +x /usr/local/bin/security-scan.sh

# 添加到 crontab（每天凌晨 2 点）
(crontab -l 2>/dev/null | grep -v "security-scan.sh"; echo "0 2 * * * /usr/local/bin/security-scan.sh") | crontab -
log "每日安全巡检已添加（每天 2:00 执行）"

# ============================================================
log "========== 安全加固 v2.0 完成！ =========="
log "SSH 端口: $SSH_PORT（密钥登录，密码已禁用）"
log "UFW: 已启用（默认拒绝入站）"
log "fail2ban: $(fail2ban-client status 2>/dev/null | grep 'Jail list' || echo 'sshd + nginx jails')"
log "Nginx: $(command -v nginx > /dev/null 2>&1 && echo '已加固' || echo '未安装/跳过')"
log "内核: unprivileged_userns_clone=$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo 'N/A')"
log ""
log "⚠️  重要提醒："
log "  1. 请保持当前 SSH 会话不要关闭，用新端口重新连接验证后再退出！"
log "  2. 如果连不上：云控制台 VNC 登录后恢复 /etc/ssh/sshd_config.bak.*"
log "  3. 巡检日志: /var/log/security-scan.log"
log "  4. 建议将本机公钥加入 ~/.ssh/authorized_keys（若还没配）"
