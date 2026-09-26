#!/usr/bin/env bash
# 50-perf-capture.sh - Aktif mirroring sirasinda performans yakalama.
# Kullanim: 50-perf-capture.sh <etiket> [sure_sn=120]
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

LABEL="${1:-}"
[ -n "$LABEL" ] || die "Kullanim: $0 <etiket> [sure_sn=120]"
SECONDS_DUR="${2:-120}"

need_device || exit 1
setup_out_dir "perf-${LABEL}"

mirroring_active() {
    # Katman adi cihaza gore degisebildigi icin asil sinyal TvMirrorStats logu;
    # SurfaceView varligi ek bir ipucu.
    adbs dumpsys SurfaceFlinger --list | grep -qi 'SurfaceView' && return 0
    adbs logcat -d -s TvMirrorStats:* -t 50 | grep -q 'TvMirrorStats' && return 0
    return 1
}

log_info "Mirroring aktif mi kontrol ediliyor..."
waited=0
while ! mirroring_active; do
    if [ "$waited" -ge 60 ]; then
        die "60 saniye icinde mirroring baslamadi. Lutfen iPhone/Mac'ten mirroring baslatip tekrar deneyin."
    fi
    log_warn "Mirroring bekleniyor... (${waited}s) iPhone/Mac'ten AirPlay/ekran yansitmayi baslatin."
    sleep 5
    waited=$((waited + 5))
done
log_ok "Mirroring aktif, olcum basliyor."

# Decoder seçimi sunucu başlarken loglanıyor; logcat temizlenmeden önce sakla.
adbs logcat -d > "$OUT/logcat-before.txt"
adbs logcat -c

log_info "Video SurfaceView katmani seciliyor..."
adbs dumpsys SurfaceFlinger --list > "$OUT/sf-list.txt"
adbs dumpsys window | safe_grep -E 'mCurrentFocus|mFocusedApp' > "$OUT/focus.txt"
FOCUS_TEXT="$(cat "$OUT/focus.txt")"
python3 "$REPO_ROOT/tools/layer_select.py" --focus "$FOCUS_TEXT" < "$OUT/sf-list.txt" > "$OUT/layer.txt"
VIDEO_LAYER="$(head -n1 "$OUT/layer.txt")"
if [ -n "$VIDEO_LAYER" ]; then
    log_ok "Video katmani: $VIDEO_LAYER"
else
    log_warn "Video katmani otomatik secilemedi, adaylar $OUT/layer.txt icinde. jank.py kendi ici secimini deneyecek."
fi

log_info "Baslangic HWC/SurfaceFlinger anlik goruntusu..."
adbs dumpsys SurfaceFlinger > "$OUT/sf-before.txt"
safe_grep -i 'missed' "$OUT/sf-before.txt" > "$OUT/missed-before.txt"
python3 "$REPO_ROOT/tools/hwc_layers.py" < "$OUT/sf-before.txt" > "$OUT/complayers-before.txt" 2>/dev/null || true

log_info "tools/jank.py arka planda baslatiliyor (${SECONDS_DUR}sn)..."
JANK_JSON="$OUT/jank.json"
JANK_ARGS=(--adb "$ADB" --device "$DEV" --seconds "$SECONDS_DUR" --interval 1.0 --json "$JANK_JSON")
if [ -n "$VIDEO_LAYER" ]; then
    JANK_ARGS+=(--layer "$VIDEO_LAYER")
fi
python3 "$REPO_ROOT/tools/jank.py" "${JANK_ARGS[@]}" > "$OUT/jank-stdout.txt" 2>&1 &
JANK_PID=$!

log_info "Periyodik ornekleme (5sn araliklarla) basliyor..."
SAMPLES="$OUT/samples.tsv"
printf 'ts\tcpu_line\tpss_kb\tmem_available_kb\tswap_free_kb\tpswpin\tpswpout\trssi\tlinkspeed\n' > "$SAMPLES"

