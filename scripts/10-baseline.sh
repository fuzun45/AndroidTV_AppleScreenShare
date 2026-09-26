#!/usr/bin/env bash
# 10-baseline.sh - SADECE OKUMA yapar, cihazda hicbir sey degistirmez.
# TV'nin mevcut durumunu toplu halde $OUT altina kaydeder ve
# $OUT/BASELINE-SUMMARY.md insan-okunur ozetini uretir.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

need_device || exit 1
setup_out_dir "baseline"

SUMMARY="$OUT/BASELINE-SUMMARY.md"
{
    echo "# Baseline Ozeti"
    echo
    echo "- Tarih: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Cihaz: $DEV"
    echo
} > "$SUMMARY"

section() {
    printf '\n## %s\n\n' "$1" >> "$SUMMARY"
}

log_info "getprop toplaniyor..."
adbs getprop > "$OUT/getprop-full.txt"
{
    echo '```'
    adbs getprop | safe_grep -E 'ro\.(product|build)\.|ro\.board\.platform|persist\.sys\.|dalvik\.vm\.heapsize'
    echo '```'
} > "$OUT/getprop-key.txt"
section "Kilit getprop degerleri"
cat "$OUT/getprop-key.txt" >> "$SUMMARY"

log_info "Bellek bilgisi (/proc/meminfo, dumpsys meminfo, swap)..."
adbs cat /proc/meminfo > "$OUT/meminfo.txt"
adbs dumpsys meminfo > "$OUT/dumpsys-meminfo-full.txt"
adbs dumpsys meminfo | safe_grep -A5 -iE '^Total (RAM|PSS)|Free RAM|Used RAM' > "$OUT/meminfo-summary.txt"
adbs cat /proc/vmstat | safe_grep -E 'pswpin|pswpout' > "$OUT/swap-vmstat.txt"
section "Bellek / Swap Ozeti"
{
    echo '```'
    cat "$OUT/meminfo-summary.txt"
    echo
    echo "-- swap (pswpin/pswpout) --"
    cat "$OUT/swap-vmstat.txt"
    echo '```'
} >> "$SUMMARY"

log_info "Disk kullanimi (df -h)..."
adbs df -h > "$OUT/df-h.txt"

log_info "Paket listeleri..."
adbs pm list packages -f > "$OUT/pm-packages-all.txt"
adbs pm list packages -d > "$OUT/pm-packages-disabled.txt"
adbs pm list packages -3 > "$OUT/pm-packages-3rdparty.txt"

log_info "Calisan surecler (ps -A, dumpsys activity processes)..."
adbs ps -A > "$OUT/ps-A.txt"
adbs dumpsys activity processes > "$OUT/dumpsys-activity-processes.txt"
safe_grep -m 40 -A1 -iE 'proc |top activity|adj' "$OUT/dumpsys-activity-processes.txt" > "$OUT/dumpsys-activity-processes-top.txt"

log_info "Mevcut HOME uygulamasi..."
adbs cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
    > "$OUT/current-home.txt"
section "Mevcut HOME (launcher)"
{
    echo '```'
    cat "$OUT/current-home.txt"
    echo '```'
} >> "$SUMMARY"

log_info "Ekran boyutu / yogunlugu / display bilgisi..."
adbs wm size > "$OUT/wm-size.txt"
adbs wm density > "$OUT/wm-density.txt"
adbs dumpsys display > "$OUT/dumpsys-display-full.txt"
safe_grep -iE 'mode|fps|HdrCapabilities|supportedModes' "$OUT/dumpsys-display-full.txt" > "$OUT/dumpsys-display-modes.txt"
section "Ekran"
{
    echo '```'
    echo "wm size:"; cat "$OUT/wm-size.txt"
    echo "wm density:"; cat "$OUT/wm-density.txt"
    echo
    echo "Desteklenen modlar / fps / HDR (ilk 40 satir):"
    head -n 40 "$OUT/dumpsys-display-modes.txt"
    echo '```'
} >> "$SUMMARY"

log_info "Medya codec XML'leri cekiliyor (bazilari okunamayabilir, sorun degil)..."
mkdir -p "$OUT/codecs"
for f in /vendor/etc/media_codecs.xml /vendor/etc/media_codecs_performance.xml \
         /system/etc/media_codecs.xml /system/etc/media_codecs_google_video.xml \
         /odm/etc/media_codecs.xml; do
    adbp "$f" "$OUT/codecs/" >/dev/null 2>&1 || true
done
# Genis tarama: /vendor/etc ve /system/etc altinda media_codecs* pattern'i
adbs "ls /vendor/etc/media_codecs*.xml /system/etc/media_codecs*.xml /odm/etc/media_codecs*.xml 2>/dev/null" \
    > "$OUT/codecs/found-files.txt"
while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    adbp "$cf" "$OUT/codecs/" >/dev/null 2>&1 || true
done < "$OUT/codecs/found-files.txt"

