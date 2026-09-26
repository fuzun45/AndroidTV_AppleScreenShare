#!/usr/bin/env python3
"""
layer_select.py - `dumpsys SurfaceFlinger --list` ciktisindan video icin
kullanilan SurfaceView katmanini secer.

Katman adi cihaza/OS surumune gore degisebilir (orn. paket adi, activity
sinif adi veya sadece pencere basligi icerebilir), bu yuzden sabit bir
regex yerine oncelik sirali bir secim mantigi kullanilir:

  1. Aday kumesi: "SurfaceView" iceren, "Background for" ile baslamayan ve
     "Bounds for" icermeyen satirlar.
  2. Bilinen paket/namespace token'larindan biriyle eslesenler tercih edilir
     (io.github.fuzun45.tvmirror, tvmirror, io.github.jqssun.airplay, airplay).
  3. Eslesme yoksa ve odak ipucu (mCurrentFocus vb.) verildiyse, ipucundaki
     paket/activity token'lariyla eslesenler tercih edilir.
  4. Hala eslesme yoksa ve tek bir SurfaceView adayi varsa o secilir.
  5. Birden fazla eslesme varsa (BLAST) iceren tercih edilir, sonra en yuksek
     sondaki "#<sayi>" (en yeni katman) secilir.

Kullanim:
    layer_select.py [--focus "<mCurrentFocus/mFocusedApp metni>"] < list.txt

Cikti: ilk satirda secilen katman adi (bulunamadiysa bos satir), ardindan
tum SurfaceView adaylari icin "# aday: <ad>" satirlari.
"""
import argparse
import re
import sys

APP_TOKENS = (
    "io.github.fuzun45.tvmirror",
    "tvmirror",
    "io.github.jqssun.airplay",
    "airplay",
)

TRAILING_ID_RE = re.compile(r"#(\d+)\s*$")


def _is_surfaceview_candidate(line):
    if "SurfaceView" not in line:
        return False
    stripped = line.strip()
    if stripped.startswith("Background for"):
        return False
    if "Bounds for" in stripped:
        return False
    return True


def list_candidates(list_output):
    """`--list` ciktisindan SurfaceView adaylarini (Background/Bounds haric) dondurur."""
    candidates = []
    for ln in list_output.splitlines():
        stripped = ln.strip()
        if not stripped:
            continue
        if _is_surfaceview_candidate(stripped):
            candidates.append(stripped)
    return candidates


def _matches_any_token(name, tokens):
    lname = name.lower()
    return any(tok.lower() in lname for tok in tokens)


def _focus_tokens(focus_hint):
    """mCurrentFocus/mFocusedApp metninden paket/activity token'larini cikarir.

    Ornek: 'mCurrentFocus=Window{abc u0 io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity}'
    -> ['io.github.fuzun45.tvmirror', 'io.github.jqssun.airplay.MainActivity',
        'io.github.jqssun.airplay', 'MainActivity']
    """
    if not focus_hint:
        return []
    tokens = []
    # "pkg/activity" bicimindeki parcalari yakala
    for m in re.finditer(r"([A-Za-z0-9_.]+)/([A-Za-z0-9_.]+)", focus_hint):
        pkg, act = m.group(1), m.group(2)
        tokens.append(pkg)
        if act.startswith("."):
            act = pkg + act
        tokens.append(act)
        # activity'nin son sinif adi (paket olmadan) da ise yarayabilir
        tokens.append(act.rsplit(".", 1)[-1])
    return [t for t in tokens if t]


def _prefer_blast_and_newest(candidates):
    if not candidates:
        return None
    blast = [c for c in candidates if "(BLAST)" in c]
    pool = blast if blast else candidates

    def sort_key(name):
        m = TRAILING_ID_RE.search(name)
        return int(m.group(1)) if m else -1

    pool_sorted = sorted(pool, key=sort_key, reverse=True)
    return pool_sorted[0]


def app_token_candidates(list_output):
    """Yalnizca bilinen paket/namespace token'lariyla eslesen SurfaceView adaylari.

    Odak ipucu veya "tek aday" fallback'ini kullanmaz; 60-soak.sh'nin stale-layer
    kontrolu gibi "bizim uygulamamiza ait bir katman kaldi mi" sorusu icin
    kullanilir (fallback baska bir uygulamanin SurfaceView'ini secebilir).
    """
    candidates = list_candidates(list_output)
    return [c for c in candidates if _matches_any_token(c, APP_TOKENS)]


def pick_video_layer(list_output, focus_hint=None):
    """Video icin kullanilan SurfaceView katmanini secer.

    Donen: (secilen_katman_adi_veya_None, tum_SurfaceView_adaylari)
    """
    candidates = list_candidates(list_output)
    if not candidates:
        return None, []

    app_matches = [c for c in candidates if _matches_any_token(c, APP_TOKENS)]
    if app_matches:
        return _prefer_blast_and_newest(app_matches), candidates

    focus_tokens = _focus_tokens(focus_hint)
    if focus_tokens:
        focus_matches = [c for c in candidates if _matches_any_token(c, focus_tokens)]
        if focus_matches:
            return _prefer_blast_and_newest(focus_matches), candidates

    if len(candidates) == 1:
        return candidates[0], candidates

    return None, candidates


def layer_matches(name, chosen):
    """Iki katman adini (bosluklari trimleyerek) tam esitlikle karsilastirir."""
    if name is None or chosen is None:
        return False
    return name.strip() == chosen.strip()


def main():
    ap = argparse.ArgumentParser(description="Video SurfaceView katmanini secer")
    ap.add_argument(
        "--focus",
        default=None,
        help="mCurrentFocus/mFocusedApp metni (odak ipucu icin)",
    )
    ap.add_argument(
        "--app-only",
        action="store_true",
        help="Sadece bilinen paket/namespace token'lariyla eslesen adaylari listele "
             "(odak ipucu/tek-aday fallback'i kullanma; stale-layer kontrolu icin)",
    )
    args = ap.parse_args()

    list_output = sys.stdin.read()

    if args.app_only:
        candidates = app_token_candidates(list_output)
        chosen = _prefer_blast_and_newest(candidates)
    else:
        chosen, candidates = pick_video_layer(list_output, args.focus)

    print(chosen if chosen else "")
    for c in candidates:
        print(f"# aday: {c}")


if __name__ == "__main__":
    main()
