#!/bin/bash
# Сборка HevSocks5Tunnel.xcframework из hev-socks5-tunnel.
#
# Повторяет шаги исходного release.yml Tun2SocksKit (те же срезы, флаги и
# раскладка xcframework), с двумя отличиями:
#   1. ENABLE_STACK_OVERFLOW_DETECTOR выключен (см. ниже);
#   2. заглушка для симулятора лежит в репозитории (stub/), а не в чужом репо.
#
# Использование: scripts/build.sh [HEV_TAG]      (по умолчанию 2.18.0)
# Результат:     HevSocks5Tunnel.xcframework и HevSocks5Tunnel.xcframework.zip
#                в корне репозитория, sha256 zip'а — последней строкой вывода.
set -euo pipefail

HEV_TAG="${1:-2.18.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build-hev"
SRC="$WORK/hev-socks5-tunnel"

# С 2.17 hev-socks5-tunnel включает в Makefile
# TPFLAGS=ENABLE_STACK_OVERFLOW_DETECTOR=1. Детектор в hev_task_system_init
# ставит обработчики SIGSEGV/SIGBUS на весь процесс. В PacketTunnel рядом живёт
# Go-рантайм Xray: обработчик hev срабатывает первым, на Go-потоке
# hev_task_system_get_context() == NULL и сам обработчик падает, вместо того
# чтобы отдать сигнал Go. Пользы нет — он только печатает в stderr.
TPFLAGS="ENABLE_STACK_OVERFLOW_DETECTOR=0"

rm -rf "$WORK" "$ROOT/HevSocks5Tunnel.xcframework" "$ROOT/HevSocks5Tunnel.xcframework.zip"
mkdir -p "$WORK"

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$HEV_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/heiher/hev-socks5-tunnel "$SRC"

merge_libs() { # $1 — выходной .a
    libtool -static -o "$1" \
        "$SRC/bin/libhev-socks5-tunnel.a" \
        "$SRC/third-part/lwip/bin/liblwip.a" \
        "$SRC/third-part/yaml/bin/libyaml.a" \
        "$SRC/third-part/hev-task-system/bin/libhev-task-system.a" 2>/dev/null
}

build_hev() { # $1 — CC, $2 — CFLAGS/LFLAGS, $3 — выходной .a
    make -C "$SRC" clean >/dev/null
    make -C "$SRC" -j"$(sysctl -n hw.ncpu)" \
        PP="$1" CC="$1" \
        CFLAGS="$2" \
        LFLAGS="$2 -Wl,-Bsymbolic-functions" \
        TPFLAGS="$TPFLAGS" static >/dev/null
    mkdir -p "$(dirname "$3")"
    merge_libs "$3"
}

build_stub() { # $1 — CFLAGS, $2 — выходной .a
    mkdir -p "$(dirname "$2")"
    xcrun -sdk iphonesimulator clang $1 -O3 -c "$ROOT/stub/hev-main.c" -o "$2.o"
    libtool -static -o "$2" "$2.o"
    rm "$2.o"
}

echo "==> macOS arm64 + x86_64"
build_hev gcc "-arch x86_64 -mmacosx-version-min=12.0" "$WORK/macos_x86_64/libhev-socks5-tunnel.a"
build_hev gcc "-arch arm64 -mmacosx-version-min=12.0"  "$WORK/macos_arm64/libhev-socks5-tunnel.a"
mkdir -p "$WORK/macos"
lipo -create -o "$WORK/macos/libhev-socks5-tunnel.a" \
    "$WORK/macos_arm64/libhev-socks5-tunnel.a" "$WORK/macos_x86_64/libhev-socks5-tunnel.a"

echo "==> iphoneos arm64"
build_hev "xcrun --sdk iphoneos --toolchain iphoneos clang" "-arch arm64 -mios-version-min=12.0" \
    "$WORK/iphoneos/libhev-socks5-tunnel.a"

echo "==> iphonesimulator arm64 + x86_64 (заглушка)"
build_stub "-arch arm64 -mios-simulator-version-min=12.0"  "$WORK/sim_arm64/libhev-socks5-tunnel.a"
build_stub "-arch x86_64 -mios-simulator-version-min=12.0" "$WORK/sim_x86_64/libhev-socks5-tunnel.a"
mkdir -p "$WORK/sim"
lipo -create -o "$WORK/sim/libhev-socks5-tunnel.a" \
    "$WORK/sim_arm64/libhev-socks5-tunnel.a" "$WORK/sim_x86_64/libhev-socks5-tunnel.a"

# Проверки: детектор не подключён, публичный API на месте.
# (вывод nm сначала в переменную: grep -q под pipefail даёт SIGPIPE у nm)
syms="$(nm "$WORK/iphoneos/libhev-socks5-tunnel.a" 2>/dev/null)"
if grep -q " U _hev_task_stack_detector_new" <<<"$syms"; then
    echo "ОШИБКА: stack overflow detector включён" >&2; exit 1
fi
for sym in main main_from_file main_from_str quit stats; do
    for lib in iphoneos sim macos; do
        syms="$(nm -gU "$WORK/$lib/libhev-socks5-tunnel.a" 2>/dev/null)"
        grep -q " T _hev_socks5_tunnel_${sym}$" <<<"$syms" \
            || { echo "ОШИБКА: нет _hev_socks5_tunnel_${sym} в $lib" >&2; exit 1; }
    done
done

echo "==> xcframework"
mkdir -p "$WORK/include"
cp "$SRC/src/hev-main.h" "$WORK/include/hev-socks5-tunnel.h"
cp "$ROOT/Templates/HevSocks5Tunnel.template" "$WORK/include/module.modulemap"
xcodebuild -create-xcframework \
    -library "$WORK/iphoneos/libhev-socks5-tunnel.a" -headers "$WORK/include" \
    -library "$WORK/sim/libhev-socks5-tunnel.a"      -headers "$WORK/include" \
    -library "$WORK/macos/libhev-socks5-tunnel.a"    -headers "$WORK/include" \
    -output "$ROOT/HevSocks5Tunnel.xcframework" >/dev/null

(cd "$ROOT" && zip -qr HevSocks5Tunnel.xcframework.zip HevSocks5Tunnel.xcframework)
echo "hev-socks5-tunnel $HEV_TAG ($(git -C "$SRC" rev-parse --short HEAD))"
shasum -a 256 "$ROOT/HevSocks5Tunnel.xcframework.zip" | cut -c1-64