elapsed=0
while [ "$elapsed" -lt "$SECONDS_DUR" ]; do
    ts="$(date +%s)"
    cpu_line="$(app_cpu)"
    pss_kb="$(app_pss_kb)"
    mem_avail="$(adbs cat /proc/meminfo 2>/dev/null | safe_grep MemAvailable | tr -s ' ' | cut -d' ' -f2)"
    swap_free="$(adbs cat /proc/meminfo 2>/dev/null | safe_grep SwapFree | tr -s ' ' | cut -d' ' -f2)"
    pswpin="$(adbs cat /proc/vmstat 2>/dev/null | safe_grep '^pswpin ' | cut -d' ' -f2)"
    pswpout="$(adbs cat /proc/vmstat 2>/dev/null | safe_grep '^pswpout ' | cut -d' ' -f2)"
    wifi_line="$(wifi_now)"
    rssi="$(echo "$wifi_line" | grep -oE 'RSSI: -?[0-9]+' | grep -oE -- '-?[0-9]+')"
    linkspeed="$(echo "$wifi_line" | grep -oE 'Link speed: [0-9]+' | grep -oE '[0-9]+')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ts" "${cpu_line:-NA}" "${pss_kb:-NA}" "${mem_avail:-NA}" "${swap_free:-NA}" \
        "${pswpin:-NA}" "${pswpout:-NA}" "${rssi:-NA}" "${linkspeed:-NA}" >> "$SAMPLES"
    sleep 5
    elapsed=$((elapsed + 5))
done

log_info "jank.py'nin bitmesi bekleniyor..."
wait "$JANK_PID" 2>/dev/null || true

log_info "Bitis HWC/SurfaceFlinger anlik goruntusu..."
adbs dumpsys SurfaceFlinger > "$OUT/sf-after.txt"
safe_grep -i 'missed' "$OUT/sf-after.txt" > "$OUT/missed-after.txt"
python3 "$REPO_ROOT/tools/hwc_layers.py" < "$OUT/sf-after.txt" > "$OUT/complayers-after.txt" 2>/dev/null || true

log_info "Video SurfaceView katmani (bitis) yeniden seciliyor..."
adbs dumpsys SurfaceFlinger --list > "$OUT/sf-list-after.txt"
adbs dumpsys window | safe_grep -E 'mCurrentFocus|mFocusedApp' > "$OUT/focus-after.txt"
FOCUS_TEXT_AFTER="$(cat "$OUT/focus-after.txt")"
python3 "$REPO_ROOT/tools/layer_select.py" --focus "$FOCUS_TEXT_AFTER" < "$OUT/sf-list-after.txt" > "$OUT/layer-after.txt"
VIDEO_LAYER_END="$(head -n1 "$OUT/layer-after.txt")"
if [ -z "$VIDEO_LAYER_END" ]; then
    VIDEO_LAYER_END="$VIDEO_LAYER"
fi
if [ -n "$VIDEO_LAYER_END" ]; then
    log_ok "Video katmani (bitis): $VIDEO_LAYER_END"
fi
if [ -n "$VIDEO_LAYER" ] && [ -n "$VIDEO_LAYER_END" ] && [ "$VIDEO_LAYER_END" != "$VIDEO_LAYER" ]; then
    log_warn "Video katmani, olcum sirasinda yeniden olusturulmus (yuzey degisti): baslangic=$VIDEO_LAYER bitis=$VIDEO_LAYER_END"
fi

log_info "Video katmani tampon (buffer) detaylari cikariliyor..."
VIDEO_LAYER="$VIDEO_LAYER_END" python3 -c '
import os, re, sys

video = os.environ.get("VIDEO_LAYER", "").strip()
path = sys.argv[1]
details_out = sys.argv[2]
format_out = sys.argv[3]

FIELD_RE = re.compile(r"format|dataspace|usage|buffer|composition|crop|frame|transform", re.IGNORECASE)

lines = []
if video:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        lines = []

result = []
seen = set()
if video:
    for i, ln in enumerate(lines):
        if video not in ln:
            continue
        # eslesen katman satirindan sonraki (en fazla) 25 satira bak
        for j in range(i + 1, min(i + 1 + 25, len(lines))):
            cand = lines[j].rstrip("\n")
            if not FIELD_RE.search(cand):
                continue
            if cand in seen:
                continue
            seen.add(cand)
            result.append(cand)
            if len(result) >= 40:
                break
        if len(result) >= 40:
            break

with open(details_out, "w", encoding="utf-8") as f:
    for ln in result[:40]:
        f.write(ln + "\n")

