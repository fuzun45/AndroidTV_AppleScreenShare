#!/usr/bin/env bash
# 00-connect.sh - TV'ye adb ile baglanir ve temel cihaz bilgisini yazdirir.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

need_device || exit 1

log_info "Cihaz bilgileri okunuyor..."

model="$(adbs getprop ro.product.model | tr -d '\r\n')"
brand="$(adbs getprop ro.product.brand | tr -d '\r\n')"
device_name="$(adbs getprop ro.product.device | tr -d '\r\n')"
android_ver="$(adbs getprop ro.build.version.release | tr -d '\r\n')"
api_level="$(adbs getprop ro.build.version.sdk | tr -d '\r\n')"
board_platform="$(adbs getprop ro.board.platform | tr -d '\r\n')"
manufacturer="$(adbs getprop ro.product.manufacturer | tr -d '\r\n')"

printf '\n=== TV Cihaz Bilgisi (%s) ===\n' "$DEV"
printf 'Marka          : %s\n' "$brand"
printf 'Uretici        : %s\n' "$manufacturer"
printf 'Model          : %s\n' "$model"
printf 'Cihaz adi      : %s\n' "$device_name"
printf 'Android surumu : %s (API %s)\n' "$android_ver" "$api_level"
printf 'Board platform : %s\n' "$board_platform"
printf '===============================\n'

log_ok "Baglanti basarili."
