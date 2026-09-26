#!/usr/bin/env bash
# 60-soak.sh - Yari-manuel dayaniklilik (soak) testleri.
# Kullanim:
#   60-soak.sh connect-cycles N          (elle: her adimda Enter)
#   AUTO=1 60-soak.sh connect-cycles N   (Mac: scripts/mac-mirror.sh ile otomatik; HOLD_SEC=15 AUTO_GAP_SEC=5)
#   60-soak.sh boot-cycles N
#   60-soak.sh long <dakika>
# Not: Bellek/kaynak sizintisi icin bu scripti 65-leak-watch.sh ile paralel
# calistirabilirsiniz (bkz. scripts/65-leak-watch.sh basindaki kullanim notlari).
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

# Crash tamponu acilistan beri birikir: test oncesi eski kayitlar (or. onceki
# APK'lar) her cevrimde yeniden sayilmasin diye yalnizca baslangica gore YENI
# kayitlar sayilir, ve yalnizca bizim surecimize ait olanlar ("Process: <pkg>"
# ya da "ANR in <pkg>"); baska uygulamanin cokmesi FAIL uretmez.
PKG_RE="$(printf '%s' "$PKG" | sed 's/\./\\./g')"
OUR_CRASH_RE="(Process: |ANR in )${PKG_RE}([^A-Za-z0-9_.]|$)"
our_crash_count() {
    grep -cE "$OUR_CRASH_RE" "$1" 2>/dev/null || true
}
adbs logcat -d -b crash > "$OUT/crash-buffer-baseline.txt" 2>&1 || true
CRASH_BASE="$(our_crash_count "$OUT/crash-buffer-baseline.txt")"
CRASH_BASE="${CRASH_BASE:-0}"

check_crash() {
    adbs logcat -d -b crash > "$OUT/crash-buffer-$1.txt" 2>&1 || true
    local n
    n="$(our_crash_count "$OUT/crash-buffer-$1.txt")"
    [ "${n:-0}" -le "$CRASH_BASE" ]
}

# AUTO=1: Mac'te yansitmayi scripts/mac-mirror.sh ile otomatik baslat/durdur.
# HOLD_SEC: her cevrimde yansitma acik kalma suresi; AUTO_GAP_SEC: cevrimler
# arasi bekleme (macOS'un cihazi yeniden kesfetmesi icin).
AUTO="${AUTO:-0}"
HOLD_SEC="${HOLD_SEC:-15}"
AUTO_GAP_SEC="${AUTO_GAP_SEC:-5}"
AIRPLAY_NAME="${AIRPLAY_NAME:-Salon TV}"
MAC_LOG="$OUT/mac-mirror.log"

# wait_layer present|absent SANIYE: katman gorunene / kaybolana kadar bekler,
# gecen saniyeyi yazar; sure dolarsa "-" yazar ve 1 doner.
wait_layer() {
    local want="$1" t=0
    while [ "$t" -lt "$2" ]; do
        if [ -n "$(app_surfaceview_layer)" ]; then
            [ "$want" = "present" ] && { echo "$t"; return 0; }
        else
            [ "$want" = "absent" ] && { echo "$t"; return 0; }
        fi
        sleep 1; t=$((t + 1))
    done
    echo "-"; return 1
}

# mac_mirror start|stop: mac-mirror.sh'i calistirir, ciktiyi zaman damgasiyla
# MAC_LOG'a yazar, cikis kodunu dondurur.
mac_mirror() {
    local out rc
    out="$("$SCRIPT_DIR/mac-mirror.sh" "$1" "$AIRPLAY_NAME" 2>&1)"; rc=$?
    printf '%s cevrim=%s %s rc=%s %s\n' "$(date '+%H:%M:%S')" "$i" "$1" "$rc" "$out" >> "$MAC_LOG"
    [ "$rc" -eq 0 ] || log_warn "mac-mirror $1 hata verdi: $out"
    return "$rc"
}

# Alicinin olaylari: logcat temizlenmez; verilen cihaz saatinden (epoch sn)
# sonrasi okunur. Epoch bicimi bosluk icermez; "MM-DD hh:mm:ss" adb shell'de
# iki argumana bolunup filtre sanildigi icin hic satir dondurmuyordu.
dev_now() { adbs date +%s | tr -dc '0-9'; }
log_since() { adbs logcat -d -T "${1}.000" 2>/dev/null; }
count_in() { printf '%s\n' "$1" | grep -c "$2" || true; }
cycle_events() {
    local log
    log="$(log_since "$1")"
    printf 'conn=%s disc=%s codec=%s' \
        "$(count_in "$log" 'Client connected')" \
        "$(count_in "$log" 'Client disconnected')" \
        "$(count_in "$log" 'Video codec started')"
}
ev_get() { printf '%s\n' "$1" | sed -n "s/.*$2=\([0-9]*\).*/\1/p"; }

