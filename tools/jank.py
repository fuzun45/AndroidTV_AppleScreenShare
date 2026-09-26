#!/usr/bin/env python3
"""
jank.py - SurfaceFlinger --latency verilerinden frame istatistigi cikarir.

`dumpsys SurfaceFlinger --latency "<layer>"` ciktisi:
  - ilk satir: refresh period (ns)
  - sonraki satirlar: 3 timestamp (desiredPresentTime, actualPresentTime, frameReadyTime), tab ile ayrilmis
  - 0 veya INT64_MAX (9223372036854775807) olan satirlar/bekleyen ya da gecersiz kare demektir.

Bu script, latency buffer'i ~127 kare tuttugu icin periyodik olarak tekrar tekrar
sorgular, actualPresentTime'a gore kareleri tekillestirir (dedup) ve toplam
pencere sonunda fps / frame interval percentile'lari / janky oranini hesaplar.

Kullanim:
    jank.py --adb ADB --device DEV [--layer-regex REGEX] [--seconds 20]
            [--interval 1.0] [--json out.json]
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layer_select  # noqa: E402

INT64_MAX = 9223372036854775807

# Geriye donuk uyumluluk icin tutuluyor; --layer-regex acikca verilirse kullanilir.
DEFAULT_LAYER_REGEX = r"SurfaceView.*tvmirror|tvmirror.*SurfaceView"

NOISE_LINES = ("Init wrapper", "open mma")


def run_adb(adb, device, args, timeout=10):
    """adb -s DEVICE <args> calistirir, gurultu satirlarini filtreler."""
    cmd = [adb, "-s", device] + args
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return ""
    except FileNotFoundError:
        print(f"HATA: adb bulunamadi: {adb}", file=sys.stderr)
        sys.exit(2)
    lines = (proc.stdout or "").splitlines()
    lines = [ln for ln in lines if not any(ln.startswith(n) for n in NOISE_LINES)]
    return "\n".join(lines)


def list_layers(adb, device):
    out = run_adb(adb, device, ["shell", "dumpsys", "SurfaceFlinger", "--list"])
    return [ln.strip() for ln in out.splitlines() if ln.strip()]


def autodetect_layer_regex(adb, device, layer_regex):
    """Eski regex tabanli algilama (yalnizca --layer-regex acikca verildiyse kullanilir)."""
    layers = list_layers(adb, device)
    pattern = re.compile(layer_regex, re.IGNORECASE)
    candidates = [ln for ln in layers if pattern.search(ln)]
    if not candidates:
        return None, layers
    # (BLAST) iceren isimleri tercih et
    blast = [ln for ln in candidates if "(BLAST)" in ln]
    chosen = blast[0] if blast else candidates[0]
    return chosen, layers


def get_focus_hint(adb, device):
    """dumpsys window'dan mCurrentFocus satirini alir (secim icin ipucu)."""
    out = run_adb(adb, device, ["shell", "dumpsys", "window"])
    lines = [ln for ln in out.splitlines() if "mCurrentFocus" in ln or "mFocusedApp" in ln]
    return "\n".join(lines)


def autodetect_layer(adb, device):
    """tools/layer_select.py'deki oncelikli secim mantigini kullanir."""
    list_output = run_adb(adb, device, ["shell", "dumpsys", "SurfaceFlinger", "--list"])
    layers = [ln.strip() for ln in list_output.splitlines() if ln.strip()]
    focus_hint = get_focus_hint(adb, device)
    chosen, candidates = layer_select.pick_video_layer(list_output, focus_hint)
    return chosen, candidates if candidates else layers


def parse_latency(text):
    """--latency ciktisini parse eder.

    Donen: (refresh_period_ns_or_None, [(desired, actual, ready), ...])
    Gecersiz (0 veya INT64_MAX iceren) satirlar atlanir.
    """
    lines = [ln for ln in text.splitlines() if ln.strip() != ""]
    if not lines:
        return None, []

    refresh_period = None
    first = lines[0].strip()
    try:
        refresh_period = int(first.split()[0])
    except (ValueError, IndexError):
        refresh_period = None

    frames = []
    for ln in lines[1:]:
        parts = ln.split()
        if len(parts) < 3:
            continue
        try:
            desired, actual, ready = int(parts[0]), int(parts[1]), int(parts[2])
        except ValueError:
            continue
        if desired in (0, INT64_MAX) or actual in (0, INT64_MAX) or ready in (0, INT64_MAX):
            continue
        frames.append((desired, actual, ready))
    return refresh_period, frames


