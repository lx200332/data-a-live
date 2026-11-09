#!/bin/bash
# build_linux.sh -- build pandora-loader with WSL's clang/lld instead of the NDK.
#
#   build_linux.sh [OUT=dir]      (default out/, reads out/payload.bin + out/logo.bin)
#
# Same objects, same linker script, same checks as build.sh; only the toolchain differs
# (--target=aarch64-none-elf, ld.lld/llvm-objcopy/llvm-readelf from llvm-18).
set -euo pipefail
cd "$(dirname "$0")"
CC=${CC:-clang}
LD=${LD:-ld.lld}
READELF=${READELF:-llvm-readelf}
OBJCOPY=${OBJCOPY:-llvm-objcopy}
out=${OUT:-out}
mkdir -p "$out"
[ -f "$out/payload.bin" ] || { echo "missing $out/payload.bin" >&2; exit 1; }
[ -f "$out/logo.bin" ] || : > "$out/logo.bin"

flags=(--target=aarch64-none-elf -O2 -ffreestanding -fno-builtin -nostdlib -fno-pic
       -fno-stack-protector -mgeneral-regs-only -mstrict-align -Wall -Wextra -Werror)
"$CC" "${flags[@]}" -c start.S -o "$out/start.o"
"$CC" "${flags[@]}" -DPAYLOAD="\"$out/payload.bin\"" -c payload.S -o "$out/payload.o"
"$CC" "${flags[@]}" -DLOGO="\"$out/logo.bin\"" -c logo.S -o "$out/logo.o"
"$CC" "${flags[@]}" -c loader.c -o "$out/loader.o"
if "$READELF" -r "$out/loader.o" | grep -q R_AARCH64_ABS; then
	echo "absolute relocation in loader.c" >&2; exit 1
fi
"$LD" -T loader.ld --build-id=none "$out/start.o" "$out/loader.o" "$out/logo.o" "$out/payload.o" -o "$out/loader.elf"
"$OBJCOPY" -O binary "$out/loader.elf" "$out/Image"

python3 - "$out/Image" "$out/payload.bin" <<'PY'
import struct, sys
img = open(sys.argv[1], 'rb').read(); pl = open(sys.argv[2], 'rb').read()
size = struct.unpack_from('<Q', img, 16)[0]
assert img[0x38:0x3c] == b'ARM\x64', 'no arm64 Image magic'
assert size == len(img), (hex(size), hex(len(img)))
off = img.find(pl[:64])
assert off > 0 and off % 4096 == 0 and img[off:off + len(pl)] == pl, 'payload not embedded'
print('Image %d bytes, payload at 0x%x (%d bytes)' % (len(img), off, len(pl)))
PY
python3 -I ../../tools/mkbootimg_v4.py "$out/Image" "$out/loader-boot.img"
python3 -I ../../tools/bootimg_info.py "$out/loader-boot.img"
sha256sum "$out/loader-boot.img"
