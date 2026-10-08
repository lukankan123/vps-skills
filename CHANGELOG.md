# Changelog

All notable changes to this skills collection are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) loosely.
Versions are tied to the skill, not the repo.

---

## vps-security

### v2.2 — 2026-10-08

- **新增 minisign 签名**：`SHA256SUMS.minisig` + 公钥 `minisign.pub`（Key ID 5AB319E92F6F292），文档给出「先验签名、再验哈希」的顺序
- **新增 `scripts/sign-release.sh`**：重算校验值 → 签名 → 同步站点 → 闭环自验，一条流水跑完，避免漏签名
- 新增 `RELEASING.md`：发布流程 + 中英文文档必须同步的硬规矩
- **安装方式改变**：不再推荐 `curl ... | bash`（下载即执行，无审查机会，且校验值若与脚本同源等于没校验）
  改为四步：下载 → 校验 → 先读一遍 → 再执行
- **新增 `SHA256SUMS`**：脚本的 SHA256 校验值发布在仓库根目录，文档明确说明「校验值必须与下载源分离」
- 文档同步：README.md / README_cn.md / SKILL.md / SKILL.en.md 的示例全部改为四步法
- 修正文档里过期的版本号与行数（v2.0 / 561 行 → v2.2 / 当前行数）
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
- **Random port is now the default** — when `--port` is omitted, the script auto-generates a random high SSH port (40000–60000) instead of the old fixed 13521. `--port` still overrides with a manual value.

### v2.0 — 2026-08-03

#### Added
- fail2ban with **9 jails** (sshd + 6 Nginx scan detectors + bot search + rate-limit cooldown).
- Nginx hardening: hide version, 19 malicious UAs, sensitive-path deny, rate limiting, ghost-domain 444.
- Kernel hardening: disable `unprivileged_userns_clone` (blocks DirtyFrag / Bad Epoll local privilege escalation).
- Upgraded daily security scan (login audit / Nginx scans / resources / UFW / SSL expiry).
- Full backup + `sshd -t` syntax check to avoid locking yourself out.
