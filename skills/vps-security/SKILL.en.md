---
name: vps-security
description: VPS security hardening skill v2.1. One-click SSH hardening (custom or random high port), modern X25519/GCM cipher suites, UFW firewall, fail2ban with 9 jails (incl. Nginx scan detection), Nginx hardening, kernel hardening and daily security scans for Ubuntu/Debian. Use when the user needs to secure a VPS, configure SSH protection, install a firewall, block brute-force attacks, or stop Nginx web scanners.
---

# VPS Security Hardening (v2.1)

One-shot security hardening for your VPS. v2.1 adds a random high SSH port option and modern SSH cipher hardening. v2.0 packaged battle-tested strategies from production into a generic script with automatic backups and syntax checks — you won't lock yourself out.

## Features

- 🔐 **SSH Hardening** — custom port (13521) OR `--random-port` (40000-60000, collision-checked, recorded to `/root/ssh_port.txt`), disable password login, force key auth, limit retries
- 🛡️ **Modern SSH crypto** — X25519 key exchange, Chacha20-Poly1305 / AES-GCM ciphers, modern MACs; keeps session alive (ClientAliveInterval/TCPKeepAlive)
- 🔥 **UFW Firewall** — deny incoming by default, optional `--strict` egress whitelist mode
- 🚫 **fail2ban with 9 jails** — SSH brute-force + 6 Nginx scan detectors + bot search + rate-limit cooldown
- 🌐 **Nginx Hardening** — hide version, block 19 malicious UAs, deny sensitive paths, rate limiting, ghost-domain 444
- 🧠 **Kernel Hardening** — disable `unprivileged_userns_clone` (blocks DirtyFrag / Bad Epoll LPE chains)
- 📋 **Log Auditing** — login records, failed attempts, ban records
- 🔍 **Daily Security Scan v2.0** — login audit / Nginx scans / resources / UFW / SSL expiry

## Quick Start

```bash
# One-shot install (default SSH port 13521)
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --port 13521 --email your@email.com

# Or let the script pick a random high SSH port (recommended)
curl -fsSL https://your-server/vps-secure.sh | sudo bash -s -- --random-port --email your@email.com
```

Or download and run:

```bash
sudo bash scripts/vps-secure.sh --port 13521 --email your@email.com
```

Full script: `scripts/vps-secure.sh` (v2.1, 614 lines).

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--port` | SSH port (manual) | 13521 |
| `--random-port` | Generate a random high SSH port (40000-60000, collision-checked, saved to `/root/ssh_port.txt`) | off |
| `--email` | Alert email (fail2ban / scan report) | root@localhost |
| `--strict` | UFW egress whitelist (DNS/HTTP/HTTPS/NTP/SMTP only) | off |
| `--skip-nginx` | Skip Nginx hardening | off |
| `--skip-kernel` | Skip kernel hardening | off |
| `--no-upgrade` | Skip apt system upgrade | off |

Examples:

```bash
# Strict egress whitelist + custom port
sudo bash scripts/vps-secure.sh --port 22022 --email you@email.com --strict

# Random high port (recommended) — records the picked port to /root/ssh_port.txt
sudo bash scripts/vps-secure.sh --random-port

# App-only server (no Nginx)
sudo bash scripts/vps-secure.sh --skip-nginx
```

## Core Steps

### 1. System Update & Tools

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y ufw fail2ban curl mailutils iptables-persistent
```

### 2. SSH Hardening

```bash
# Change port (works whether or not a Port line already exists)
sed -i "s/^#\?Port .*/Port 13521/" /etc/ssh/sshd_config || echo "Port 13521" >> /etc/ssh/sshd_config

# Security directives: key auth, no passwords, limited retries
for opt in "PermitRootLogin prohibit-password" "PasswordAuthentication no" \
           "PermitEmptyPasswords no" "PubkeyAuthentication yes" \
           "MaxAuthTries 4" "LoginGraceTime 30" "X11Forwarding no"; do
    key="${opt%% *}"; val="${opt#* }"
    sed -i "s|^#\?$key .*|$key $val|" /etc/ssh/sshd_config || echo "$key $val" >> /etc/ssh/sshd_config
done

# Modern SSH crypto (v2.1): strip legacy/weak algorithms, keep only strong ones
for opt in \
    "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256" \
    "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr" \
    "MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512" \
    "ClientAliveInterval 300" "ClientAliveCountMax 3" "TCPKeepAlive yes"; do
    key="${opt%% *}"; val="${opt#* }"
    sed -i "s|^#\?$key .*|$key $val|" /etc/ssh/sshd_config || echo "$key $val" >> /etc/ssh/sshd_config
done

# ⚠️ Only restart after syntax check passes; auto-rollback on failure
sshd -t && systemctl restart sshd
```

### 3. UFW Firewall

```bash
ufw default deny incoming
ufw default allow outgoing          # or --strict whitelist mode
ufw allow 13521/tcp                 # allow the NEW SSH port FIRST!
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp                   # QUIC/HTTP3
echo "y" | ufw enable
```