def percentile(sorted_vals, p):
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    k = (len(sorted_vals) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return sorted_vals[f]
    d0 = sorted_vals[f] * (c - k)
    d1 = sorted_vals[c] * (k - f)
    return d0 + d1


def collect(adb, device, layer, seconds, interval):
    """Periyodik olarak --latency sorgular, actualPresent'e gore dedup eder."""
    seen_actual = set()
    all_actual = []  # sirali, tekillestirilmis actualPresentTime listesi
    refresh_period = None
    end_time = time.time() + seconds
    layer_disappeared = False

    while time.time() < end_time:
        out = run_adb(
            # katman adi "(BLAST)#123" icerir: uzak kabukta "(" soz dizimi hatasi, "#" yorum
            # baslatir. Tek tirnakla aynen iletilmeli.
            adb, device, ["shell", "dumpsys", "SurfaceFlinger", "--latency", shlex.quote(layer)]
        )
        if not out.strip():
            # katman gitmis olabilir (mirror oturumu bitti)
            layers_now = list_layers(adb, device)
            if layer not in layers_now:
                layer_disappeared = True
                break
        else:
            rp, frames = parse_latency(out)
            if rp:
                refresh_period = rp
            for _desired, actual, _ready in frames:
                if actual not in seen_actual:
                    seen_actual.add(actual)
                    all_actual.append(actual)
        time.sleep(interval)

    all_actual.sort()
    return refresh_period, all_actual, layer_disappeared


def compute_stats(refresh_period, actual_times):
    n = len(actual_times)
    if n < 2:
        return {
            "frames": n,
            "fps": None,
            "refresh_period_ns": refresh_period,
            "p50_ms": None,
            "p95_ms": None,
            "p99_ms": None,
            "max_ms": None,
            "janky_count": None,
            "janky_pct": None,
        }

    span_ns = actual_times[-1] - actual_times[0]
    fps = (n - 1) / (span_ns / 1e9) if span_ns > 0 else None

    intervals_ms = [
        (actual_times[i] - actual_times[i - 1]) / 1e6 for i in range(1, n)
    ]
    sorted_iv = sorted(intervals_ms)
    median = percentile(sorted_iv, 50)
    p95 = percentile(sorted_iv, 95)
    p99 = percentile(sorted_iv, 99)
    max_iv = sorted_iv[-1]

    janky_threshold = median * 1.5 if median else None
    janky_count = 0
    if janky_threshold:
        janky_count = sum(1 for iv in intervals_ms if iv > janky_threshold)
    janky_pct = (janky_count / len(intervals_ms) * 100.0) if intervals_ms else None

    return {
        "frames": n,
        "fps": fps,
        "refresh_period_ns": refresh_period,
        "p50_ms": median,
        "p95_ms": p95,
        "p99_ms": p99,
        "max_ms": max_iv,
        "janky_count": janky_count,
        "janky_pct": janky_pct,
    }


def main():
    ap = argparse.ArgumentParser(description="SurfaceFlinger jank/fps olcumu")
    ap.add_argument("--adb", required=True, help="adb binary yolu")
    ap.add_argument("--device", required=True, help="adb -s <device>")
    ap.add_argument(
        "--layer-regex",
        default=None,
        help="Katman adi icin regex (verilirse layer_select.py yerine bu kullanilir)",
    )
    ap.add_argument("--layer", default=None, help="Katman adini otomatik algilamak yerine dogrudan ver")
    ap.add_argument("--seconds", type=float, default=20.0, help="Toplam olcum suresi (sn)")
    ap.add_argument("--interval", type=float, default=1.0, help="Sorgu araligi (sn)")
    ap.add_argument("--json", default=None, help="Sonucu JSON olarak da yaz")
    args = ap.parse_args()

    candidates = None
    if args.layer:
        layer = args.layer
    elif args.layer_regex:
        layer, candidates = autodetect_layer_regex(args.adb, args.device, args.layer_regex)
    else:
        layer, candidates = autodetect_layer(args.adb, args.device)

    if not layer:
        print("HATA: Katman bulunamadi. --list ciktisi (SurfaceView adaylari):", file=sys.stderr)
        for ln in (candidates or []):
            print(f"  {ln}", file=sys.stderr)
        if args.json:
            with open(args.json, "w", encoding="utf-8") as f:
                json.dump({"layer": None, "candidates": candidates or []}, f, ensure_ascii=False, indent=2)
        sys.exit(1)

    print(f"Katman: {layer}")
    print(f"Olcum suresi: {args.seconds:.0f} sn, aralik: {args.interval:.1f} sn")

    refresh_period, actual_times, disappeared = collect(
        args.adb, args.device, layer, args.seconds, args.interval
    )
    stats = compute_stats(refresh_period, actual_times)
    stats["layer"] = layer
    stats["partial"] = disappeared

    if disappeared:
        print("NOT: Katman olcum sirasinda kayboldu (oturum bitmis olabilir), kismi sonuc.")

    print("\n=== Ozet ===")
    if stats["fps"] is not None:
        print(f"Kare sayisi     : {stats['frames']}")
        print(f"FPS (sunulan)   : {stats['fps']:.1f}")
        rp = stats["refresh_period_ns"]
        if rp:
            print(f"Refresh period  : {rp} ns (~{1e9/rp:.1f} Hz)")
        print(f"Kare araligi p50: {stats['p50_ms']:.2f} ms")
        print(f"Kare araligi p95: {stats['p95_ms']:.2f} ms")
        print(f"Kare araligi p99: {stats['p99_ms']:.2f} ms")
        print(f"Kare araligi max: {stats['max_ms']:.2f} ms")
        print(f"Takilma (janky) : {stats['janky_count']} kare (%{stats['janky_pct']:.1f})")
    else:
        print("Yeterli kare toplanamadi (0 veya 1 gecerli kare).")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(stats, f, ensure_ascii=False, indent=2)
        print(f"\nJSON yazildi: {args.json}")


if __name__ == "__main__":
    main()
