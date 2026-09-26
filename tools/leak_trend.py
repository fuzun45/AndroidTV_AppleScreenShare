#!/usr/bin/env python3
"""tools/leak_trend.py - scripts/65-leak-watch.sh tarafindan uretilen leak.tsv
dosyasini analiz edip Markdown rapor (PASS/SUPHELI) uretir.

Sadece Python standart kutuphanesini kullanir (stdlib-only), harici bagimlilik
yoktur.

Kullanim:
    leak_trend.py <leak.tsv> > LEAK.md

TSV kolonlari (scripts/65-leak-watch.sh ile ayni sira):
    ts  phase  pid  pss_total_kb  java_heap_kb  native_heap_kb  graphics_kb
    threads  fds  codecs  sf_layers  sys_mem_available_kb  swap_free_kb
    pswpin  pswpout  lmk_kills_total  mirroring  restart

Yaklasim:
    - Ilk %10'luk kisim (en az 1 ornek) isinma (warm-up) olarak yok sayilir.
    - Kalan orneklerle en kucuk kareler (least squares) egimi saatlik birime
      cevrilerek hesaplanir (pss_total, native_heap, java_heap, graphics,
      threads, fds, sf_layers, sys_mem_available_kb).
    - NA degerler yok sayilir (o metrik icin eksik veri).
    - Esikler asagida THRESHOLDS icinde; asilirsa Turkce supheli etiketi
      eklenir.
"""
import sys

NUMERIC_COLUMNS = (
    "pss_total_kb",
    "java_heap_kb",
    "native_heap_kb",
    "graphics_kb",
    "threads",
    "fds",
    "codecs",
    "sf_layers",
    "sys_mem_available_kb",
    "swap_free_kb",
    "pswpin",
    "pswpout",
    "lmk_kills_total",
    "mirroring",
    "restart",
)

COLUMNS = ("ts", "phase", "pid") + NUMERIC_COLUMNS

# Trend hesaplanan metrikler ve rapordaki gorunen adlari.
TREND_METRICS = (
    ("pss_total_kb", "TOTAL PSS (KB)"),
    ("native_heap_kb", "Native Heap (KB)"),
    ("java_heap_kb", "Java Heap (KB)"),
    ("graphics_kb", "Graphics (KB)"),
    ("threads", "Threads"),
    ("fds", "Acik FD sayisi"),
    ("sf_layers", "SurfaceFlinger katman sayisi (app)"),
    ("sys_mem_available_kb", "Sistem MemAvailable (KB)"),
)

# Esikler (saatlik egim). KB cinsinden metrikler icin MB/h -> KB/h.
THRESHOLDS = {
    "pss_total_kb": 8 * 1024.0,
    "native_heap_kb": 5 * 1024.0,
    "graphics_kb": 5 * 1024.0,
}
THREADS_SLOPE_THRESHOLD = 2.0
THREADS_DELTA_THRESHOLD = 5.0


def parse_tsv(path):
    """leak.tsv dosyasini okuyup dict listesine cevirir. NA -> None."""
    rows = []
    with open(path, "r") as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.strip() != ""]
    if not lines:
        return rows
    header = lines[0].split("\t")
    for line in lines[1:]:
        fields = line.split("\t")
        row = {}
        for i, col in enumerate(header):
            val = fields[i] if i < len(fields) else "NA"
            if col in ("ts", "phase", "pid"):
                if col == "ts":
                    row[col] = _to_number(val)
                else:
                    row[col] = val
            else:
                row[col] = _to_number(val)
        rows.append(row)
    return rows


def _to_number(val):
    if val is None:
        return None
    val = val.strip()
    if val == "" or val.upper() == "NA":
        return None
    try:
        if "." in val:
            return float(val)
        return int(val)
    except ValueError:
        try:
            return float(val)
        except ValueError:
            return None


def warmup_cutoff(n):
    """Ilk %10'u (en az 1 ornek) isinma olarak yok sayilacak eleman sayisi."""
    if n <= 0:
        return 0
    cut = n // 10
    if cut < 1:
        cut = 1
    if cut >= n:
        cut = n - 1
    return cut