**`--strict` egress whitelist:** deny outgoing by default, allow only `53/80/123/443/25/587` (DNS/HTTP/HTTPS/NTP/SMTP).

### 4. fail2ban (9 jails)

Key settings: `backend = polling` (nginx logs aren't in journald), `dbpurgeage = 0` (ban records survive restarts).

| Jail | Monitors | Ban policy |
|------|----------|------------|
| `sshd` / `sshd-ddos` | SSH brute-force | 4 failures → ban 7 days |
| `nginx-envscan` | `.env`/`.git`/`.aws` probing | **permanent** (bantime=-1) |
| `nginx-secscan` | generic security scans (22 patterns) | 7 days |
| `nginx-wpscan` | WordPress vulnerability scans | **ban on 1st hit** (IPv6 single-scan) |
| `nginx-phpscan` | PHP vulnerability scans | 7 days |
| `nginx-botsearch` | bot search traffic | 7 days |
| `nginx-bad-request` | malicious requests (SQLi/path traversal) | 7 days |
| `nginx-http-auth` | HTTP auth brute-force | 7 days |
| `nginx-ratelimit` | 429 rate-limit cooldown | 5 hits/5 min → ban 1h |

The script writes 8 filter files (`/etc/fail2ban/filter.d/`) plus `jail.local`. If Nginx isn't installed, only the sshd jails are enabled to avoid missing-logpath errors.

### 5. Nginx Hardening

**Hide version:**
```nginx
# nginx.conf, http block
server_tokens off;
```

**Malicious UA blacklist (map directive, http block):**
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

**Server-level snippet (include in every server block):**
```nginx
if ($bad_bot) { return 444; }   # drop malicious UAs immediately

# Deny sensitive paths
location ~ /\.(git|env|md|aws|svn|hg|htaccess|htpasswd|DS_Store) {
    deny all; access_log off; log_not_found off; return 444;
}
location ~ \.(sql|bak|tar|gz|zip|log|ini|conf|old|swp)$ {
    deny all; access_log off; log_not_found off;
}

# Rate limiting: 10 req/s global + 10 concurrent connections per IP
limit_req zone=global_limit burst=20 nodelay;
limit_conn addr_limit 10;
```

**Rate-limit zones (http block):**
```nginx
limit_req_zone $binary_remote_addr zone=global_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=sensitive_limit:10m rate=3r/m;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_conn_zone $binary_remote_addr zone=addr_limit:10m;
```

**Ghost-domain 444 (default_server):**
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

### 6. Kernel Hardening

```bash
echo "kernel.unprivileged_userns_clone=0" >> /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf
# Verify
cat /proc/sys/kernel/unprivileged_userns_clone   # should be 0
```

Blocks non-privileged users from creating namespaces, cutting off DirtyFrag / Bad Epoll local privilege-escalation paths. Docker runs as root and is unaffected.

### 7. Daily Security Scan v2.0

Installed at `/usr/local/bin/security-scan.sh`, cron at 02:00 daily. Checks:

1. **Failed logins** — auto-ban IPs with ≥3 failures today
2. **Nginx scan detection** — top IPs hitting `.env`/`.git`/`wp-login`/`phpmyadmin`/`actuator` today
3. **fail2ban stats** — current bans per jail
4. **System resources** — load / disk / memory
5. **UFW status**
6. **SSL expiry** — days remaining (when certbot is present)

Log: `/var/log/security-scan.log`

### 8. Manual Log Auditing

```bash
last -20                                    # recent logins
grep "Failed password" /var/log/auth.log | tail -20   # failed attempts
fail2ban-client banned                      # all banned IPs
grep -E "(\.env|\.git)" /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -rn   # scanners
```

## ⚠️ Read Before Running

1. **Keep your current SSH session open** until you can reconnect on the new port
2. Use your cloud provider's VNC console as a safety net
3. The script backs everything up (`*.bak.timestamp`); SSH mistakes auto-rollback
4. Make sure you already have SSH public-key login configured

## Verification

```bash
grep "^Port" /etc/ssh/sshd_config          # SSH port
ufw status verbose                          # firewall
fail2ban-client status                      # 9 jails
curl -o /dev/null -w "%{http_code}" http://127.0.0.1/.env   # sensitive path → 403/444
cat /proc/sys/kernel/unprivileged_userns_clone               # kernel → 0
bash /usr/local/bin/security-scan.sh        # manual scan
```

## Rollback

```bash
# Restore SSH defaults
sed -i 's/^Port.*$/Port 22/' /etc/ssh/sshd_config && systemctl restart sshd

# Disable firewall
ufw disable
systemctl stop fail2ban

# Restore kernel setting
sysctl -w kernel.unprivileged_userns_clone=1
```

## Supported Systems

- ✅ Ubuntu 20.04+ / 22.04+ / 24.04+
- ✅ Debian 11+ / 12+
