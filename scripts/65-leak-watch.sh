#!/usr/bin/env bash
# 65-leak-watch.sh - Uzun sureli mirroring / cok sayida connect-disconnect
# donguleri sirasinda bellek ve kaynak sizintisi (memory/resource leak) izleme.
#
# Kullanim:
#   65-leak-watch.sh [dakika=60] [aralik_sn=60]
#
# Ornek senaryolar:
#   1) Mac/iPhone'dan 30-60 dakikalik tek bir mirroring oturumu boyunca:
#        PHASE=mac ./scripts/65-leak-watch.sh 45 60
#      (mirroring'i elle baslatip script calisirken acik tutun)
#
#   2) Cok sayida connect/disconnect dongusu ile birlikte, baska bir
#      terminalde 60-soak.sh'i PARALEL calistirin:
#        Terminal A: PHASE=cycles ./scripts/65-leak-watch.sh 60 30
#        Terminal B: ./scripts/60-soak.sh connect-cycles 20
#
#   3) Gece boyu bos (idle) durumda, uzun araliklarla:
#        PHASE=idle ./scripts/65-leak-watch.sh 480 300
#
# Cikti: $OUT/leak.tsv (ham ornekler), $OUT/LEAK.md (tools/leak_trend.py analizi),
# $OUT/media-resource-first.txt, $OUT/media-resource-last.txt (dumpsys
# media.resource_manager ham ciktisi, codec ayristirmasi ilerde
# iyilestirilebilsin diye), $OUT/crash-buffer-restart-N.txt (pid degisimi
# tespit edildiginde).
#
# Not: Tamamen salt-okunur (read-only) calisir; cihazda hicbir sey degistirmez,
# uygulama debug edilebilir olmadigi (release build) icin run-as kullanilmaz.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

MIN="${1:-60}"
INTERVAL="${2:-60}"
PHASE="${PHASE:-run}"

need_device || exit 1
setup_out_dir "leak-${PHASE}"

LEAK_TSV="$OUT/leak.tsv"
MEDIA_FIRST="$OUT/media-resource-first.txt"
MEDIA_LAST="$OUT/media-resource-last.txt"

printf 'ts\tphase\tpid\tpss_total_kb\tjava_heap_kb\tnative_heap_kb\tgraphics_kb\tthreads\tfds\tcodecs\tsf_layers\tsys_mem_available_kb\tswap_free_kb\tpswpin\tpswpout\tlmk_kills_total\tmirroring\trestart\n' > "$LEAK_TSV"

TOTAL_SECONDS=$((MIN * 60))
if [ "$TOTAL_SECONDS" -le 0 ]; then TOTAL_SECONDS=$((60 * 60)); fi
if [ "$INTERVAL" -le 0 ]; then INTERVAL=60; fi

SAMPLE_COUNT=$(( (TOTAL_SECONDS + INTERVAL - 1) / INTERVAL ))
log_info "Sizinti izleme basliyor: ${MIN} dakika, ${INTERVAL} sn araliklarla (~${SAMPLE_COUNT} ornek), faz='${PHASE}'"
log_info "Cikti: $LEAK_TSV"

PREV_PID=""
RESTART_COUNT=0
SAMPLE_NO=0

# --- SurfaceFlinger listesinden uygulamaya ait katman sayisi ve SurfaceView varligi ---
# sf_layers: 'tvmirror' ya da 'jqssun' iceren satir sayisi.
# mirroring: bu satirlar arasinda "SurfaceView" iceren en az bir satir varsa 1.
sf_layer_info() {
    sf_out="$(adbs dumpsys SurfaceFlinger --list 2>/dev/null)"
    app_lines="$(printf '%s\n' "$sf_out" | safe_grep -Ei 'tvmirror|jqssun')"
    if [ -n "$app_lines" ]; then
        sf_layers="$(printf '%s\n' "$app_lines" | safe_grep -c .)"
    else
        sf_layers=0
    fi
    if printf '%s\n' "$app_lines" | grep -qi 'surfaceview'; then
        mirroring=1
    else
        mirroring=0
    fi
}

