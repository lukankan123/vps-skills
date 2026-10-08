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

- 私钥：`/root/.hermes/secrets/vps-skills-signing/minisign.key`（`600`，**只留在发布机，绝不入库、绝不外发**）
- 公钥：随仓库发布（`minisign.pub`），Key ID `5AB319E92F6F292`
- 如需更换密钥：**先**把新公钥与 Key ID 用独立渠道公布（站点公告/README 同时更新），再签新版本；
  历史版本签名用旧公钥验，两把公钥都要保留说明

**签名能防什么、不能防什么**（要在文档里对读者说清）：

- 能防：下载链路被换文件（镜像、CDN、中间层、代理）
- 不能防：仓库主机本身被攻破（密钥与仓库同机）→ 所以重要场合要**独立渠道核对 Key ID**

## 推送后的注意事项

`raw.githubusercontent.com` 有 CDN 缓存。刚推送完如果读者验签/校验失败，多半是 CDN 还在吐上一版，
等几分钟重试即可；`SHA256SUMS` 也可用 GitHub API（`/repos/.../contents/SHA256SUMS`）读取，API 不带该缓存。
