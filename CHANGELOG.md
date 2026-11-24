# Changelog

All notable changes to this skills collection are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) loosely.
Versions are tied to the skill, not the repo.

---

## vps-security

## 待办（下次带私钥发布时处理）

以下两项在 CI 里是**警告级**（不阻塞），需要改 `vps-secure.sh` 本体 → 必须重新签名 →
因此必须由所有者临时提供离线私钥才能落地：

- `RANDOM_PORT` 是死变量：第 46/63/64 行赋值但全脚本从没读取（shellcheck SC2034）。
  需确认随机端口实际由 `SSH_PORT` 逻辑实现后，删掉它或让它真正生效。
- 第 515 行用了 `A && B || C` 写法（shellcheck SC2015）：
  `nginx -t && systemctl reload nginx && log … || warn …`，当 reload 失败时会打出
  「default_server 配置跳过（已有默认站点）」的**误导性**提示（防护本身不受影响），
  建议改写成显式 `if/else`。

### v2.2.1 — 2026-11-24

只修 bug，不加功能。三个问题都属于「装了但防护静默失效」那一类 —— 不会报错，但等于没防护。

**1. 巡检脚本取 IP 取错，自动封禁实际是坏的**

`vps-secure.sh` 和 SKILL.md 巡检段落里原来写 `awk '{print $NF}'`。sshd 日志行是：

```
Failed password for root from 1.2.3.4 port 2222 ssh2
```

`$NF` 取到的是 `ssh2`，不是 IP。后面 `fail2ban-client set sshd banip "ssh2"` 等于没封 —— 看起来跑了，实际什么都没发生。改为取 `from` 后面那个字段。

同段连带修：失败次数永远显示空（`FAILED_IPS` 里只有 IP 没有计数）；ip-api 明文 HTTP 查询加了 `--max-time 5` 和失败跳过，不再阻塞封禁流程。

**2. `nginx-wpscan` 过滤器正则编译失败**

括号不平衡（左 3 右 4），fail2ban 直接报 `ERROR: Unable to compile regular expression`，这个 jail 起了也白起。

另外结尾的 `(\/|\?|$)` 在真实日志里也匹配不到 —— nginx 日志中路径后面跟的是空格（`"GET /wp-login.php HTTP/1.1"`），`$` 表示行尾。补上 `\s` 分支后实测命中。

**3. `nginx-bad-request` 过滤器加载就崩（此轮新发现）**

正则里的 `%00` `%0d` `%0a` 会被 Python `configparser` 当成插值语法：

```
configparser.InterpolationSyntaxError: '%' must be followed by '%' or '(', found: '%00|%0d|%0a|...'
```

整个过滤器文件解析失败。**fail2ban 配置里 `%` 必须写成 `%%`。**

**文档对齐**

- jail 数量 9 → 10（实际就是 10 个：sshd、sshd-ddos 和 8 个 nginx 类）
- 脚本路径 `scripts/vps-secure.sh` → `skills/vps-security/scripts/vps-secure.sh`（根目录的 `scripts/` 只有 CI 工具，原路径在 GitHub 上点开是 404）
- 脚本行数 624 → 625
- 中英文档同步

**验证方式**

8 个 fail2ban 过滤器全部用 `fail2ban-regex` 实测可加载；有对应样本路径的均命中（secscan 5 行、wpscan 1 行、phpscan 1 行、bad-request 1 行）。巡检的 IP 提取逻辑用仿真 auth.log 验证：旧写法输出 4 个 `ssh2`，新写法正确输出 `203.0.113.9 × 3`。

### v2.2 — 2026-10-08

- **新增 minisign 签名**：`SHA256SUMS.minisig` + 公钥 `minisign.pub`（Key ID 5AB319E92F6F292 —— 该私钥已于 2026-11-24 随系统重装丢失，现役公钥为 B77452EF0FED6854），文档给出「先验签名、再验哈希」的顺序
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
