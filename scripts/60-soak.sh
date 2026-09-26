#!/usr/bin/env bash
# 60-soak.sh - Yari-manuel dayaniklilik (soak) testleri.
# Kullanim:
#   60-soak.sh connect-cycles N
#   60-soak.sh boot-cycles N
#   60-soak.sh long <dakika>
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

MODE="${1:-}"
ARG="${2:-}"
[ -n "$MODE" ] || die "Kullanim: $0 {connect-cycles N | boot-cycles N | long DAKIKA}"

need_device || exit 1
setup_out_dir "soak-${MODE}"

SOAK_MD="$OUT/SOAK.md"
CRASH_FOUND=0

# Uygulamamiza ait SurfaceView katmani var mi (stale-layer kontrolu icin).
# --app-only: odak ipucu/tek-aday fallback'ini kullanmaz, sadece bilinen
# paket/namespace token'lariyla eslesen adaylari sayar (bkz. tools/layer_select.py).
app_surfaceview_layer() {
    adbs dumpsys SurfaceFlinger --list | python3 "$REPO_ROOT/tools/layer_select.py" --app-only 2>/dev/null | head -n1
}

{
    echo "# Soak Test Sonuclari - $MODE"
    echo
    echo "Baslangic: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
} > "$SOAK_MD"

check_crash() {
    adbs logcat -d -b crash > "$OUT/crash-buffer-$1.txt" 2>&1 || true
    if safe_grep -qE 'ANR in|FATAL EXCEPTION' "$OUT/crash-buffer-$1.txt"; then
        if safe_grep -q "$PKG" "$OUT/crash-buffer-$1.txt"; then
            return 1
        fi
    fi
    return 0
}

