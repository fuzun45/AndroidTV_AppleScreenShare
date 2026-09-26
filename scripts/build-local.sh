#!/usr/bin/env bash
# build-local.sh - Mac'te lokal APK build fallback'i.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

DEFAULT_JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
DEFAULT_SDK_DIR="/opt/homebrew/share/android-commandlinetools"
NDK_VERSION="27.0.12077973"

export JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"
[ -d "$JAVA_HOME" ] || log_warn "JAVA_HOME bulunamadi: $JAVA_HOME (build yine de denenecek)"

export ANDROID_HOME="${ANDROID_HOME:-$DEFAULT_SDK_DIR}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
[ -d "$ANDROID_HOME" ] || log_warn "ANDROID_HOME bulunamadi: $ANDROID_HOME"

export PATH="$JAVA_HOME/bin:$PATH"

RECEIVER_DIR="$REPO_ROOT/receiver"
[ -d "$RECEIVER_DIR" ] || die "receiver/ dizini bulunamadi: $RECEIVER_DIR"

LOCAL_PROPS="$RECEIVER_DIR/local.properties"
if [ ! -f "$LOCAL_PROPS" ]; then
    log_info "local.properties olusturuluyor (sdk.dir)..."
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" > "$LOCAL_PROPS"
else
    log_info "local.properties zaten var, dokunulmuyor (imzalama ayarlari korunuyor)."
fi

# --- sdkmanager konumunu bul ---
SDKMANAGER=""
if [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
elif [ -x "$ANDROID_HOME/bin/sdkmanager" ]; then
    SDKMANAGER="$ANDROID_HOME/bin/sdkmanager"
else
    found="$(find "$ANDROID_HOME" -maxdepth 4 -iname 'sdkmanager' -perm -u+x 2>/dev/null | head -n1)"
    SDKMANAGER="$found"
fi

if [ -n "$SDKMANAGER" ]; then
    log_info "NDK $NDK_VERSION kontrol ediliyor/kuruluyor ($SDKMANAGER)..."
    "$SDKMANAGER" --install "ndk;$NDK_VERSION" || log_warn "sdkmanager NDK kurulumu basarisiz oldu, gradle'in kendi NDK cozumune bakilacak"
else
    log_warn "sdkmanager bulunamadi, NDK kurulumu atlaniyor (gradle kendi cozebilir)"
fi

log_info "Git submodule'lari guncelleniyor..."
( cd "$REPO_ROOT" && git submodule update --init --recursive --depth 1 )

log_info "Gradle build basliyor (assembleRelease)..."
( cd "$RECEIVER_DIR" && ./gradlew assembleRelease )

APK_SRC="$(find "$RECEIVER_DIR" -path '*/release/*.apk' -iname '*release*.apk' 2>/dev/null | head -n1)"
[ -n "$APK_SRC" ] || APK_SRC="$(find "$RECEIVER_DIR/app/build/outputs/apk" -iname '*.apk' 2>/dev/null | head -n1)"
[ -n "$APK_SRC" ] || die "Build sonrasi APK bulunamadi (receiver/app/build/outputs/apk altina bakin)"

mkdir -p "$REPO_ROOT/out"
DEST="$REPO_ROOT/out/tvmirror.apk"
cp "$APK_SRC" "$DEST"
shasum -a 256 "$DEST" | awk '{print $1}' > "$DEST.sha256"

log_ok "Build tamamlandi: $DEST"
log_ok "sha256: $(cat "$DEST.sha256")"
