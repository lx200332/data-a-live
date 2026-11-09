#!/bin/bash
# build_red8_body.sh -- the real work, runs inside WSL. Called by build_red8.sh.
set -euo pipefail
W=${1:?usage: build_red8_body.sh WORKSPACE}
REPO="$W/data-a-live-popsicle"
PORT="$W/popsicle-port"
export W REPO PORT
R=$(mktemp -d /tmp/red8.XXXX)
echo "work dir: $R"

echo '=== 1 原厂 kernelcache -> arm64 Mach-O ==='
python3 - "$R" <<'PY'
import os, struct, sys
sys.path.insert(0, os.environ['REPO'] + '/tools')
import adt
blob, info = adt.im4p_payload(open(os.environ['W'] + '/_ipsw/kernelcache.release.iphone10b', 'rb').read())
print('im4p type', info['type'], 'desc', info['desc'])
assert blob[:4] == b'\xca\xfe\xba\xbe', 'not a FAT'
nfat = struct.unpack('>I', blob[4:8])[0]
cputype, cpusub, off, size = struct.unpack('>IIII', blob[8:24])
print(f'fat: {nfat} arch, cpu 0x{cputype:x}, slice {size} bytes @0x{off:x}')
open(os.path.join(sys.argv[1], 'kc.macho'), 'wb').write(blob[off:off + size])
PY

echo '=== 2 预链接原厂 kext ==='
python3 "$REPO/tools/mkprelink.py" \
	"$W/_ci/k/kernel.development.pandora" "$R/kc.macho" "$R/prelinked" | tail -16

echo '=== 3 trust cache ==='
python3 - "$R" <<'PY'
import os, sys
sys.path.insert(0, os.environ['REPO'] + '/tools')
import adt
body, info = adt.im4p_payload(
    open(os.environ['W'] + '/_ipsw/Firmware/087-86698-044.dmg.trustcache', 'rb').read())
open(os.path.join(sys.argv[1], 'tc-mod0.bin'), 'wb').write(body)
print('mod0', len(body), 'bytes, type', info['type'])
PY
python3 "$REPO/tools/split_trustcache.py" "$PORT/boots/loader-ct5-boot.img.gz" "$R/refmods"

echo '=== 4 /chosen 设备状态 ==='
python3 "$REPO/tools/extract_adt.py" "$PORT/boots/loader-ct5-boot.img.gz" "$R/ref.adt"

echo '=== 5 boot.img ==='
CMD='debug=0x8 serial=3 cpus=8 keepsyms=1 rd=ufsroot0 ufsrw=1 rootrw=1 unentitled_ios_sim_launch=1 ignition_level=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=60 sweetfb_fill=1 sweetfb_noconsole=1 amfi_get_out_of_my_way=1 cs_enforcement_disable=1 sweetnull=SpringBoard,containermanagerd,backboardd pandora_touch=0xf pandora_logsecs=1 pandora_reboot_after=1800 pandora_gpu=15 pandora_gpu_metal=1 sweetiolog=lsd,SpringBoard sweetnoexec=bluetoothd,fairplayd.H2 sweetsample=containermanagerd,installd,lsd,SpringBoard fuxiwlan=1 pandora_adsp=2 pandora_files=1 pandora_bt=7 pandora_modem=2 pandora_thermal=1'
export D22AP_ADT="$W/_ipsw/d22ap.adt"
export WORK="$R/work"
bash "$REPO/wsl/make_image.sh" "$R/prelinked" "$R/boot.img" \
	--cmdline "$CMD" \
	--ref-adt "$R/ref.adt" \
	--tc "$R/tc-mod0.bin $R/refmods/tc-mod1.bin" | tail -14

echo '=== 6 终检 ==='
python3 "$REPO/tools/final_check.py" "$R/boot.img" | tail -4

cp "$R/boot.img" "$PORT/boots/loader-red8b-boot.img"
gzip -9 -f "$PORT/boots/loader-red8b-boot.img"
echo "--- done ---"
sha256sum "$R/boot.img"
ls -l "$PORT/boots/loader-red8b-boot.img.gz"
echo "kept: $R"