def least_squares_slope_per_hour(rows, key):
    """(ts, deger) ciftlerinden saatlik egim (least squares). Yetersiz veri -> None."""
    pts = []
    for r in rows:
        ts = r.get("ts")
        val = r.get(key)
        if ts is None or val is None:
            continue
        pts.append((float(ts), float(val)))
    if len(pts) < 2:
        return None
    n = len(pts)
    sum_x = sum(p[0] for p in pts)
    sum_y = sum(p[1] for p in pts)
    mean_x = sum_x / n
    mean_y = sum_y / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in pts)
    den = sum((x - mean_x) ** 2 for x, y in pts)
    if den == 0:
        return 0.0
    slope_per_sec = num / den
    return slope_per_sec * 3600.0


def min_max_start_end(rows, key):
    """(start, end, min, max) - NA'lar yok sayilir. Veri yoksa None'lar."""
    vals = [(r.get("ts"), r.get(key)) for r in rows if r.get(key) is not None]
    if not vals:
        return (None, None, None, None)
    vals_sorted = sorted(vals, key=lambda t: t[0] if t[0] is not None else 0)
    start = vals_sorted[0][1]
    end = vals_sorted[-1][1]
    mn = min(v for _, v in vals_sorted)
    mx = max(v for _, v in vals_sorted)
    return (start, end, mn, mx)


def count_restarts(rows):
    return sum(1 for r in rows if r.get("restart") == 1)


def delta_first_last(rows, key):
    """Ilk ve son gecerli deger arasindaki fark (kumulatif sayaclar icin)."""
    vals = [r.get(key) for r in rows if r.get(key) is not None]
    if len(vals) < 2:
        return None
    return vals[-1] - vals[0]


def idle_codec_leak(rows):
    """mirroring==0 olan orneklerde codecs>0 olan ornek sayisi."""
    count = 0
    for r in rows:
        mirroring = r.get("mirroring")
        codecs = r.get("codecs")
        if mirroring == 0 and codecs is not None and codecs > 0:
            count += 1
    return count


def idle_sf_layer_growth(rows):
    """Idle (mirroring==0) orneklerde sf_layers egimi (saatlik). Veri yoksa None."""
    idle_rows = [r for r in rows if r.get("mirroring") == 0]
    return least_squares_slope_per_hour(idle_rows, "sf_layers")


def analyze(rows):
    """Tum analiz sonucunu dict olarak dondurur (rapor + testler icin)."""
    result = {
        "sample_count": len(rows),
        "metrics": {},
        "verdicts": [],
        "restarts": 0,
        "lmk_delta": None,
        "pswpin_delta": None,
        "pswpout_delta": None,
        "idle_codec_samples": 0,
        "idle_sf_layer_slope": None,
        "overall_pass": True,
    }
    if not rows:
        result["verdicts"].append("Veri yok (leak.tsv bos).")
        result["overall_pass"] = False
        return result

    cut = warmup_cutoff(len(rows))
    analysis_rows = rows[cut:]
    if not analysis_rows:
        analysis_rows = rows

    for key, label in TREND_METRICS:
        start, end, mn, mx = min_max_start_end(analysis_rows, key)
        slope = least_squares_slope_per_hour(analysis_rows, key)
        result["metrics"][key] = {
            "label": label,
            "start": start,
            "end": end,
            "min": mn,
            "max": mx,
            "slope_per_hour": slope,
        }

    restarts = count_restarts(rows)
    result["restarts"] = restarts

    lmk_delta = delta_first_last(rows, "lmk_kills_total")
    result["lmk_delta"] = lmk_delta

    result["pswpin_delta"] = delta_first_last(rows, "pswpin")
    result["pswpout_delta"] = delta_first_last(rows, "pswpout")

    idle_codec = idle_codec_leak(rows)
    result["idle_codec_samples"] = idle_codec

    idle_sf_slope = idle_sf_layer_growth(analysis_rows)
    result["idle_sf_layer_slope"] = idle_sf_slope

    verdicts = []

    for key in ("pss_total_kb", "native_heap_kb", "graphics_kb"):
        slope = result["metrics"][key]["slope_per_hour"]
        threshold = THRESHOLDS[key]
        label = result["metrics"][key]["label"]
        if slope is not None and slope > threshold:
            if key == "pss_total_kb":
                verdicts.append(
                    "SIZINTI SUPHESI: %s egimi %.1f KB/saat (esik %.1f KB/saat)"
                    % (label, slope, threshold)
                )
            else:
                verdicts.append(
                    "SUPHELI: %s egimi %.1f KB/saat (esik %.1f KB/saat)"
                    % (label, slope, threshold)
                )

    threads_metric = result["metrics"]["threads"]
    t_slope = threads_metric["slope_per_hour"]
    t_start = threads_metric["start"]
    t_end = threads_metric["end"]
    threads_flagged = False
    if t_slope is not None and t_slope > THREADS_SLOPE_THRESHOLD:
        threads_flagged = True
    if t_start is not None and t_end is not None and (t_end - t_start) > THREADS_DELTA_THRESHOLD:
        threads_flagged = True
    if threads_flagged:
        verdicts.append(
            "SUPHELI: Thread sayisi artis egiliminde (baslangic=%s, bitis=%s, egim=%s/saat)"
            % (t_start, t_end, ("%.2f" % t_slope) if t_slope is not None else "NA")
        )

    if idle_codec > 0:
        verdicts.append(
            "BIRAKILMAYAN CODEC: mirroring kapaliyken codec kullanimi gozlemlenen ornek sayisi=%d"
            % idle_codec
        )

    if idle_sf_slope is not None and idle_sf_slope > 0:
        verdicts.append(
            "SUPHELI: Idle durumda SurfaceFlinger katman sayisi artiyor (egim=%.2f/saat)"
            % idle_sf_slope
        )

    if restarts > 0:
        verdicts.append("SUPHELI: %d kez PID degisimi (olasi restart/crash) tespit edildi." % restarts)

    if lmk_delta is not None and lmk_delta > 0:
        verdicts.append("SUPHELI: LMK/lowmemorykiller olay sayisinda %d artis." % lmk_delta)

    result["verdicts"] = verdicts
    result["overall_pass"] = len(verdicts) == 0
    return result


