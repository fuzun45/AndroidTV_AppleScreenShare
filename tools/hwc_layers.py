#!/usr/bin/env python3
"""dumpsys SurfaceFlinger çıktısından HWC katmanlarının kompozisyon tipini çıkarır.

İki biçimi okur:
  - Android 12+ tablo:  katman adı bir satırda, altındaki satırda "| ... | DEVICE | ..." sütunları
  - eski/özet biçim:     "<ad> ... Comp Type = DEVICE"

Çıktı: her katman için "<TIP>\\t<ad>" satırı (yalnızca ilk ekranın HWC bölümü).
Kullanım: hwc_layers.py < sf.txt
"""
import re
import sys

INLINE = re.compile(r"^\s*(?P<name>\S.*?)\s+Comp Type\s*=\s*(?P<type>[A-Z_]+)")
TYPES = {"DEVICE", "CLIENT", "SOLID_COLOR", "CURSOR", "SIDEBAND", "DISPLAY_DECORATION",
         "REFRESH_RATE_INDICATOR", "INVALID"}


def parse(text):
    out = []
    lines = text.splitlines()
    comp_col = None
    in_table = False
    pending = None
    for line in lines:
        m = INLINE.match(line)
        if m and m.group("type") in TYPES:
            out.append((m.group("type"), m.group("name").strip()))
            continue
        if "|" in line and "Comp Type" in line:
            cols = [c.strip() for c in line.split("|")]
            comp_col = next(i for i, c in enumerate(cols) if "Comp Type" in c)
            in_table = True
            pending = None
            continue
        if not in_table:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("---"):
            if not stripped and out:
                in_table = False  # tablo bitti (ilk ekranla yetin)
            continue
        if "|" in line:
            cols = [c.strip() for c in line.split("|")]
            if pending and comp_col is not None and comp_col < len(cols) and cols[comp_col] in TYPES:
                out.append((cols[comp_col], pending))
            pending = None
        else:
            pending = stripped
    return out


def main():
    for t, name in parse(sys.stdin.read()):
        print(f"{t}\t{name}")


if __name__ == "__main__":
    main()
