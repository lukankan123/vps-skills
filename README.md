# VPS Skills

🤖 Robot × Human — Open-source Skills collection

## About

An open-source Skills library co-developed by **Robot** 🤖 and **lukankan123** 👤, built from real production experience. Every skill here has been battle-tested on live servers.

## Philosophy

- 🚀 **Simple** — built for everyday users, low learning curve
- 🔒 **Secure** — every skill is security-hardened by design
- 💡 **Practical** — solves real problems, focused on efficiency
- 🌱 **Evolving** — continuously improved, feedback welcome

## Skills

### 🔐 Security

#### vps-security — VPS Security Hardening (v2.2)

One-shot security hardening for Ubuntu/Debian VPS:

- 🔐 SSH hardening (custom port **or** `--random-port` high port, key-only auth, retry limits)
- 🛡️ Modern SSH crypto (X25519, Chacha20-Poly1305 / AES-GCM, modern MACs)
- 🔥 UFW firewall (deny incoming by default, optional `--strict` egress whitelist)
- 🚫 fail2ban with **9 jails** (SSH brute-force + 6 Nginx scan detectors + rate-limit cooldown)
- 🌐 Nginx hardening (hide version, 19 malicious UA blacklist, sensitive-path deny, rate limiting, ghost-domain 444)
- 🧠 Kernel hardening (disables `unprivileged_userns_clone` — blocks DirtyFrag / Bad Epoll LPE)
- 🔍 Daily security scan (login audit / Nginx scans / resources / SSL expiry)

**Docs:** [English](skills/vps-security/SKILL.en.md) · [中文](skills/vps-security/SKILL.md) · [Changelog](CHANGELOG.md)

**Quick start:**
```bash
# 1) Download (do NOT pipe straight into a shell -- save it to a file first)
curl -fsSLO https://vodka1.eu.cc/skills/vps-security.sh

# 2) Verify integrity: the checksum comes from the GitHub repo
#    (independent of the download host -- a checksum served next to the script proves nothing)
curl -fsSL https://raw.githubusercontent.com/lukankan123/vps-skills/main/SHA256SUMS -o SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing

# 3) Read what it is going to change (strongly recommended before touching SSH)
less vps-security.sh

# 4) Run it once you are satisfied
sudo bash vps-security.sh --email you@example.com        # default: random high SSH port
# sudo bash vps-security.sh --port 13521 --email you@example.com   # fixed port
```

> If verification fails right after a release: the GitHub raw CDN may still be serving the previous copy. Retry in a few minutes (the GitHub API serves the same file without that cache).

**Supported systems:** Ubuntu 20.04+ / Debian 11+

## Directory Structure

```
skills/
├── vps-security/                 # VPS security hardening
│   ├── SKILL.md                  # 中文文档
│   ├── SKILL.en.md               # English docs
│   └── scripts/
│       └── vps-secure.sh         # v2.2 hardening script (624 lines)
└── README.md
```

## License

MIT — free to use, modify, and distribute.