case "$MODE" in
    connect-cycles)
        N="${ARG:-1}"
        echo "| # | ANR/FATAL yok | Surec canli | PSS(KB) | SurfaceView temiz | Sonuc |" >> "$SOAK_MD"
        echo "|---|---|---|---|---|---|" >> "$SOAK_MD"
        i=1
        while [ "$i" -le "$N" ]; do
            printf '\n--- Cevrim %d/%d ---\n' "$i" "$N"
            printf 'Iphone/Mac uzerinden mirroring BASLATIN, sonra Enter tusuna basin...\n'
            read -r _
            sleep 2
            [ -n "$(app_surfaceview_layer)" ] \
                && log_ok "SurfaceView katmani goruldu (mirroring aktif gorunuyor)" \
                || log_warn "SurfaceView katmani bulunamadi (yine de devam ediliyor)"

            printf 'Simdi mirroring DURDURUN, sonra Enter tusuna basin...\n'
            read -r _
            sleep 3

            no_crash="EVET"; check_crash "cycle$i" || { no_crash="HAYIR"; CRASH_FOUND=1; }
            proc_alive="EVET"; adbs pidof "$PKG" | safe_grep -q '[0-9]' || proc_alive="HAYIR"
            pss="$(app_pss_kb)"

            layer_after="$(app_surfaceview_layer)"
            focus_after="$(adbs dumpsys window | safe_grep -E 'mCurrentFocus|mFocusedApp' | safe_grep "$PKG" || true)"
            surface_clean="EVET"
            if [ -n "$layer_after" ] || [ -n "$focus_after" ]; then
                surface_clean="HAYIR"
            fi

            result="OK"
            [ "$no_crash" = "HAYIR" ] && result="FAIL(crash)"
            [ "$proc_alive" = "HAYIR" ] && result="FAIL(surec)"
            [ "$surface_clean" = "HAYIR" ] && [ "$result" = "OK" ] && result="UYARI(stale-layer)"

            echo "| $i | $no_crash | $proc_alive | ${pss:-NA} | $surface_clean | $result |" >> "$SOAK_MD"
            i=$((i + 1))
        done
        ;;

    boot-cycles)
        N="${ARG:-1}"
        echo "| # | Onay | boot_completed | Servis calisiyor | Port 7000 | Sonuc |" >> "$SOAK_MD"
        echo "|---|---|---|---|---|---|" >> "$SOAK_MD"
        i=1
        while [ "$i" -le "$N" ]; do
            printf '\n--- Reboot dongusu %d/%d ---\n' "$i" "$N"
            printf 'Cihaz yeniden baslatilacak (adb reboot). Onayliyor musunuz? [y/N] '
            read -r ans
            case "$ans" in
                y|Y) ;;
                *) log_warn "Atlandi."; echo "| $i | Hayir | - | - | - | ATLANDI |" >> "$SOAK_MD"; i=$((i+1)); continue ;;
            esac

            "$ADB" -s "$DEV" reboot
            log_info "Cihazin donmesi bekleniyor..."
            "$ADB" wait-for-device 2>/dev/null || true

            boot_ok="HAYIR"
            tries=0
            while [ "$tries" -lt 60 ]; do
                bc="$(adbs getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ')"
                if [ "$bc" = "1" ]; then boot_ok="EVET"; break; fi
                sleep 5
                tries=$((tries + 1))
                # reboot sonrasi adb baglantisi kopmus olabilir
                "$ADB" connect "$DEV" >/dev/null 2>&1 || true
            done

            log_info "Ek 30 saniye bekleniyor (servislerin oturmasi icin)..."
            sleep 30

            svc_ok="HAYIR"
            adbs dumpsys activity services "$PKG" | safe_grep -q "$SERVICE_CLASS" && svc_ok="EVET"

            port_ok="HAYIR"
            if adbs_raw 'command -v ss >/dev/null 2>&1'; then
                adbs ss -ltn | safe_grep -qE ':7000\b' && port_ok="EVET"
            fi
            if [ "$port_ok" = "HAYIR" ]; then
                adbs cat /proc/net/tcp 2>/dev/null | safe_grep -qi ':1B58 ' && port_ok="EVET"
            fi

            result="OK"
            [ "$boot_ok" = "HAYIR" ] && result="FAIL(boot)"
            [ "$svc_ok" = "HAYIR" ] && [ "$result" = "OK" ] && result="FAIL(servis)"
            [ "$port_ok" = "HAYIR" ] && [ "$result" = "OK" ] && result="UYARI(port)"

            echo "| $i | Evet | $boot_ok | $svc_ok | $port_ok | $result |" >> "$SOAK_MD"
            [ "$result" != "OK" ] && [ "$boot_ok" = "HAYIR" ] && CRASH_FOUND=1
            i=$((i + 1))
        done
        ;;

    long)
        MIN="${ARG:-60}"
        chunk_min=10
        chunks=$(( (MIN + chunk_min - 1) / chunk_min ))
        echo "Toplam sure: ${MIN} dakika, ${chunks} adet ${chunk_min} dakikalik parca halinde." >> "$SOAK_MD"
        echo >> "$SOAK_MD"
        echo "| Parca | Ozet dosyasi | Janky% | CPU medyan | PSS baslangic/bitis |" >> "$SOAK_MD"
        echo "|---|---|---|---|---|" >> "$SOAK_MD"
        c=1
        while [ "$c" -le "$chunks" ]; do
            log_info "Uzun soak parcasi $c/$chunks basliyor..."
            chunk_out="$OUT/chunk-$c"
            OUT="$chunk_out" "$SCRIPT_DIR/50-perf-capture.sh" "soak-chunk-$c" $((chunk_min * 60)) || true
            janky="$(safe_grep -o 'Janky yuzde: [0-9.]*' "$chunk_out/SUMMARY.md" 2>/dev/null | tail -n1 | cut -d' ' -f3)"
            cpu="$(safe_grep -o 'CPU medyan.*: [0-9.]*' "$chunk_out/SUMMARY.md" 2>/dev/null | tail -n1 | grep -o '[0-9.]*$')"
            pssline="$(safe_grep -o 'PSS baslangic/bitis/tepe.*' "$chunk_out/SUMMARY.md" 2>/dev/null | tail -n1)"
            echo "| $c | chunk-$c/SUMMARY.md | ${janky:-NA} | ${cpu:-NA} | ${pssline:-NA} |" >> "$SOAK_MD"
            c=$((c + 1))
        done
        ;;

    *)
        die "Bilinmeyen mod: $MODE (connect-cycles|boot-cycles|long bekleniyor)"
        ;;
esac

{
    echo
    echo "Bitis: $(date '+%Y-%m-%d %H:%M:%S')"
} >> "$SOAK_MD"

log_ok "Soak test sonuclari: $SOAK_MD"

if [ "$CRASH_FOUND" -ne 0 ]; then
    log_err "Bir veya daha fazla cevrimde crash/ANR/boot hatasi tespit edildi."
    exit 1
fi
exit 0
