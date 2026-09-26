#!/usr/bin/env bash
# common.sh - Tum scriptlerin ortak kullandigi yardimci fonksiyonlar.
# Bu dosya "source" edilir, dogrudan calistirilmaz.

# --- Repo kokunu script yolundan coz (herhangi bir cwd'den calisir) ---
_common_sh_path="${BASH_SOURCE[0]:-$0}"
COMMON_SH_DIR="$(cd "$(dirname "$_common_sh_path")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$COMMON_SH_DIR/../.." >/dev/null 2>&1 && pwd)"

# Sayılar her yerde nokta ondalıklı olsun (Türkçe yerelde awk/printf "32,5" üretiyor)
export LC_ALL=C

# --- Varsayilanlar (env ile override edilebilir) ---
ADB="${ADB:-/opt/homebrew/share/android-commandlinetools/platform-tools/adb}"
DEV="${DEV:-192.168.1.104:5555}"
PKG="io.github.fuzun45.tvmirror"
MAIN_ACTIVITY_CLASS="io.github.jqssun.airplay.MainActivity"
SERVICE_CLASS="io.github.jqssun.airplay.service.AirPlayService"

# adb yoksa PATH'teki adb'ye dus
if [ ! -x "$ADB" ]; then
    if command -v adb >/dev/null 2>&1; then
        ADB="$(command -v adb)"
    fi
fi

# --- Log yardimcilari ---
log_info()  { printf '[INFO] %s\n' "$*"; }
log_warn()  { printf '[WARN] %s\n' "$*" >&2; }
log_err()   { printf '[HATA] %s\n' "$*" >&2; }
log_ok()    { printf '[ OK ] %s\n' "$*"; }

die() {
    log_err "$*"
    exit 1
}

# --- Cikti dizini ---
# $OUT env'de verilmemisse out/<timestamp>-<label> olusturulur.
setup_out_dir() {
    label="${1:-run}"
    if [ -z "${OUT:-}" ]; then
        ts="$(date +%Y%m%d-%H%M%S)"
        OUT="$REPO_ROOT/out/${ts}-${label}"
    fi
    mkdir -p "$OUT"
    export OUT
    log_info "Cikti dizini: $OUT"
}

# --- ADB shell wrapper: cihazdaki gurultu satirlarini filtreler ---
# "Init wrapper", "open mma" gibi satirlari eler.
adbs() {
    "$ADB" -s "$DEV" shell "$@" 2>&1 | grep -Ev 'Init wrapper|open mma' || true
}

# Ham (filtresiz) adb shell - gerektiginde
adbs_raw() {
    "$ADB" -s "$DEV" shell "$@"
}

adbp() {
    # adb pull wrapper, basarisizsa scripti durdurmaz
    "$ADB" -s "$DEV" pull "$@" 2>&1 | grep -Ev 'Init wrapper|open mma' || true
}

# --- Cihaz baglantisini kontrol et, gerekirse connect dene ---
need_device() {
    [ -x "$ADB" ] || [ -n "$(command -v "$ADB" 2>/dev/null)" ] || die "adb bulunamadi: $ADB (ADB env degiskenini kontrol edin)"

    state="$("$ADB" devices 2>/dev/null | awk -v d="$DEV" '$1==d {print $2}')"
    if [ "$state" = "device" ]; then
        return 0
    fi

    log_warn "Cihaz ($DEV) bagli degil, 'adb connect' deneniyor..."
    "$ADB" connect "$DEV" >/dev/null 2>&1 || true
    sleep 1

    state="$("$ADB" devices 2>/dev/null | awk -v d="$DEV" '$1==d {print $2}')"
    if [ "$state" = "device" ]; then
        log_ok "Cihaza baglanildi: $DEV"
        return 0
    fi

    log_err "Cihaza baglanilamadi: $DEV (durum: '${state:-yok}')"
    log_err "Ipucu: TV'de Ayarlar > Cihaz Tercihleri > Gelistirici secenekleri > Ag/USB hata ayiklama acik olmali,"
    log_err "      ve TV ekraninda cikan RSA parmak izi onay kutusunu kabul etmelisiniz."
    return 1
}

# grep bulunamadiginda scripti durdurmasin diye kucuk yardimci
safe_grep() {
    grep "$@" || true
}

# --- Uygulama süreci ölçümleri (PID üzerinden) ---
# top uzun paket adlarını kırptığı için isimle grep güvenilir değil; PID kullanılıyor.
app_pid() {
    adbs pidof "$PKG" | tr -d '\r' | awk '{print $1}'
}

# Toplam PSS (KB). Android 14: "TOTAL PSS:   52341   TOTAL RSS: ...";
# eski sürümler: "TOTAL   52341 ..." satırı.
app_pss_kb() {
    pid="$(app_pid)"
    [ -n "$pid" ] || return 0
    adbs dumpsys meminfo "$pid" | awk '
        /TOTAL PSS:/ { for (i = 1; i <= NF; i++) if ($i == "PSS:") { print $(i + 1); exit } }
        /^ *TOTAL +[0-9]/ { print $2; exit }'
}

# Tek bir top örneğinde uygulamanın %CPU değeri (tek çekirdek = 100).
# toybox top başlığında "S[%CPU]" birleşik yazılır; veri satırında S ve %CPU ayrı alanlardır.
app_cpu() {
    pid="$(app_pid)"
    [ -n "$pid" ] || return 0
    adbs top -b -n 1 -p "$pid" | awk -v pid="$pid" '
        /PID/ && /CPU/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "S[%CPU]") { col = i + 1; break }
                if ($i ~ /%CPU/)     { col = i;     break }
            }
            next
        }
        col && $1 == pid { print $col; exit }'
}

# Anlık Wi-Fi RSSI ve link hızı (yalnızca mWifiInfo satırından).
wifi_now() {
    adbs dumpsys wifi | awk -F', ' '/mWifiInfo SSID/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^(RSSI|Link speed):/) printf "%s ", $i
        print ""; exit }'
}
