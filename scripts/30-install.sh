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
if [ "${1:-}" = "--from-artifact" ]; then
    dir="${2:-}"
    [ -n "$dir" ] || die "--from-artifact icin bir dizin belirtin"
    APK_PATH="$(find "$dir" -iname 'tvmirror.apk' -print 2>/dev/null | head -n1)"
    [ -n "$APK_PATH" ] || die "$dir altinda tvmirror.apk bulunamadi"
elif [ -n "${1:-}" ]; then
    APK_PATH="$1"
else
    log_info "APK yolu verilmedi, ~/Downloads altinda en yeni tvmirror.apk araniyor..."
    # Safari artifact zip'ini genelde kendisi acar; acmadiysa en yeni zip'i burada ac.
    if [ -z "$(find "$HOME/Downloads" -iname 'tvmirror.apk' -print 2>/dev/null | head -n1)" ]; then
        zip_path="$(ls -t "$HOME"/Downloads/tvmirror-*.zip 2>/dev/null | head -n1)"
        if [ -n "$zip_path" ]; then
            log_info "Zip aciliyor: $zip_path"
            unzip -o -q "$zip_path" -d "${zip_path%.zip}" || die "Zip acilamadi: $zip_path"
        fi
    fi
    APK_PATH="$(find "$HOME/Downloads" -iname 'tvmirror.apk' -print 2>/dev/null | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)"
    [ -n "$APK_PATH" ] || die "~/Downloads altinda tvmirror.apk bulunamadi, lutfen APK yolunu argument olarak verin"
fi

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

log_ok "Kurulum tamamlandi. Uygulama baslatiliyor: $PKG/$MAIN_ACTIVITY_CLASS"
adbs am start -n "$PKG/$MAIN_ACTIVITY_CLASS"

log_info "Kurulu versiyon:"
adbs dumpsys package "$PKG" | safe_grep 'versionName'