# Android 14 dökümünde piksel formatı yazmıyor; dataspace ayırt edici:
# GL ile çizilen RGBA tampon V0_SRGB (0x8810000), codec YUV çıkışı video dataspace degeri
# taşıyor (ör. 0x8c10000 = BT709/SMPTE170M/FULL). Bitler: standard 16-21, transfer 22-26,
# range 27-29 (1=FULL, 2=LIMITED).
def _dataspaces(rows):
    out = []
    for ln in rows:
        for m in re.finditer(r"dataspace=(\S+)(?: \((\d+)\))?", ln):
            name, num = m.group(1), m.group(2)
            try:
                val = int(num) if num else int(name, 16)
            except ValueError:
                val = None
            out.append((name, val))
    return out

verdict = "Tampon bicimi belirlenemedi"
for name, val in _dataspaces(result):
    if val in (None, 0):
        continue
    if "SRGB" in name.upper() or val == 0x8810000:
        verdict = "Tampon: RGBA (GL cizimi), dataspace %s" % name
        break
    transfer = (val >> 22) & 0x1F
    rng = {1: "FULL", 2: "LIMITED", 3: "EXTENDED"}.get((val >> 27) & 0x7, "?")
    if transfer in (3, 7):  # SMPTE_170M / HLG vb. video transferleri
        verdict = "Tampon: YUV (codec dogrudan), dataspace %s, range %s" % (name, rng)
        break
with open(format_out, "w", encoding="utf-8") as f:
    f.write(verdict + "\n")
' "$OUT/sf-after.txt" "$OUT/video-layer-details.txt" "$OUT/video-layer-format.txt" 2>/dev/null || true

log_info "TvMirrorStats logcat kaydediliyor..."
adbs logcat -d -s TvMirrorStats:* > "$OUT/tvmirrorstats.log"

log_info "Decoder secim loglari..."
adbs logcat -d > "$OUT/logcat-full.txt"
cat "$OUT/logcat-before.txt" >> "$OUT/logcat-full.txt"
safe_grep -iE 'DecoderSelector|MediaCodec|low-latency|vdec' "$OUT/logcat-full.txt" | tail -n 200 > "$OUT/decoder-selection.log"
# HEVC/AVC secimiyle ilgili satirlar; TvMirrorStats'in saniyelik durum satirlari haric.
safe_grep -viE 'TvMirrorStats' "$OUT/logcat-full.txt" \
    | safe_grep -iE 'decoders: avc=|hevc decoder not whitelisted|Video codec started|output switched|experiments:|Direct output failed|setOutputSurface|H\.265|h265|hevc' \
    | tail -n 20 > "$OUT/hevc-selection.log"

# --- Ozet hesaplamalari ---
extract_median_field() {
    # $1: log dosyasi, $2: alan anahtari (orn "in_fps=")
    safe_grep -o "$2[0-9.]*" "$1" | sed "s/$2//" | sort -n | awk '
        { a[NR]=$1 }
        END {
            if (NR==0) { print "NA"; exit }
            if (NR % 2 == 1) { print a[(NR+1)/2] }
            else { print (a[NR/2]+a[NR/2+1])/2 }
        }'
}

req="$(safe_grep -o 'req=[0-9x@]*' "$OUT/tvmirrorstats.log" | tail -n1 | sed 's/req=//')"
recv="$(safe_grep -o 'recv=[0-9x]*' "$OUT/tvmirrorstats.log" | tail -n1 | sed 's/recv=//')"
codec="$(safe_grep -o 'codec=[A-Za-z0-9._-]*' "$OUT/tvmirrorstats.log" | tail -n1 | sed 's/codec=//')"
audio="$(safe_grep -o 'audio=[A-Za-z0-9._-]*' "$OUT/tvmirrorstats.log" | tail -n1 | sed 's/audio=//')"
# ölçüm süresince görülen codec çıkış yolları (direct/gl); karışıksa ikisi de yazılır
out_paths="$(safe_grep -o 'out=[a-z]*' "$OUT/tvmirrorstats.log" | sed 's/out=//' | sort | uniq -c | awk '{printf "%s%s(%s)", sep, $2, $1; sep=" "}')"
decoder="$(safe_grep -o 'decoder=[^ ]*' "$OUT/tvmirrorstats.log" | tail -n1 | sed 's/decoder=//')"
in_fps_med="$(extract_median_field "$OUT/tvmirrorstats.log" 'in_fps=')"
dec_fps_med="$(extract_median_field "$OUT/tvmirrorstats.log" 'dec_fps=')"
dropped_last="$(safe_grep -o 'dropped=[0-9]*' "$OUT/tvmirrorstats.log" | tail -n1 | sed 's/dropped=//')"