case "$MODE" in
    connect-cycles)
        N="${ARG:-1}"
        if [ "$AUTO" = "1" ]; then
            echo "Mod: otomatik. Gercek durum TV'den okunur (video katmani + alici logu); Mac'e mac-mirror.sh click ile tiklanir. HOLD_SEC=$HOLD_SEC AUTO_GAP_SEC=$AUTO_GAP_SEC" >> "$SOAK_MD"
            echo >> "$SOAK_MD"
        fi
        echo "| # | Baslat | Katman (sn) | Durdur | Kaybolma (sn) | Alici olaylari | ANR/FATAL yok | Surec canli | PSS(KB) | Sonuc |" >> "$SOAK_MD"
        echo "|---|---|---|---|---|---|---|---|---|---|" >> "$SOAK_MD"
        i=1
        while [ "$i" -le "$N" ]; do
            printf '\n--- Cevrim %d/%d ---\n' "$i" "$N"
            t0="$(dev_now)"
            start_st="elle"; stop_st="elle"
            if [ "$AUTO" = "1" ]; then
                if [ -n "$(app_surfaceview_layer)" ]; then
                    start_st="zaten-acik"; t_up=0
                else
                    mac_mirror click; start_st="tik"
                    t_up="$(wait_layer present 25)"
                    if [ "$t_up" = "-" ]; then
                        log_warn "Katman gelmedi, Mac'e bir kez daha tiklaniyor"
                        mac_mirror click; start_st="tik x2"
                        t_up="$(wait_layer present 25)"
                    fi
                fi
            else
                printf 'Iphone/Mac uzerinden mirroring BASLATIN, sonra Enter tusuna basin...\n'
                read -r _
                t_up="$(wait_layer present 5)"
            fi
            [ "$t_up" != "-" ] \
                && log_ok "SurfaceView katmani goruldu (${t_up} sn)" \
                || log_warn "SurfaceView katmani bulunamadi (yine de devam ediliyor)"

            t1="$(dev_now)"
            if [ "$AUTO" = "1" ]; then
                sleep "$HOLD_SEC"
                t1="$(dev_now)"
                mac_mirror click; stop_st="tik"
                t_down="$(wait_layer absent 10)"
                if [ "$t_down" = "-" ]; then
                    # Alici kopmayi gormediyse Mac birakmamistir: bir kez daha tikla.
                    # Gorduyse ikinci tik yansitmayi yeniden baslatir; tiklanmaz.
                    if [ "$(ev_get "$(cycle_events "$t1")" disc)" = "0" ]; then
                        log_warn "Alici kopma gormedi, Mac'e bir kez daha tiklaniyor"
                        mac_mirror click; stop_st="tik x2"
                        t_down="$(wait_layer absent 10)"
                    fi
                fi
            else
                printf 'Simdi mirroring DURDURUN, sonra Enter tusuna basin...\n'
                read -r _
                t_down="$(wait_layer absent 10)"
            fi
            sleep 2
            events="$(cycle_events "$t0")"
            stop_events="$(cycle_events "$t1")"

            no_crash="EVET"; check_crash "cycle$i" || { no_crash="HAYIR"; CRASH_FOUND=1; }
            proc_alive="EVET"; [ -n "$(app_pid)" ] || proc_alive="HAYIR"
            pss="$(app_pss_kb)"

            layer_after="$(app_surfaceview_layer)"
            printf '%s\t%s\t%s\t%s\n' "$i" "${layer_after:-}" "$events" "stop:$stop_events" >> "$OUT/after-stop.tsv"

            # Siniflandirma: gonderici (Mac/script) sorunlari ayrilir; uygulama
            # bulgusu yalnizca alicinin olaylari bunu gosterdiginde sayilir.
            result="OK"
            if [ "$t_up" = "-" ]; then
                if [ "$(ev_get "$events" conn)" = "0" ]; then
                    result="MAC-START-FAIL"
                elif [ "$(ev_get "$events" codec)" = "0" ]; then
                    result="FAIL(baslamadi)"
                else
                    result="FAIL(katman-yok)"
                fi
            elif [ -n "$layer_after" ]; then
                if [ "$(ev_get "$stop_events" disc)" = "0" ]; then
                    result="MAC-STOP-FAIL"
                else
                    result="UYARI(stale-layer)"
                fi
            fi
            [ "$no_crash" = "HAYIR" ] && result="FAIL(crash)"
            [ "$proc_alive" = "HAYIR" ] && result="FAIL(surec)"

            echo "| $i | $start_st | $t_up | $stop_st | $t_down | $events | $no_crash | $proc_alive | ${pss:-NA} | $result |" >> "$SOAK_MD"
            i=$((i + 1))
            [ "$AUTO" = "1" ] && sleep "$AUTO_GAP_SEC"
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
            adbs dumpsys activity services "$PKG" | grep -q "$SERVICE_CLASS" && svc_ok="EVET"

            port_ok="HAYIR"
            if adbs_raw 'command -v ss >/dev/null 2>&1'; then
                adbs ss -ltn | grep -qE ':7000\b' && port_ok="EVET"
            fi
            if [ "$port_ok" = "HAYIR" ]; then
                adbs cat /proc/net/tcp 2>/dev/null | grep -qi ':1B58 ' && port_ok="EVET"
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
