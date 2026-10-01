#!/bin/bash
# Graph89 Remastered - TI graphing calculator emulator for iPhone
# Copyright (C) 2026 JH. GNU General Public License version 3 or later (see LICENSE).
#
# Downloads free calculator operating systems for the emulator tests into the folder given (they are never part of
# the app, which does not include any calculator OS):
#   PedroM 0.83 (TI-89, TI-89 Titanium), Patrick Pelissier, GPL: www.ticalc.org/archives/files/fileinfo/319/31951.html
#   KnightOS kernel 0.6.11 (TI-83 Plus, TI-83 Plus SE, TI-84 Plus, TI-84 Plus SE), MIT: github.com/KnightOS/kernel
# The kernel's boot page jumps to 4000h, where TilEm (unlike a real calculator) has no code mapped after a reset; the
# jump is patched to 0000h, where the kernel's own reset vector is, after checking the bytes around it.
set -euo pipefail

out="${1:?usage: fetch-test-os.sh <folder>}"
mkdir -p "$out"
cd "$out"

if [ ! -f PedroM-89.89u ] || [ ! -f PedroM-89ti.89u ]; then
    curl -fsSL --retry 3 -o pedrom.zip https://www.ticalc.org/pub/89/os/pedrom.zip
    unzip -o -j -q pedrom.zip 'pedrom/PedroM-89.89u' 'pedrom/PedroM-89ti.89u'
    rm -f pedrom.zip
fi

for m in TI83p TI83pSE TI84p TI84pSE; do
    if [ ! -f "kernel-$m.rom" ]; then
        curl -fsSL --retry 3 -o "kernel-$m.rom.orig" "https://github.com/KnightOS/kernel/releases/download/0.6.11/kernel-$m.rom"
        python3 - "kernel-$m.rom.orig" "kernel-$m.rom" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
rom = bytearray(open(src, 'rb').read())
off = len(rom) - 0x4000 + 0x20  # "jp 4000h" in the boot page
if rom[off - 2:off + 1] != b'\xc3\x00\x40':
    sys.exit(f'{src}: unexpected boot page bytes {rom[off - 2:off + 1].hex()} at {off - 2:#x}')
rom[off] = 0x00  # jp 0000h
open(dst, 'wb').write(rom)
print(f'{dst}: boot page jump patched at {off:#x}')
PY
        rm -f "kernel-$m.rom.orig"
    fi
done

shasum -a 256 PedroM-89.89u PedroM-89ti.89u kernel-*.rom