presented_fps="NA"
janky_pct="NA"
janky_pct_cadence="NA"
cadence_expected_fps="NA"
cadence_limit_ms="NA"
dropped_vs_expected_pct="NA"
JANK_CADENCE_JSON="$OUT/jank-cadence.json"
if [ -f "$JANK_JSON" ]; then
    presented_fps="$(python3 -c "import json; d=json.load(open('$JANK_JSON')); v=d.get('fps'); print('%.1f' % v if v is not None else 'NA')" 2>/dev/null || echo NA)"
    janky_pct="$(python3 -c "import json; d=json.load(open('$JANK_JSON')); v=d.get('janky_pct'); print('%.2f' % v if v is not None else 'NA')" 2>/dev/null || echo NA)"

    # in_fps medyani (icerik temposu) yalnizca capture bittikten SONRA biliniyor;
    # bu yuzden cadence-aware jank'i burada, jank.py'nin --from-json modu ile
    # kaydedilmis ham zaman damgalarindan (adb'ye tekrar gitmeden) hesapliyoruz.
    case "$in_fps_med" in
        ''|NA) : ;;
        *)
            if python3 "$REPO_ROOT/tools/jank.py" --from-json "$JANK_JSON" --expected-fps "$in_fps_med" \
                --json "$JANK_CADENCE_JSON" > "$OUT/jank-cadence-stdout.txt" 2>&1; then
                janky_pct_cadence="$(python3 -c "import json; d=json.load(open('$JANK_CADENCE_JSON')); v=d.get('janky_pct_cadence'); print('%.2f' % v if v is not None else 'NA')" 2>/dev/null || echo NA)"
                cadence_expected_fps="$(python3 -c "import json; d=json.load(open('$JANK_CADENCE_JSON')); v=d.get('expected_fps'); print('%.1f' % v if v is not None else 'NA')" 2>/dev/null || echo NA)"
                cadence_limit_ms="$(python3 -c "import json; d=json.load(open('$JANK_CADENCE_JSON')); v=d.get('cadence_limit_ms'); print('%.2f' % v if v is not None else 'NA')" 2>/dev/null || echo NA)"
                dropped_vs_expected_pct="$(python3 -c "import json; d=json.load(open('$JANK_CADENCE_JSON')); v=d.get('dropped_vs_expected_pct'); print('%.2f' % v if v is not None else 'NA')" 2>/dev/null || echo NA)"
            fi
            ;;
    esac
fi

# complayers-*.txt: "<TIP>\t<katman adi>" (tools/hwc_layers.py). hwc_layers.py'nin
# gordugu ad, VIDEO_LAYER'daki sonek/parantezleri iceremeyebilir; bu yuzden tam
# esitlik tutmazsa birbirini icerme, o da tutmazsa ayni "#<id>" ile eslesen
# SurfaceView satirina dusuluyor (tools/layer_select.py'deki secime paralel).
VIDEO_LAYER="$VIDEO_LAYER_END" python3 -c '
import os, re, sys

video = os.environ.get("VIDEO_LAYER", "").strip()
path = sys.argv[1]
comptype_out = sys.argv[2]
other_out = sys.argv[3]

def contains_match(a, b):
    if not a or not b:
        return False
    return a in b or b in a

entries = []
try:
    with open(path, encoding="utf-8") as f:
        for ln in f:
            parts = ln.rstrip("\n").split("\t", 1)
            if len(parts) == 2:
                entries.append((parts[0], parts[1].strip()))
except OSError:
    pass

trailing_id = None
m = re.search(r"#(\d+)\s*$", video)
if m:
    trailing_id = m.group(1)

