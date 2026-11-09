#!/bin/bash
# build_red8.sh -- rebuild loader-red8b from the CI kernel, entirely on this machine.
#
#   bash tools/build_red8.sh        (from Windows Git Bash, or from inside WSL)
#
# Inputs (all already here; see 项目交接-全量上下文-20261103.md §7):
#   _ci/k/kernel.development.pandora        CI 编出的新内核（已含三处适配）
#   _ipsw/kernelcache.release.iphone10b     IPSW 原厂 kernelcache（预链接用）
#   _ipsw/Firmware/087-86698-044.dmg.trustcache  静态 trust cache
#   _ipsw/d22ap.adt                          原厂 D22AP 设备树（ADT 的 /product 来源）
#   popsicle-port/boots/loader-ct5-boot.img.gz   上一次能跑的镜像（继承 /chosen 与 mod1）
# 中间产物在 WSL 的 /tmp/red8.*，失败可原地重跑。
#
# 排错要点（都踩过）：
#   · cmdline 有空格，必须写在文件里执行，塞进 bash -lc '...' 会丢参数；
#   · WSL 里 bash -c 传 $CMD 会再分词，所以整段主体写在独立脚本里；
#   · 输出文件名带空格/中文时 sha256sum 会加转义，别用正则去解析它。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
if grep -qi microsoft /proc/version 2>/dev/null; then
	W=$(cd "$HERE/../.." && pwd)
	exec bash "$HERE/build_red8_body.sh" "$W"
fi
W=$(wslpath -u 'C:\dsh-对话')
exec wsl -d Ubuntu-24.04 -- bash -lc "bash '$HERE/build_red8_body.sh' '$W'"
