# Changelog

All notable changes to this skills collection are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) loosely.
Versions are tied to the skill, not the repo.

---

## vps-security

### v2.1 — 2026-09-06

#### Added
- **`--random-port` option** — generate a random high SSH port (40000–60000) on deployment.
  - Skips well-known ports (22/53/80/443/3000/5432/6379/8000/8080/8443/8888).
  - Collision-checked against ports already in use (`ss -tln`).
  - Writes the chosen port to `/root/ssh_port.txt` (mode 600) so you never lock yourself out.
- **Modern SSH crypto hardening** — replace legacy/weak algorithms with current ones:
  - KEX: `curve25519-sha256`, `curve25519-sha256@libssh.org`, `ecdh-sha2-nistp*`, `diffie-hellman-group-exchange-sha256`.
  - Ciphers: `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`, `aes128-gcm@openssh.com`, `aes256-ctr`, `aes128-ctr`.
  - MACs: `hmac-sha2-256-etm@openssh.com`, `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256`, `hmac-sha2-512`.
- **SSH session keepalive** — `ClientAliveInterval 300`, `ClientAliveCountMax 3`, `TCPKeepAlive yes` to reduce disconnects during config changes.

#### Changed
- Install URL example in the script header now uses the neutral `https://your-server/...` placeholder instead of a hardcoded personal domain.

### v2.0 — 2026-08-03

#### Added
- fail2ban with **9 jails** (sshd + 6 Nginx scan detectors + bot search + rate-limit cooldown).
- Nginx hardening: hide version, 19 malicious UAs, sensitive-path deny, rate limiting, ghost-domain 444.
- Kernel hardening: disable `unprivileged_userns_clone` (blocks DirtyFrag / Bad Epoll local privilege escalation).
- Upgraded daily security scan (login audit / Nginx scans / resources / UFW / SSL expiry).
- Full backup + `sshd -t` syntax check to avoid locking yourself out.