matched_name = None
comptype = "NA"
if video:
    for t, name in entries:
        if name == video:
            matched_name, comptype = name, t
            break
    if matched_name is None:
        for t, name in entries:
            if contains_match(name, video):
                matched_name, comptype = name, t
                break
    if matched_name is None and trailing_id:
        for t, name in entries:
            if "SurfaceView" in name and name.endswith("#" + trailing_id):
                matched_name, comptype = name, t
                break

with open(comptype_out, "w", encoding="utf-8") as f:
    f.write(comptype + "\n")

with open(other_out, "w", encoding="utf-8") as f:
    for t, name in entries:
        if t == "CLIENT" and name != matched_name:
            f.write(name + "\n")
' "$OUT/complayers-after.txt" "$OUT/video-layer-comptype.txt" "$OUT/other-client-layers.txt" 2>/dev/null || true

video_layer_comptype="$(cat "$OUT/video-layer-comptype.txt" 2>/dev/null | tr -d '\n')"
video_layer_comptype="${video_layer_comptype:-NA}"
other_client_layers="$(cat "$OUT/other-client-layers.txt" 2>/dev/null)"

missed_before_n="$(safe_grep -m1 'HWC missed' "$OUT/missed-before.txt" | grep -oE '[0-9]+' | tail -n1)"
missed_after_n="$(safe_grep -m1 'HWC missed' "$OUT/missed-after.txt" | grep -oE '[0-9]+' | tail -n1)"
missed_delta="NA"
if [ -n "${missed_before_n:-}" ] && [ -n "${missed_after_n:-}" ]; then
    missed_delta=$((missed_after_n - missed_before_n))
fi

cpu_median="$(awk -F'\t' 'NR>1 && $2!="NA"{print $2}' "$SAMPLES" | safe_grep -E '^[0-9]+(\.[0-9]+)?$' | sort -n | awk '{a[NR]=$1} END{if(NR==0){print "NA"; exit} if(NR%2==1) print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2}')"
pss_start="$(awk -F'\t' 'NR==2{print $3}' "$SAMPLES")"
pss_end="$(awk -F'\t' 'END{print $3}' "$SAMPLES")"
pss_peak="$(awk -F'\t' 'NR>1 && $3!="NA"{print $3}' "$SAMPLES" | sort -n | tail -n1)"
rssi_min="$(awk -F'\t' 'NR>1{print $8}' "$SAMPLES" | safe_grep -oE '\-?[0-9]+' | sort -n | head -n1)"
rssi_max="$(awk -F'\t' 'NR>1{print $8}' "$SAMPLES" | safe_grep -oE '\-?[0-9]+' | sort -n | tail -n1)"
pswpin_start="$(awk -F'\t' 'NR==2{print $6}' "$SAMPLES")"
pswpin_end="$(awk -F'\t' 'END{print $6}' "$SAMPLES")"
pswpout_start="$(awk -F'\t' 'NR==2{print $7}' "$SAMPLES")"
pswpout_end="$(awk -F'\t' 'END{print $7}' "$SAMPLES")"

