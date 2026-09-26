#!/usr/bin/env bash
# 70-capture-issue.sh - Yansitma baslamiyorken salt-okunur teshis yakalama.
# Kullanim: 70-capture-issue.sh <etiket>
#
# Amac: TV uygulamasinda cozunurluk ayari degistirildikten sonra AirPlay
# sunucusu yeniden baslatiliyor; bazen Mac/iPhone'dan yansitma bir daha
# baslamiyor. Bu script hicbir sey degistirmez, sadece durumu kaydeder.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

LABEL="${1:-}"
[ -n "$LABEL" ] || die "Kullanim: $0 <etiket>"

AIRPLAY_NAME="${AIRPLAY_NAME:-Salon TV}"

need_device || exit 1
setup_out_dir "issue-${LABEL}"

DNSSD_BIN="$(command -v dns-sd 2>/dev/null || true)"

# --- Yardimci: surec bilgisi (PID + baslangic zamani) ---
get_proc_info() {
    pid="$1"
    if [ -z "$pid" ]; then
        printf 'PID yok (surec calismiyor)\n'
        return
    fi
    info="$(adbs ps -A -o PID,STIME,ELAPSED,NAME 2>/dev/null | safe_grep -E "^[[:space:]]*${pid}[[:space:]]")"
    if [ -z "$info" ]; then
        info="$(adbs ps -A 2>/dev/null | safe_grep -E "[[:space:]]${pid}[[:space:]]")"
    fi
    if [ -z "$info" ]; then
        printf 'PID %s icin surec satiri bulunamadi\n' "$pid"
    else
        printf '%s\n' "$info"
    fi
}

# --- Yardimci: port 7000 dinleniyor mu ---
check_port_7000() {
    port_hex="1B58"  # 7000 decimal -> hex
    if adbs_raw 'command -v ss >/dev/null 2>&1'; then
        if adbs ss -ltn | safe_grep -qE ':7000\b'; then
            printf 'dinleniyor (ss)\n'
            return
        fi
    fi
    if adbs_raw 'command -v netstat >/dev/null 2>&1'; then
        if adbs netstat -ltn | safe_grep -qE ':7000\b'; then
            printf 'dinleniyor (netstat)\n'
            return
        fi
    fi
    if adbs cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | safe_grep -qi ":${port_hex} "; then
        printf 'dinleniyor (/proc/net/tcp)\n'
        return
    fi
    printf 'dinlenmiyor\n'
}

# --- Yardimci: dns-sd komutunu 5sn calistirip oldur (macOS'ta 'timeout' yok) ---
dnssd_timed() {
    out_file="$1"
    shift
    "$DNSSD_BIN" "$@" > "$out_file" 2>&1 &
    dpid=$!
    sleep 5
    kill "$dpid" 2>/dev/null || true
    wait "$dpid" 2>/dev/null || true
}

# --- Yardimci: dns-sd -B ciktisindan "Add" satirlarindaki instance adini coz ---
# $1 = dosya, $2 = disari birakilacak isim (bos olabilir)
parse_browse_name() {
    file="$1"
    excl="${2:-}"
    awk -v excl="$excl" '
        $1 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ && $2 == "Add" {
            name = ""
            for (i = 6; i <= NF; i++) { name = name (name == "" ? "" : " ") $i }
            if (name != "" && name != excl) { print name; exit }
        }
    ' "$file" 2>/dev/null
}

# --- Yardimci: dns-sd -B _raop._tcp ciktisindan "@<isim>" iceren instance adini coz ---
parse_raop_name() {
    file="$1"
    suf="$2"
    awk -v suf="$suf" '
        $1 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ && $2 == "Add" {
            name = ""
            for (i = 6; i <= NF; i++) { name = name (name == "" ? "" : " ") $i }
            if (index(name, suf) > 0) { print name; exit }
        }
    ' "$file" 2>/dev/null
}

################################################################################
# 1) ONCESI kayitlari
################################################################################
log_info "Onceki durum kaydediliyor..."

PID_BEFORE="$(app_pid)"
PROC_BEFORE="$(get_proc_info "$PID_BEFORE")"
printf '%s\n' "$PROC_BEFORE" > "$OUT/proc-before.txt"