codec_grep="$OUT/codecs/avc-hevc-grep.txt"
: > "$codec_grep"
for xf in "$OUT"/codecs/*.xml; do
    [ -e "$xf" ] || continue
    {
        echo "== $xf =="
        safe_grep -iE 'avc|hevc|h264|h265|size=|measured-frame-rate|performance-point|low-latency' "$xf"
    } >> "$codec_grep"
done
section "Medya Codec Ozeti (AVC/HEVC, performans noktalari, low-latency)"
{
    echo '```'
    if [ -s "$codec_grep" ]; then
        head -n 80 "$codec_grep"
    else
        echo "(codec XML dosyalarina erisilemedi veya bulunamadi)"
    fi
    echo '```'
} >> "$SUMMARY"

log_info "Wi-Fi durumu (dumpsys wifi)..."
adbs dumpsys wifi > "$OUT/dumpsys-wifi-full.txt"
safe_grep -iE 'frequency|rssi|link speed|linkspeed|is5ghzbandsupported|mis5ghzbandsupported|supported band' \
    "$OUT/dumpsys-wifi-full.txt" > "$OUT/wifi-summary.txt"
section "Wi-Fi Ozeti"
{
    echo '```'
    cat "$OUT/wifi-summary.txt"
    echo '```'
} >> "$SUMMARY"

log_info "IP adresleri..."
adbs ip -4 addr show wlan0 > "$OUT/ip-wlan0.txt" 2>&1 || true
adbs ip -4 addr show eth0 > "$OUT/ip-eth0.txt" 2>&1 || true
section "IP Adresleri"
{
    echo '```'
    echo "wlan0:"; cat "$OUT/ip-wlan0.txt"
    echo "eth0:"; cat "$OUT/ip-eth0.txt"
    echo '```'
} >> "$SUMMARY"

log_info "Mac'ten TV'ye ping jitter olcumu (50 paket)..."
tv_ip="${DEV%%:*}"
ping_out="$OUT/ping-jitter.txt"
if command -v ping >/dev/null 2>&1; then
    ping -c 50 -i 0.2 "$tv_ip" > "$ping_out" 2>&1 || true
else
    echo "ping komutu bulunamadi" > "$ping_out"
fi
section "Ping Jitter (Mac -> TV, $tv_ip)"
{
    echo '```'
    tail -n 6 "$ping_out"
    echo '```'
} >> "$SUMMARY"

log_info "Dinleyen portlar (ss/netstat)..."
if adbs_raw 'command -v ss >/dev/null 2>&1'; then
    adbs ss -ltnu > "$OUT/listening-ports.txt" 2>&1
elif adbs_raw 'command -v netstat >/dev/null 2>&1'; then
    adbs netstat -ltnu > "$OUT/listening-ports.txt" 2>&1
else
    echo "ss ve netstat bulunamadi, /proc/net/tcp kullaniliyor" > "$OUT/listening-ports.txt"
    adbs cat /proc/net/tcp >> "$OUT/listening-ports.txt" 2>&1
fi
section "Dinleyen Portlar"
{
    echo '```'
    cat "$OUT/listening-ports.txt"
    echo '```'
} >> "$SUMMARY"

log_info "Mac uzerinden mDNS taramasi (_airplay._tcp, ~5sn)..."
dnssd_out="$OUT/dns-sd-airplay.txt"
if command -v dns-sd >/dev/null 2>&1; then
    ( dns-sd -B _airplay._tcp local. > "$dnssd_out" 2>&1 & echo $! > "$OUT/.dnssd.pid" )
    sleep 5
    if [ -f "$OUT/.dnssd.pid" ]; then
        kill "$(cat "$OUT/.dnssd.pid")" 2>/dev/null || true
        rm -f "$OUT/.dnssd.pid"
    fi
else
    echo "dns-sd komutu bulunamadi (bu Mac'te calistirilmali)" > "$dnssd_out"
fi
section "mDNS: _airplay._tcp taramasi (TV zaten native AirPlay yayinliyor mu?)"
{
    echo '```'
    cat "$dnssd_out"
    echo '```'
} >> "$SUMMARY"

log_info "SurfaceFlinger HWC katmanlari (idle UI) ve missed frame sayaci..."
adbs dumpsys SurfaceFlinger > "$OUT/surfaceflinger-full.txt"
safe_grep -A 60 -iE 'HWC layers|Display 0' "$OUT/surfaceflinger-full.txt" > "$OUT/surfaceflinger-hwc-layers.txt"
safe_grep -i 'missed' "$OUT/surfaceflinger-full.txt" > "$OUT/surfaceflinger-missed.txt"
section "SurfaceFlinger HWC Katmanlari (idle UI)"
{
    echo '```'
    head -n 60 "$OUT/surfaceflinger-hwc-layers.txt"
    echo
    echo "-- HWC missed frame count --"
    cat "$OUT/surfaceflinger-missed.txt"
    echo '```'
} >> "$SUMMARY"

log_info "Ilgili paketler taraniyor (hue|ambilight|mediatek|vestel|netflix|youtube|cast|assistant|launcher)..."
safe_grep -iE 'hue|ambilight|mediatek|vestel|netflix|youtube|cast|assistant|launcher' "$OUT/pm-packages-all.txt" \
    > "$OUT/pm-packages-of-interest.txt"
section "Ilgi Cekici Paketler"
{
    echo '```'
    if [ -s "$OUT/pm-packages-of-interest.txt" ]; then
        cat "$OUT/pm-packages-of-interest.txt"
    else
        echo "(eslesme bulunamadi)"
    fi
    echo '```'
} >> "$SUMMARY"

section "Ham Dosyalar"
{
    echo "Tum ham ciktilar: $OUT"
    echo
    echo "Bu script cihazda HICBIR SEYI DEGISTIRMEZ (salt okunur)."
} >> "$SUMMARY"

log_ok "Baseline toplama tamamlandi."
log_ok "Ozet: $SUMMARY"