SUMMARY="$OUT/SUMMARY.md"
{
    echo "# Performans Yakalama Ozeti - $LABEL"
    echo
    echo "- Tarih: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Sure: ${SECONDS_DUR}sn"
    echo
    echo "## Uctan Uca Akis"
    echo
    echo "istenen (req) -> alinan (recv) -> decode edilen (dec_fps) -> sunulan (presented fps)"
    echo
    echo "\`\`\`"
    echo "req      : ${req:-NA}"
    echo "recv     : ${recv:-NA}"
    echo "codec    : ${codec:-NA} (decoder=${decoder:-NA})"
    echo "in_fps   : ${in_fps_med:-NA} (medyan)"
    echo "dec_fps  : ${dec_fps_med:-NA} (medyan)"
    echo "presented: ${presented_fps} fps (jank.py, sunulan)"
    echo "dropped  : ${dropped_last:-NA} (son deger)"
    echo "audio    : ${audio:-NA}"
    echo "output   : ${out_paths:-NA} (codec cikis yolu, saniye sayisi)"
    echo "\`\`\`"
    if echo "$dec_fps_med" | grep -qE '^[0-9]+(\.[0-9]+)?$' && echo "$presented_fps" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        drop_pct="$(awk -v d="$dec_fps_med" -v p="$presented_fps" 'BEGIN{ if (d > 0 && p < 0.9*d) printf "%.0f", (1-p/d)*100; else print "" }')"
        if [ -n "$drop_pct" ]; then
            echo
            echo "UYARI: decode edilen karelerin %${drop_pct}'i ekrana ulasmadi (kompozisyon darbogazi)"
        fi
    fi
    echo
    echo "## Takilma (Jank)"
    echo
    echo "- Ham jank (medyan tabanli): ${janky_pct}%"
    if [ "$janky_pct_cadence" != "NA" ]; then
        echo "- Icerik temposuna gore jank: ${janky_pct_cadence}% (beklenen ${cadence_expected_fps} fps, sinir ${cadence_limit_ms} ms)"
        echo "- Beklenene gore eksik kare: ${dropped_vs_expected_pct}%"
    else
        echo "- Icerik temposuna gore jank: hesaplanamadi (in_fps medyani bulunamadi)"
    fi
    echo
    echo "## Video katmani ayrintilari (tampon bicimi)"
    echo
    if [ -n "$VIDEO_LAYER" ] && [ -s "$OUT/video-layer-details.txt" ]; then
        echo "- $(cat "$OUT/video-layer-format.txt" 2>/dev/null || echo "Tampon bicimi belirlenemedi")"
        echo '```'
        cat "$OUT/video-layer-details.txt"
        echo '```'
    else
        echo "- Video katmani detaylari bulunamadi."
    fi
    echo
    echo "## HWC Katman Durumu"
    echo
    if [ -n "$VIDEO_LAYER" ]; then
        echo "- Secilen video katmani (baslangic): \`${VIDEO_LAYER}\`"
    else
        echo "- Secilen video katmani (baslangic): bulunamadi (jank.py kendi ici secimini denedi, asagida adaylar)"
        echo "\`\`\`"
        safe_grep '^# aday:' "$OUT/layer.txt"
        echo "\`\`\`"
    fi
    if [ -n "$VIDEO_LAYER_END" ]; then
        echo "- Secilen video katmani (bitis): \`${VIDEO_LAYER_END}\`"
    else
        echo "- Secilen video katmani (bitis): bulunamadi"
    fi
    if [ -n "$VIDEO_LAYER" ] && [ -n "$VIDEO_LAYER_END" ] && [ "$VIDEO_LAYER" != "$VIDEO_LAYER_END" ]; then
        echo "- UYARI: katman olcum sirasinda yeniden olusturuldu (yuzey degisti); presented olcumu kismi olabilir"
    fi
    echo "- Video katmani Comp Type: ${video_layer_comptype:-NA}"
    echo "- Diger CLIENT (GPU) katmanlari:"
    echo '```'
    echo "${other_client_layers:-yok}"
    echo '```'
    echo "- Missed frame delta: ${missed_delta}"
    echo
    echo "## Decoder Secimi"
    echo
    echo "- decoder=${decoder:-NA} (TvMirrorStats)"
    echo "\`\`\`"
    if [ -s "$OUT/hevc-selection.log" ]; then
        cat "$OUT/hevc-selection.log"
    else
        echo "(ilgili log satiri bulunamadi)"
    fi
    echo '```'
    echo
    echo "## Sistem Kaynaklari"
    echo
    echo "- CPU medyan (uygulama, top): ${cpu_median:-NA}%"
    echo "- PSS baslangic/bitis/tepe (KB): ${pss_start:-NA} / ${pss_end:-NA} / ${pss_peak:-NA}"
    echo "- Swap pswpin delta: $((${pswpin_end:-0} - ${pswpin_start:-0})) (basl:${pswpin_start:-NA} bit:${pswpin_end:-NA})"
    echo "- Swap pswpout delta: $((${pswpout_end:-0} - ${pswpout_start:-0})) (basl:${pswpout_start:-NA} bit:${pswpout_end:-NA})"
    echo "- Wi-Fi RSSI araligi: ${rssi_min:-NA} .. ${rssi_max:-NA}"
    echo
    echo "## Ham Dosyalar"
    echo
    echo "Cikti dizini: $OUT"
} > "$SUMMARY"

log_ok "Yakalama tamamlandi."
echo
cat "$SUMMARY"