# --- dumpsys meminfo <pid> App Summary bolumunden alan cikarma (toleransli) ---
extract_kb() {
    # $1: dumpsys meminfo ciktisi, $2: alan etiketi (orn. "Java Heap:")
    label="$2"
    printf '%s\n' "$1" | grep -oE "${label}[[:space:]]*[0-9]+" | head -n1 | grep -oE '[0-9]+$'
}

check_crash_on_restart() {
    n="$1"
    adbs logcat -d -b crash > "$OUT/crash-buffer-restart-$n.txt" 2>&1 || true
}

# Yalnizca BIZIM surecimizin LMK/am_kill ile oldurulmesi sayilir; baska
# (onbellekteki) uygulamalarin oldurulmesi 1.78 GB TV'de olagan ve sizinti
# gostergesi degil.
lmk_kill_count() {
    adbs logcat -d -b events 2>/dev/null | grep -Ei 'am_kill|lowmemorykiller' | grep -c "$PKG" || true
}

elapsed=0
while [ "$elapsed" -lt "$TOTAL_SECONDS" ]; do
    SAMPLE_NO=$((SAMPLE_NO + 1))
    ts="$(date +%s)"

    pid="$(app_pid)"
    restart=0
    if [ -n "$PREV_PID" ] && [ -n "$pid" ] && [ "$pid" != "$PREV_PID" ]; then
        restart=1
        RESTART_COUNT=$((RESTART_COUNT + 1))
        log_warn "PID degisti ($PREV_PID -> $pid): olasi restart/crash. Crash buffer kaydediliyor..."
        check_crash_on_restart "$RESTART_COUNT"
    fi
    if [ -n "$pid" ]; then
        PREV_PID="$pid"
    fi

    if [ -n "$pid" ]; then
        mem="$(adbs dumpsys meminfo "$pid" 2>/dev/null)"
        pss_total="$(extract_kb "$mem" 'TOTAL PSS:')"
        [ -n "$pss_total" ] || pss_total="$(app_pss_kb)"
        java_heap="$(extract_kb "$mem" 'Java Heap:')"
        native_heap="$(extract_kb "$mem" 'Native Heap:')"
        graphics="$(extract_kb "$mem" 'Graphics:')"

        status="$(adbs cat "/proc/$pid/status" 2>/dev/null)"
        # /proc/<pid>/status alanlari SEKME ile ayrilir ("Threads:\t30")
        threads="$(printf '%s\n' "$status" | awk '/^Threads:/{print $2; exit}')"

        fd_raw="$(adbs "ls /proc/$pid/fd 2>&1" 2>/dev/null)"
        if printf '%s\n' "$fd_raw" | grep -qi 'permission denied'; then
            fds="NA"
        else
            fds="$(printf '%s\n' "$fd_raw" | safe_grep -c '^[0-9][0-9]*$')"
        fi

        media_dump="$(adbs dumpsys media.resource_manager 2>/dev/null)"
        if [ "$SAMPLE_NO" -eq 1 ]; then
            printf '%s\n' "$media_dump" > "$MEDIA_FIRST"
        fi
        printf '%s\n' "$media_dump" > "$MEDIA_LAST"
        codecs="$(printf '%s\n' "$media_dump" | safe_grep -Ec "$pid|$PKG")"
    else
        pss_total="NA"; java_heap="NA"; native_heap="NA"; graphics="NA"
        threads="NA"; fds="NA"; codecs="NA"
        log_warn "Uygulama sureci bulunamadi (pid yok), sonraki ornekte tekrar denenecek."
    fi

    sf_layer_info

    meminfo_sys="$(adbs cat /proc/meminfo 2>/dev/null)"
    mem_avail="$(printf '%s\n' "$meminfo_sys" | safe_grep MemAvailable | tr -s ' ' | cut -d' ' -f2)"
    swap_free="$(printf '%s\n' "$meminfo_sys" | safe_grep SwapFree | tr -s ' ' | cut -d' ' -f2)"

    vmstat="$(adbs cat /proc/vmstat 2>/dev/null)"
    pswpin="$(printf '%s\n' "$vmstat" | safe_grep '^pswpin ' | cut -d' ' -f2)"
    pswpout="$(printf '%s\n' "$vmstat" | safe_grep '^pswpout ' | cut -d' ' -f2)"

    lmk_total="$(lmk_kill_count)"

    # TSV butunlugu: her alan tek bir sayi (ya da NA) olmali; sekme/\r/bosluk
    # iceren ya da sayi olmayan degerler sutunlari kaydirmasin diye NA yapilir.
    num() {
        local v; v="$(printf '%s' "$1" | tr -d '\r\t ')"
        case "$v" in ''|*[!0-9]*) echo NA ;; *) echo "$v" ;; esac
    }
    pid="$(num "${pid:-}")"; pss_total="$(num "${pss_total:-}")"; java_heap="$(num "${java_heap:-}")"
    native_heap="$(num "${native_heap:-}")"; graphics="$(num "${graphics:-}")"; threads="$(num "${threads:-}")"
    fds="$(num "${fds:-}")"; codecs="$(num "${codecs:-}")"; sf_layers="$(num "${sf_layers:-}")"
    mem_avail="$(num "${mem_avail:-}")"; swap_free="$(num "${swap_free:-}")"; pswpin="$(num "${pswpin:-}")"
    pswpout="$(num "${pswpout:-}")"; lmk_total="$(num "${lmk_total:-}")"
    [ "$pid" = "NA" ] && pid=""

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ts" "$PHASE" "${pid:-NA}" "${pss_total:-NA}" "${java_heap:-NA}" "${native_heap:-NA}" "${graphics:-NA}" \
        "${threads:-NA}" "${fds:-NA}" "${codecs:-NA}" "${sf_layers:-NA}" "${mem_avail:-NA}" "${swap_free:-NA}" \
        "${pswpin:-NA}" "${pswpout:-NA}" "${lmk_total:-NA}" "${mirroring:-NA}" "$restart" >> "$LEAK_TSV"

    log_info "[$SAMPLE_NO] pid=${pid:-NA} pss=${pss_total:-NA}KB native=${native_heap:-NA}KB graphics=${graphics:-NA}KB threads=${threads:-NA} fds=${fds:-NA} restart=$restart"

    elapsed=$((elapsed + INTERVAL))
    if [ "$elapsed" -lt "$TOTAL_SECONDS" ]; then
        sleep "$INTERVAL"
    fi
done

log_ok "Ornekleme bitti ($SAMPLE_NO ornek). Analiz calistiriliyor..."

LEAK_MD="$OUT/LEAK.md"
if command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_ROOT/tools/leak_trend.py" "$LEAK_TSV" > "$LEAK_MD" 2>"$OUT/leak_trend-stderr.txt"
    status=$?
    # cikis kodu: 0=PASS, 1=SUPHELI (ikisi de basarili bir analiz calismasidir),
    # 2 ve uzeri gercek bir hata/kullanim sorunudur.
    if [ "$status" -ge 2 ]; then
        log_err "tools/leak_trend.py basarisiz oldu (bkz. $OUT/leak_trend-stderr.txt)"
    else
        log_ok "Analiz: $LEAK_MD"
        cat "$LEAK_MD"
        [ "$status" -eq 1 ] && log_warn "Analiz supheli bulgular icermektedir, $LEAK_MD dosyasina bakin."
    fi
else
    log_err "python3 bulunamadi, analiz atlandi. Ham veri: $LEAK_TSV"
fi

exit 0
