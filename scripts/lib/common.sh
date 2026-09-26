#!/usr/bin/env bash
# common.sh - Tum scriptlerin ortak kullandigi yardimci fonksiyonlar.
# Bu dosya "source" edilir, dogrudan calistirilmaz.

# --- Repo kokunu script yolundan coz (herhangi bir cwd'den calisir) ---
_common_sh_path="${BASH_SOURCE[0]:-$0}"
COMMON_SH_DIR="$(cd "$(dirname "$_common_sh_path")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$COMMON_SH_DIR/../.." >/dev/null 2>&1 && pwd)"

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
