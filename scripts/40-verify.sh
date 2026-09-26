#!/usr/bin/env bash
# 40-verify.sh - Salt okunur dogrulama testleri. Her satir PASS/FAIL basar.
# Herhangi bir FAIL varsa exit kodu != 0 doner.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

need_device || exit 1
setup_out_dir "verify"

FAIL_COUNT=0

pass() { printf 'PASS - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# 1) Paket kurulu mu?
if adbs pm list packages "$PKG" | safe_grep -q "^package:$PKG$"; then
    pass "Paket kurulu ($PKG)"
else
    fail "Paket kurulu degil ($PKG)"
fi

# 2) Surec calisiyor mu?
if adbs pidof "$PKG" | safe_grep -q '[0-9]'; then
    pass "Surec calisiyor"
else
    fail "Surec calismiyor"
fi

# 3) Port 7000 dinleniyor mu?
port_hex="1B58"  # 7000 decimal -> hex
port_listening=0
if adbs_raw 'command -v ss >/dev/null 2>&1'; then
    if adbs ss -ltn | safe_grep -qE ':7000\b'; then port_listening=1; fi
elif adbs_raw 'command -v netstat >/dev/null 2>&1'; then
    if adbs netstat -ltn | safe_grep -qE ':7000\b'; then port_listening=1; fi
fi
if [ "$port_listening" -eq 0 ]; then
    if adbs cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | safe_grep -qi ":${port_hex} "; then
        port_listening=1
    fi
fi
if [ "$port_listening" -eq 1 ]; then
    pass "Port 7000 dinleniyor"
else
    fail "Port 7000 dinlenmiyor"
fi

# 4) mDNS: _airplay._tcp ve _raop._tcp Mac'ten gorunuyor mu?
tv_ip="${DEV%%:*}"
check_mdns() {
    svc="$1"
    out="$OUT/dnssd-${svc//[._]/}.txt"
    if command -v dns-sd >/dev/null 2>&1; then
        ( dns-sd -B "$svc" local. > "$out" 2>&1 & echo $! > "$out.pid" )
        sleep 6
        [ -f "$out.pid" ] && { kill "$(cat "$out.pid")" 2>/dev/null || true; rm -f "$out.pid"; }
        if safe_grep -q 'Add' "$out"; then
            pass "mDNS $svc goruluyor"
        else
            fail "mDNS $svc gorunmuyor (6sn icinde)"
        fi
    else
        fail "dns-sd komutu yok, mDNS $svc kontrol edilemedi"
    fi
}
check_mdns "_airplay._tcp"
check_mdns "_raop._tcp"

# 5) Idle iken wakelock tutuluyor mu (bilgi amacli, PASS/FAIL degil - not olarak yazdir)
adbs dumpsys power > "$OUT/dumpsys-power.txt"
wl="$(safe_grep -i "$PKG" "$OUT/dumpsys-power.txt")"
if [ -n "$wl" ]; then
    printf 'BILGI - Idle wakelock bulundu (asagida)\n%s\n' "$wl"
else
    printf 'BILGI - Idle wakelock bulunamadi (beklenen davranis)\n'
fi

# 6) CPU / PSS
adbs top -n 1 -b > "$OUT/top.txt" 2>&1
app_cpu_line="$(safe_grep "$PKG" "$OUT/top.txt" | head -n1)"
printf 'BILGI - CPU satiri (top -n1 -b, cok cekirdekli sistemde %%100 = 1 cekirdek): %s\n' "${app_cpu_line:-bulunamadi}"

adbs dumpsys meminfo "$PKG" > "$OUT/meminfo-pkg.txt"
pss_line="$(safe_grep -m1 'TOTAL PSS' "$OUT/meminfo-pkg.txt")"
if [ -n "$pss_line" ]; then
    pass "PSS okunabildi: $pss_line"
else
    fail "PSS okunamadi (dumpsys meminfo $PKG)"
fi

# 7) Guvenlik probu: TCP baglanti odakli aktiviteyi degistiriyor mu?
focus_before="$(adbs dumpsys window | safe_grep -E 'mCurrentFocus|mFocusedApp')"
was_ours=0
echo "$focus_before" | safe_grep -q "$PKG" && was_ours=1

if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$tv_ip" 7000 >/dev/null 2>&1 || true
    printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 2 "$tv_ip" 7000 >/dev/null 2>&1 || true
else
    log_warn "nc komutu bulunamadi, guvenlik probu atlandi"
fi

sleep 3
focus_after="$(adbs dumpsys window | safe_grep -E 'mCurrentFocus|mFocusedApp')"
is_ours_after=0
echo "$focus_after" | safe_grep -q "$PKG" && is_ours_after=1

if [ "$was_ours" -eq 0 ] && [ "$is_ours_after" -eq 1 ]; then
    fail "Guvenlik: cizgisiz TCP baglantisi uygulamayi one getirdi (onceki odakta yoktu, sonra oldu)"
else
    pass "Guvenlik: TCP probu odagi degistirmedi"
fi
{
    echo "-- Once --"; echo "$focus_before"
    echo "-- Sonra --"; echo "$focus_after"
} > "$OUT/focus-before-after.txt"

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
    log_ok "Tum kontroller PASS."
    exit 0
else
    log_err "$FAIL_COUNT kontrol FAIL. Detaylar: $OUT"
    exit 1
fi
