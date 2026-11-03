#!/usr/bin/env python3
"""把上游 data-a-live（Xiaomi 17 Pro / pandora / 1220x2656）适配到
Xiaomi 17 Pro Max（popsicle / 2509FPN0BC / SM8850 canoe / 1200x2608）。

改动内容全部记录在同目录的 popsicle-adapt.patch 里（569 行，21 个文件，
81 增 81 删）。本脚本只是它的应用器，保证幂等、可逆、可校验：

  python3 adapt_popsicle.py --check    # 校验能否干净应用（不写文件）
  python3 adapt_popsicle.py            # 应用改动
  python3 adapt_popsicle.py --revert   # 反向还原到上游原样

判据：
  - 已应用 -> git diff 里有这些改动，--check 报「已应用」
  - 未应用 -> --check 通过，执行即写入
  - 冲突   -> 报错并不写任何东西（不会留下半个文件）

为什么用 patch 而不是脚本内嵌规则表：规则表容易与真实改动漂移，
patch 由 `git diff` 直接产生，永远等于真实改动，也能在 pristine 上游
上 `git apply --check` 独立复核。逐条改动的依据见同目录 DIFF.md。
"""
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
PATCH = ROOT / "popsicle-adapt.patch"
CHECK = "--check" in sys.argv
REVERT = "--revert" in sys.argv


def git(*args, check=True):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} 失败：\n{r.stdout}{r.stderr}")
    return r


def stat(patch):
    """从 patch 里数出文件数、增行、删行，只用来自报家门。"""
    files = plus = minus = 0
    for line in patch.read_text(encoding="utf-8").splitlines():
        if line.startswith("diff --git "):
            files += 1
        elif line.startswith("+") and not line.startswith("+++"):
            plus += 1
        elif line.startswith("-") and not line.startswith("---"):
            minus += 1
    return files, plus, minus


def main():
    if not PATCH.exists():
        raise SystemExit(f"缺少 {PATCH.name}；先在上游上执行 git diff > popsicle-adapt.patch")

    base = git("rev-parse", "--short", "HEAD").stdout.strip()
    # 只看已跟踪文件的改动；未跟踪的 adapt_popsicle.py / popsicle-adapt.patch / DIFF.md 不算
    touched = [l for l in git("diff", "--name-only").stdout.splitlines() if l]

    if REVERT:
        if not touched:
            print(f"已是上游原样（{base}），无需还原。")
            return 0
        r = git("apply", "-R", "--check", str(PATCH), check=False)
        if r.returncode != 0:
            raise SystemExit("反向还原会冲突，未做任何修改：\n" + r.stderr)
        git("apply", "-R", str(PATCH))
        print(f"已还原 {len(touched)} 个文件到上游原样（{base}）。")
        return 0

    if not touched:
        r = git("apply", "--check", str(PATCH), check=False)
        if r.returncode != 0:
            raise SystemExit("无法干净应用，未做任何修改：\n" + r.stderr)
        files, plus, minus = stat(PATCH)
        if CHECK:
            print(f"待应用：{files} 个文件 {plus} 增 {minus} 删（基线 {base}）。")
            return 0
        git("apply", str(PATCH))
        print(f"已应用 {files} 个文件 {plus} 增 {minus} 删（基线 {base}）。")
        return 0

    # 已有改动：确认是不是我们自己那批
    r = git("apply", "-R", "--check", str(PATCH), check=False)
    if r.returncode == 0:
        print(f"已应用（{len(touched)} 个文件有改动，可用 --revert 还原）。")
        return 0

    raise SystemExit(
        "工作区有改动，但既不是干净的适配状态、也不能被本 patch 反向覆盖：\n"
        + r.stderr + "\n请先 git stash 或 git checkout -- . 再试。")


if __name__ == "__main__":
    sys.exit(main())