adbs dumpsys activity services "$PKG" > "$OUT/dumpsys-services-before.txt"

PORT_BEFORE="$(check_port_7000)"
printf '%s\n' "$PORT_BEFORE" > "$OUT/port-7000-before.txt"

AIRPLAY_BROWSE="$OUT/dnssd-airplay-browse.txt"
AIRPLAY_RESOLVE="$OUT/dnssd-airplay-resolve.txt"
RAOP_BROWSE="$OUT/dnssd-raop-browse.txt"
RAOP_RESOLVE="$OUT/dnssd-raop-resolve.txt"
: > "$AIRPLAY_BROWSE"
: > "$AIRPLAY_RESOLVE"
: > "$RAOP_BROWSE"
: > "$RAOP_RESOLVE"

RESOLVED_AIRPLAY_NAME=""
RESOLVED_RAOP_NAME=""

if [ -n "$DNSSD_BIN" ]; then
    OWN_NAME="$(scutil --get ComputerName 2>/dev/null || true)"

    log_info "mDNS _airplay._tcp taraniyor (5sn)..."
    dnssd_timed "$AIRPLAY_BROWSE" -B _airplay._tcp local.

    RESOLVED_AIRPLAY_NAME="$(parse_browse_name "$AIRPLAY_BROWSE" "$OWN_NAME")"
    [ -n "$RESOLVED_AIRPLAY_NAME" ] || RESOLVED_AIRPLAY_NAME="$AIRPLAY_NAME"

    log_info "mDNS _airplay._tcp cozumleniyor: \"$RESOLVED_AIRPLAY_NAME\" (5sn)..."
    dnssd_timed "$AIRPLAY_RESOLVE" -L "$RESOLVED_AIRPLAY_NAME" _airplay._tcp local.

    log_info "mDNS _raop._tcp taraniyor (5sn)..."
    dnssd_timed "$RAOP_BROWSE" -B _raop._tcp local.

    RESOLVED_RAOP_NAME="$(parse_raop_name "$RAOP_BROWSE" "@${RESOLVED_AIRPLAY_NAME}")"

    if [ -n "$RESOLVED_RAOP_NAME" ]; then
        log_info "mDNS _raop._tcp cozumleniyor: \"$RESOLVED_RAOP_NAME\" (5sn)..."
        dnssd_timed "$RAOP_RESOLVE" -L "$RESOLVED_RAOP_NAME" _raop._tcp local.
    else
        log_warn "_raop._tcp icin \"@${RESOLVED_AIRPLAY_NAME}\" ile eslesen instance bulunamadi."
    fi
else
    log_warn "dns-sd komutu bulunamadi (bu script Mac'te calistirilmali), mDNS adimlari atlaniyor."
fi

################################################################################
# 2) Kullanicidan deneme bilgisi al
################################################################################
adbs logcat -c

echo
echo "Simdi yansitmayi baslatmayi deneyin (Mac veya iPhone). Denemeniz bittiginde (basarili ya da basarisiz) Enter'a basin."
read -r _

printf 'Hangi cihazdan denediniz (Mac / iPhone / ikisi de)? '
read -r TRIED_DEVICE
printf 'Sonuc nasildi (basarili / basarisiz / aciklama yazabilirsiniz)? '
read -r TRIED_RESULT

################################################################################
# 3) SONRASI kayitlari
################################################################################
log_info "Sonraki durum kaydediliyor..."

adbs logcat -d -v threadtime > "$OUT/logcat-full.txt"
adbs logcat -d -b crash > "$OUT/crash.txt"

FILTER_PATTERN='AirPlayService|raop|UxPlay|airplay|jqssun|tvmirror|NsdService|NsdManager|mDNS|AndroidRuntime|FATAL|ANR in|DecoderSelector|MediaCodec|TvMirrorStats|pair|fairplay|rtsp|SETUP|RECORD|TEARDOWN'
safe_grep -iE "$FILTER_PATTERN" "$OUT/logcat-full.txt" | tail -n 400 > "$OUT/filtered.txt"

