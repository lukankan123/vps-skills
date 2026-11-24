# Releasing / 发布流程

> 适用对象：维护本仓库的人（包括自动化助手）。改动发布物之前先读完这一页。

## 一条硬规矩：中英文文档必须同步

任何文档改动都要**同时**落到下面成对的四份文件，不允许只改一半：

| English | 中文 |
|---|---|
| `README.md` | `README_cn.md` |
| `skills/vps-security/SKILL.en.md` | `skills/vps-security/SKILL.md` |

**为什么**：中英不一致时，读者会以为其中一份是"过期的旧版本"，进而对整个仓库的维护状态失去信任 ——
这和 `curl | bash` 一样，属于"劝退信号"。

**怎么查**：改完跑一次关键项一致性自检（示例）：

```bash
for f in README.md README_cn.md skills/vps-security/SKILL.md skills/vps-security/SKILL.en.md; do
  printf '%-40s minisign验签=%s sha256sum=%s pipe-bash=%s\n' "$f" \
    "$(grep -c 'minisign -Vm' "$f")" \
    "$(grep -c 'sha256sum -c' "$f")" \
    "$(grep -cE 'curl[^\n]*\|[[:space:]]*(sudo[[:space:]]+)?bash' "$f")"
done
```

英文与中文对应的两行，数量应当一致（`pipe-bash` 必须为 0，正文里的说明性提及除外）。

## 发布步骤

```bash
cd /root/vps-skills
bash scripts/sign-release.sh     # 重算 SHA256SUMS → 签名 → 同步站点 → 闭环自验
git add -A && git commit -m "..." && git push
git tag -f vps-security-vX.Y && git push -f origin vps-security-vX.Y
```

`scripts/sign-release.sh` 会做四件事，任何一步失败都会 `exit 1`：

1. 依据实际脚本重新生成 `SHA256SUMS`（**不要手改这个文件**，手改必漏）
2. 用 minisign 私钥签名 → `SHA256SUMS.minisig`
3. 同步站点分发目录：只放** HTTP 真能取到**的文件（脚本 + 校验值），签名/公钥/文档随 zip 分发
   —— 站点是 Next.js 应用，`.md` / `.minisig` / `.pub` 会被判 404，所以校验值/签名/公钥的权威来源是 GitHub（raw 或 API），与下载源相互独立
4. 闭环自验：验签名、验校验值、验站点与仓库一致

## 密钥

- 私钥：**由项目所有者离线保管，服务器上不保留**（本仓库曾于 2026-10-08 生成并随后从服务器擦除，
  删除前记录的私钥 SHA256 为 `30d639688b9b1993468afe15c57e49ba9415755b04da359a218f8348ae3fcd8d`，大小 262 字节；所有者本地副本已逐字节核对一致）
- 公钥：随仓库发布（`minisign.pub`），Key ID `B77452EF0FED6854`；服务器保留一份仅用于**核对**（`--check`）
- 发布签名版时需要临时提供私钥，二选一：
  1. 把私钥放回 `/root/.hermes/secrets/vps-skills-signing/minisign.key`，发布后**立即取走并删除**
  2. 指向临时位置：`MINISIGN_KEYDIR=/path/to/keydir bash scripts/sign-release.sh`
- 只想核对已发布产物（不需要私钥）：`bash scripts/sign-release.sh --check`
- ⚠️ 如私钥丢失：用同一把密钥无法再签新版本，须生成新密钥并重新走「独立渠道公布 Key ID」流程，
  历史版本仍可用旧公钥验证（旧公钥与说明要保留）
- 公钥：随仓库发布（`minisign.pub`），Key ID `B77452EF0FED6854`
- 如需更换密钥：**先**把新公钥与 Key ID 用独立渠道公布（站点公告/README 同时更新），再签新版本；
  历史版本签名用旧公钥验，两把公钥都要保留说明

### 私钥丢失之后（2026-11-24 已发生）

`2026-11-24`：所有者重装系统，离线保管的私钥随之丢失，服务器侧也确认无副本（全盘搜过，
只找到 Tailscale 的 TLS 证书）。旧 Key ID `5AB319E92F6F292` 的私钥因此不可恢复。

**当前状态**：v2.2.1 这一版**没有签名**。`SHA256SUMS.minisig` 已删除 ——
留一份对不上内容的旧签名比没有签名更糟，它会让读者以为「签名有效、内容没被改过」。

`scripts/check-repo-consistency.py` 相应调整：签名文件**缺失**时降级为警告，
但**存在就必须验得过**（验不过说明有人动过校验值，仍然是硬错误）；
SHA256 校验值比对在**任何情况下都必须通过**，签名缺失时它是唯一的完整性防线。

**重建步骤**（必须由所有者亲手做，私钥不得经过服务器或任何聊天工具）：

1. 在自己电脑上装 minisign（Windows 有单文件 exe，免安装）
2. `minisign -G -p minisign.pub -s minisign.key` —— 会提示设密码，存进密码管理器
3. `minisign.key` 存到密码管理器附件或加密 U 盘，**不要只留桌面一份**
4. 把 `minisign.pub` 的**内容**贴给维护者 —— 公钥公开无妨
5. 维护者替换仓库里的 `minisign.pub`，并把一致性检查的签名项改回硬性
6. 用独立渠道公布新 Key ID（站点公告 / README 同时改），然后签第一版

**以后每次发布**都得所有者本地跑一次：

```
minisign -S -s minisign.key -m SHA256SUMS
```

把生成的 `SHA256SUMS.minisig` 一起提交。机器替不了这一步，这是离线私钥的固有代价。

**签名能防什么、不能防什么**（要在文档里对读者说清）：

- 能防：下载链路被换文件（镜像、CDN、中间层、代理）
- 不能防：仓库主机本身被攻破（密钥与仓库同机）→ 所以重要场合要**独立渠道核对 Key ID**

## 推送后的注意事项

`raw.githubusercontent.com` 有 CDN 缓存。刚推送完如果读者验签/校验失败，多半是 CDN 还在吐上一版，
等几分钟重试即可；`SHA256SUMS` 也可用 GitHub API（`/repos/.../contents/SHA256SUMS`）读取，API 不带该缓存。
