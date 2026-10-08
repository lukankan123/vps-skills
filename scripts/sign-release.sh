#!/usr/bin/env bash
#================================================================
# vps-skills 发布脚本 —— 让「校验值 + 签名 + 站点同步」永远一致
#
# 用法（在仓库根目录执行）：
#   bash scripts/sign-release.sh              # 只签名 + 同步 + 自验
#   bash scripts/sign-release.sh --check      # 只做校验（CI / 发布前自查）
#
# 设计要点：
#   1. SHA256SUMS 由本脚本**重新生成**，不手改 —— 手改必漏
#   2. SHA256SUMS 用 minisign 签名（Ed25519），私钥只在本机、600 权限
#   3. 站点分发目录同步拷贝脚本 + 校验值 + 签名 + 公钥，并重建 zip
#   4. 最后做**闭环自验**：拿公钥验签名、拿校验值验脚本，任何一步失败即 exit 1
#
# 中英文文档必须同步：任何文档改动请同时更新 README.md 与 README_cn.md、
# SKILL.en.md 与 SKILL.md（本脚本不做内容改写，只在结尾提醒你 diff 一下）。
#================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYDIR="${MINISIGN_KEYDIR:-/root/.hermes/secrets/vps-skills-signing}"
SIGNKEY="$KEYDIR/minisign.key"
PUBKEY="$KEYDIR/minisign.pub"
SITE="${SITE_DIR:-/var/www/portfolio/public/skills}"
SCRIPT="$REPO/skills/vps-security/scripts/vps-secure.sh"
DIST_NAME="vps-security.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# ---------- 1. 重新生成 SHA256SUMS ----------
gen_sums() {
  local h
  h="$(sha256sum "$SCRIPT" | awk '{print $1}')"
  {
    echo "# vps-skills — integrity checksums"
    echo "# Verify: sha256sum -c SHA256SUMS --ignore-missing"
    echo "# 分发版（保存为 $DIST_NAME）与仓库内路径都登记，同一份文件。"
    echo "# 校验值务必取自 GitHub 仓库（与下载源分离）："
    echo "#   https://raw.githubusercontent.com/lukankan123/vps-skills/main/SHA256SUMS"
    echo "$h  $DIST_NAME"
    echo "$h  skills/vps-security/scripts/vps-secure.sh"
  } > "$REPO/SHA256SUMS"
  log "SHA256SUMS 已生成（${h:0:16}…）"
}

# ---------- 2. 签名 ----------
sign_sums() {
  [ -x "$(command -v minisign)" ] || die "未安装 minisign（apt-get install -y minisign）"
  [ -f "$SIGNKEY" ] || die "找不到私钥 $SIGNKEY（发布机才有私钥，这是设计如此）"
  # -S 覆盖旧签名；私钥无口令时不会交互
  minisign -S -s "$SIGNKEY" -m "$REPO/SHA256SUMS" -c "vps-skills SHA256SUMS" >/dev/null
  log "SHA256SUMS.minisig 已生成"
}

# ---------- 3. 同步站点 ----------
sync_site() {
  [ -d "$SITE" ] || { warn "站点目录不存在，跳过同步：$SITE"; return 0; }
  # 站点只放「HTTP 真能取到」的文件：脚本 + 校验值 + zip
  # （.md / .minisig / .pub 会被 Next 应用判 404，故只随 zip 分发；签名/公钥/文档以 GitHub 为准）
  rm -f "$SITE"/*.bak_* 2>/dev/null || true
  install -m 0644 "$SCRIPT"          "$SITE/$DIST_NAME"
  install -m 0644 "$REPO/SHA256SUMS" "$SITE/SHA256SUMS"
  rm -f "$SITE/README.md" "$SITE/CHANGELOG.md" "$SITE/SHA256SUMS.minisig" "$SITE/minisign.pub" 2>/dev/null || true
  ( cd "$SITE" && rm -f vps-security.zip && \
    cp "$REPO/README_cn.md" README.md && cp "$REPO/CHANGELOG.md" CHANGELOG.md && \
    cp "$REPO/SHA256SUMS.minisig" SHA256SUMS.minisig && cp "$REPO/minisign.pub" minisign.pub && \
    zip -q vps-security.zip README.md "$DIST_NAME" CHANGELOG.md SHA256SUMS SHA256SUMS.minisig minisign.pub && \
    rm -f README.md CHANGELOG.md SHA256SUMS.minisig minisign.pub )
  log "站点已同步（含 zip）"
}

# ---------- 4. 闭环自验 ----------
verify_all() {
  log "自验中…"
  minisign -Vm "$REPO/SHA256SUMS" -p "$PUBKEY" >/dev/null || die "签名自验失败"
  ( cd "$REPO" && sha256sum -c SHA256SUMS --ignore-missing >/dev/null ) || die "校验值自验失败"
  log "签名 + 校验值 自验通过"
  if [ -f "$SITE/$DIST_NAME" ]; then
    local a b
    a="$(sha256sum "$SCRIPT" | awk '{print $1}')"
    b="$(sha256sum "$SITE/$DIST_NAME" | awk '{print $1}')"
    [ "$a" = "$b" ] || die "站点分发的脚本与仓库不一致"
    # 签名已在上面用仓库文件验过；站点这份只需证明与仓库逐字节一致
    cmp -s "$REPO/SHA256SUMS" "$SITE/SHA256SUMS" || die "站点的校验值文件与仓库不一致"
    log "站点分发一致性通过"
  fi
}

if [ "$CHECK_ONLY" = "1" ]; then
  verify_all
else
  gen_sums
  sign_sums
  sync_site
  verify_all
  echo
  log "完成。别忘了："
  echo "   1) 中英文文档同步检查：README.md ↔ README_cn.md，SKILL.en.md ↔ SKILL.md"
  echo "   2) git add -A && git commit && git push"
  echo "   3) 推送后 raw CDN 可能滞后几分钟（校验失败时先等一会儿再试）"
fi