PID_AFTER="$(app_pid)"
PROC_AFTER="$(get_proc_info "$PID_AFTER")"
printf '%s\n' "$PROC_AFTER" > "$OUT/proc-after.txt"

RESTART_FLAG=""
if [ -z "$PID_AFTER" ]; then
    RESTART_FLAG="SUREC YENIDEN BASLAMIS (surec artik calismiyor)"
elif [ -n "$PID_BEFORE" ] && [ "$PID_BEFORE" != "$PID_AFTER" ]; then
    RESTART_FLAG="SUREC YENIDEN BASLAMIS (PID $PID_BEFORE -> $PID_AFTER)"
else
    RESTART_FLAG="Surec ayni (PID degismedi: ${PID_AFTER:-yok})"
fi
log_info "$RESTART_FLAG"

################################################################################
# 4) ISSUE.md yaz
################################################################################
ISSUE_MD="$OUT/ISSUE.md"
{
    echo "# Yansitma Sorunu Yakalama - $LABEL"
    echo
    echo "- Tarih: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Kullanici: ${USER:-bilinmiyor}"
    echo "- Denenen cihaz: ${TRIED_DEVICE:-belirtilmedi}"
    echo "- Sonuc (kullanici beyani): ${TRIED_RESULT:-belirtilmedi}"
    echo "- Cikti dizini: $OUT"
    echo
    echo "## Surec (PID) Durumu"
    echo
    echo "\`\`\`"
    echo "-- Once --"
    echo "$PROC_BEFORE"
    echo
    echo "-- Sonra --"
    echo "$PROC_AFTER"
    echo "\`\`\`"
    echo
    echo "- **$RESTART_FLAG**"
    echo
    echo "## Port 7000 (Once)"
    echo
    echo "\`\`\`"
    echo "$PORT_BEFORE"
    echo "\`\`\`"
    echo
    echo "## mDNS - _airplay._tcp"
    echo
    echo "- Kullanilan/cozulen isim: ${RESOLVED_AIRPLAY_NAME:-bulunamadi}"
    echo
    echo "### Browse (dns-sd -B _airplay._tcp local.)"
    echo "\`\`\`"
    if [ -s "$AIRPLAY_BROWSE" ]; then cat "$AIRPLAY_BROWSE"; else echo "(cikti yok)"; fi
    echo "\`\`\`"
    echo
    echo "### TXT / Resolve (dns-sd -L \"$RESOLVED_AIRPLAY_NAME\" _airplay._tcp local.)"
    echo "\`\`\`"
    if [ -s "$AIRPLAY_RESOLVE" ]; then cat "$AIRPLAY_RESOLVE"; else echo "(cikti yok)"; fi
    echo "\`\`\`"
    echo
    echo "## mDNS - _raop._tcp"
    echo
    echo "- Kullanilan/cozulen isim: ${RESOLVED_RAOP_NAME:-bulunamadi}"
    echo
    echo "### Browse (dns-sd -B _raop._tcp local.)"
    echo "\`\`\`"
    if [ -s "$RAOP_BROWSE" ]; then cat "$RAOP_BROWSE"; else echo "(cikti yok)"; fi
    echo "\`\`\`"
    echo
    echo "### TXT / Resolve (dns-sd -L \"$RESOLVED_RAOP_NAME\" _raop._tcp local.)"
    echo "\`\`\`"
    if [ -s "$RAOP_RESOLVE" ]; then cat "$RAOP_RESOLVE"; else echo "(cikti yok)"; fi
    echo "\`\`\`"
    echo
    echo "## Crash Buffer"
    echo
    echo "\`\`\`"
    if [ -s "$OUT/crash.txt" ]; then cat "$OUT/crash.txt"; else echo "yok"; fi
    echo "\`\`\`"
    echo
    echo "## Filtrelenmis Logcat (son 150 satir, filtered.txt icinde son 400)"
    echo
    echo "\`\`\`"
    tail -n 150 "$OUT/filtered.txt"
    echo "\`\`\`"
} > "$ISSUE_MD"

log_ok "Yakalama tamamlandi."
echo
echo "Rapor: $ISSUE_MD"
echo "Lutfen bu dosyayi (ISSUE.md) paylasin."
