#!/usr/bin/env python3
"""
仓库一致性自检 —— 本地和 CI 都用这一个脚本，避免两套标准。

检查项：
  1. 版本号一致：脚本头部的 vX.Y 必须出现在四份文档里
  2. 中英文档同步：两份英文 ↔ 两份中文，关键项计数与结构指引必须一致
  3. 无管道执行：任何 fenced 代码块里不得出现 curl/wget 直接管道给 sh/bash
  4. SHA256SUMS 同时覆盖「分发文件名」与「仓库内路径」，且两者哈希相同
  5. 签名与校验值自洽（装了 minisign 时执行；没装则跳过并提示）

退出码 0 = 全部通过；1 = 有失败项。
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "skills/vps-security/scripts/vps-secure.sh"
DOCS = {
    "en": [ROOT / "README.md", ROOT / "skills/vps-security/SKILL.en.md"],
    "cn": [ROOT / "README_cn.md", ROOT / "skills/vps-security/SKILL.md"],
}
PAIRS = [(ROOT / "README.md", ROOT / "README_cn.md"),
         (ROOT / "skills/vps-security/SKILL.en.md", ROOT / "skills/vps-security/SKILL.md")]

failures: list[str] = []


def report(ok: bool, ok_msg: str, bad_msg: str) -> None:
    print(("  ✅ " if ok else "  ❌ ") + (ok_msg if ok else bad_msg))
    if not ok:
        failures.append(bad_msg)


def fence_blocks(text: str) -> list[str]:
    """取出所有 fenced code block 的内容。"""
    return re.findall(r"```[^\n]*\n(.*?)```", text, re.S)


print("① 版本号一致")
m = re.search(r"^#\s*.*?(v\d+\.\d+)", SCRIPT.read_text(encoding="utf-8"), re.M)
version = m.group(1) if m else None
report(version is not None, f"脚本版本号: {version}", "脚本头部找不到 vX.Y 版本号")
if version:
    for lang, paths in DOCS.items():
        for p in paths:
            report(version in p.read_text(encoding="utf-8"),
                   f"{p.relative_to(ROOT)} 提到 {version}",
                   f"{p.relative_to(ROOT)} 没提到 {version}（版本号漂移）")

print("\n② 中英文档同步")
for en, cn in PAIRS:
    te, tc = en.read_text(encoding="utf-8"), cn.read_text(encoding="utf-8")
    for label, pattern in [("验签命令", r"minisign -Vm"),
                           ("校验命令", r"sha256sum -c"),
                           ("维护指引", r"RELEASING")]:
        a, b = len(re.findall(pattern, te)), len(re.findall(pattern, tc))
        report(a == b, f"{en.name} ↔ {cn.name}: {label} 计数一致（{a}）",
               f"{en.name}({a}) 与 {cn.name}({b}) 的「{label}」计数不一致")

print("\n③ 代码块里不得有管道执行（curl|bash 这类）")
pipe_re = re.compile(r"\b(?:curl|wget)\b[^\n|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b")
for paths in DOCS.values():
    for p in paths:
        hits = [b for b in fence_blocks(p.read_text(encoding="utf-8")) if pipe_re.search(b)]
        report(not hits, f"{p.name}: 无管道执行", f"{p.name}: 代码块里仍有管道执行（{len(hits)} 处）")

print("\n④ SHA256SUMS 覆盖两种文件名且哈希相同")
sums_path = ROOT / "SHA256SUMS"
entries = {}
for line in sums_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split()
    if len(parts) >= 2:
        entries[parts[-1].lstrip("*")] = parts[0]
need = ["vps-security.sh", "skills/vps-security/scripts/vps-secure.sh"]
for n in need:
    report(n in entries, f"SHA256SUMS 覆盖 {n}", f"SHA256SUMS 缺 {n} 的记录")
report(len({entries.get(n) for n in need}) == 1,
       "两个文件名指向同一份内容（哈希一致）",
       "两个文件名的哈希不一致（分发版与仓库版内容不同）")

actual = subprocess.run(["sha256sum", str(SCRIPT)], capture_output=True, text=True).stdout.split()[0]
report(entries.get("skills/vps-security/scripts/vps-secure.sh") == actual,
       "仓库内脚本的实际哈希与 SHA256SUMS 一致",
       "脚本已改动但 SHA256SUMS 没重新生成（快跑 scripts/sign-release.sh）")

print("\n⑤ 签名自洽（需要 minisign）")
if shutil.which("minisign"):
    sig_ok = SCRIPT.exists() and (ROOT / "SHA256SUMS.minisig").exists()
    report(sig_ok, "签名文件存在", "缺少 SHA256SUMS.minisig")
    if sig_ok:
        r = subprocess.run(["minisign", "-Vm", "SHA256SUMS", "-p", "minisign.pub"],
                           cwd=ROOT, capture_output=True, text=True)
        report(r.returncode == 0, "SHA256SUMS 签名验证通过",
               f"SHA256SUMS 签名验证失败：{(r.stdout + r.stderr).strip()[:120]}")
        chk = subprocess.run(["sha256sum", "-c", "SHA256SUMS", "--ignore-missing"],
                             cwd=ROOT, capture_output=True, text=True)
        report(chk.returncode == 0, "校验值与脚本一致", "校验值比对失败")
else:
    print("  ⏭️  未安装 minisign，跳过（CI 里会装）")

print("\n⑥ 危险模式扫描（忽略注释行）")
code_lines: list[tuple[int, str]] = []
for i, line in enumerate(SCRIPT.read_text(encoding="utf-8").splitlines(), 1):
    stripped = re.sub(r"(^|\s)#.*$", "", line)  # 去掉整行/行尾注释
    if stripped.strip():
        code_lines.append((i, stripped))

DANGER = [
    ("eval 执行", re.compile(r"(^|[^\w])eval\s")),
    ("base64 解码", re.compile(r"base64\s+(-d|--decode)")),
    ("管道执行（下载即运行）", re.compile(r"\b(?:curl|wget)\b[^\n|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b")),
]
for label, pat in DANGER:
    hits = [i for i, l in code_lines if pat.search(l)]
    report(not hits, f"代码里无「{label}」",
           f"脚本代码里出现「{label}」：行 {hits[:5]}（注释里的说明不计）")

print()
if failures:
    print(f"❌ 共 {len(failures)} 项未通过：")
    for f in failures:
        print("   - " + f)
    sys.exit(1)
print("✅ 全部通过")