def _fmt(v):
    if v is None:
        return "NA"
    if isinstance(v, float):
        return "%.1f" % v
    return str(v)


def render_markdown(analysis):
    lines = []
    lines.append("# Bellek/Kaynak Sizintisi Analizi (leak_trend.py)")
    lines.append("")
    lines.append("Ornek sayisi: %d" % analysis["sample_count"])
    lines.append("")
    lines.append("| Metrik | Baslangic | Bitis | Min | Max | Egim (saatlik) |")
    lines.append("|---|---|---|---|---|---|")
    for key, _label in TREND_METRICS:
        m = analysis["metrics"].get(key)
        if not m:
            continue
        slope = m["slope_per_hour"]
        slope_s = "%.2f" % slope if slope is not None else "NA"
        lines.append(
            "| %s | %s | %s | %s | %s | %s |"
            % (m["label"], _fmt(m["start"]), _fmt(m["end"]), _fmt(m["min"]), _fmt(m["max"]), slope_s)
        )
    lines.append("")
    lines.append("## Ek Bulgular")
    lines.append("")
    lines.append("- Restart/crash (PID degisimi) sayisi: %d" % analysis["restarts"])
    lines.append("- LMK/lowmemorykiller olay artisi (delta): %s" % _fmt(analysis["lmk_delta"]))
    lines.append("- pswpin delta: %s" % _fmt(analysis["pswpin_delta"]))
    lines.append("- pswpout delta: %s" % _fmt(analysis["pswpout_delta"]))
    lines.append("- Idle (mirroring=0) orneklerde codec gorulen ornek sayisi: %d" % analysis["idle_codec_samples"])
    idle_sf = analysis["idle_sf_layer_slope"]
    lines.append("- Idle SurfaceFlinger katman egimi (saatlik): %s" % ("%.2f" % idle_sf if idle_sf is not None else "NA"))
    lines.append("")
    lines.append("## Verdict")
    lines.append("")
    if analysis["verdicts"]:
        for v in analysis["verdicts"]:
            lines.append("- %s" % v)
    else:
        lines.append("- Supheli bulgu yok.")
    lines.append("")
    lines.append("**SONUC: %s**" % ("PASS" if analysis["overall_pass"] else "SUPHELI"))
    lines.append("")
    return "\n".join(lines)


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("Kullanim: leak_trend.py <leak.tsv>\n")
        return 2
    path = argv[1]
    rows = parse_tsv(path)
    analysis = analyze(rows)
    sys.stdout.write(render_markdown(analysis))
    return 0 if analysis["overall_pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
