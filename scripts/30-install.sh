#!/usr/bin/env bash
# 30-install.sh - APK'yi TV'ye kurar ve uygulamayi bir kez baslatir.
# Kullanim:
#   30-install.sh /path/to/tvmirror.apk
#   30-install.sh --from-artifact /path/to/dir   (dizin icinde tvmirror.apk arar)
#   30-install.sh                                (varsayilan: ~/Downloads altinda en yeni tvmirror.apk)
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

APK_PATH=""

# Zip, klasör veya APK yolundan kurulacak tvmirror.apk'yı bulur. Zip her seferinde yeniden
# açılır: aynı adlı eski bir klasör yeni sürümü gölgelemesin.
apk_from() {
    src="$1"
    case "$src" in
        *.zip)
            [ -f "$src" ] || die "Zip bulunamadi: $src"
            dest="${src%.zip}"
            log_info "Zip aciliyor: $src" >&2
            unzip -o -q "$src" -d "$dest" || die "Zip acilamadi: $src"
            src="$dest"
            ;;
    esac
    if [ -d "$src" ]; then
        find "$src" -iname 'tvmirror.apk' -print 2>/dev/null | head -n1
    else
        echo "$src"
    fi
}

if [ "${1:-}" = "--from-artifact" ]; then
    [ -n "${2:-}" ] || die "--from-artifact icin bir zip veya dizin belirtin"
    APK_PATH="$(apk_from "$2")"
    [ -n "$APK_PATH" ] || die "$2 altinda tvmirror.apk bulunamadi"
elif [ -n "${1:-}" ]; then
    APK_PATH="$(apk_from "$1")"
else
    # Açılmış APK'ların dosya tarihi zip'teki eski tarihi taşır; en yeni sürümü indirme
    # tarihine göre, yani en yeni zip'ten seç.
    log_info "APK yolu verilmedi, ~/Downloads altinda en yeni tvmirror-*.zip araniyor..."
    zip_path="$(ls -t "$HOME"/Downloads/tvmirror-*.zip 2>/dev/null | head -n1)"
    [ -n "$zip_path" ] || die "~/Downloads altinda tvmirror-*.zip bulunamadi; APK, zip veya klasor yolunu argument olarak verin"
    APK_PATH="$(apk_from "$zip_path")"
fi

# Artifact adı derlendiği commit'i taşır: tvmirror-<sha>
BUILD_SHA="$(echo "$APK_PATH" | grep -oE 'tvmirror-[0-9a-f]{7,40}' | head -n1 | sed 's/tvmirror-//')"

[ -f "$APK_PATH" ] || die "APK bulunamadi: $APK_PATH"
log_info "APK: $APK_PATH"

SHA_FILE="${APK_PATH}.sha256"
if [ -f "$SHA_FILE" ]; then
    log_info "sha256 dogrulaniyor..."
    expected="$(awk '{print $1}' "$SHA_FILE" | tr -d '\r\n')"
    actual="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"
    if [ "$expected" = "$actual" ]; then
        log_ok "sha256 eslesti."
    else
        die "sha256 uyusmuyor! beklenen=$expected gercek=$actual"
    fi
else
    log_warn "Yaninda .sha256 dosyasi yok, atlaniyor."
fi

need_device || exit 1

log_info "Kuruluyor: adb install -r ..."
install_out="$("$ADB" -s "$DEV" install -r "$APK_PATH" 2>&1)"
echo "$install_out"

if echo "$install_out" | grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'; then
    log_warn "Imza uyusmazligi (INSTALL_FAILED_UPDATE_INCOMPATIBLE)."
    log_warn "Once mevcut $PKG kaldirilmali (uygulama verileri silinir)."
    printf 'Uygulamayi kaldirip yeniden kurmak ister misiniz? [y/N] '
    read -r ans
    case "$ans" in
        y|Y)
            log_info "Kaldiriliyor: $PKG"
            "$ADB" -s "$DEV" uninstall "$PKG" || die "Kaldirma basarisiz"
            log_info "Yeniden kuruluyor..."
            "$ADB" -s "$DEV" install "$APK_PATH" || die "Kurulum basarisiz"
            ;;
        *)
            die "Kullanici onaylamadi, kurulum iptal edildi."
            ;;
    esac
elif ! echo "$install_out" | grep -qi 'Success'; then
    die "Kurulum basarisiz oldu, yukaridaki ciktiya bakin."
fi

# "Baglaninca uygulamayi ac" (varsayilan acik) Android 10+'da arka plandan
# ekrana gelmek icin "Diger uygulamalarin uzerinde goster" iznine ihtiyac duyar.
# Izin her kaldir-kur'da sifirlanir ve TV'lerde ayar ekrani cogu zaman yoktur;
# bu yuzden yalnizca bu uygulama icin adb ile verilir. Geri almak:
#   adb shell appops set <pkg> SYSTEM_ALERT_WINDOW default
adbs appops set "$PKG" SYSTEM_ALERT_WINDOW allow
log_ok "Ekrana otomatik gelme izni verildi: $(adbs appops get "$PKG" SYSTEM_ALERT_WINDOW | tr -d '\r')"

log_ok "Kurulum tamamlandi. Uygulama baslatiliyor: $PKG/$MAIN_ACTIVITY_CLASS"
adbs am start -n "$PKG/$MAIN_ACTIVITY_CLASS"

log_info "Kurulu versiyon:"
adbs dumpsys package "$PKG" | safe_grep 'versionName'
if [ -n "$BUILD_SHA" ]; then
    log_ok "Kurulan derleme: commit ${BUILD_SHA}"
    mkdir -p "$REPO_ROOT/out"
    printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$BUILD_SHA" "$APK_PATH" >> "$REPO_ROOT/out/installed.tsv"
fi
