#!/usr/bin/env python3
"""tools/test_leak_trend.py - leak_trend.py icin unittest'ler (stdlib-only)."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import leak_trend  # noqa: E402


HEADER = (
    "ts\tphase\tpid\tpss_total_kb\tjava_heap_kb\tnative_heap_kb\tgraphics_kb\t"
    "threads\tfds\tcodecs\tsf_layers\tsys_mem_available_kb\tswap_free_kb\t"
    "pswpin\tpswpout\tlmk_kills_total\tmirroring\trestart"
)


def _row(
    ts,
    pid=1000,
    pss=50000,
    java=10000,
    native=8000,
    graphics=5000,
    threads=20,
    fds=40,
    codecs=0,
    sf_layers=1,
    mem_avail=500000,
    swap_free=0,
    pswpin=0,
    pswpout=0,
    lmk=0,
    mirroring=1,
    restart=0,
):
    fields = [
        ts,
        "run",
        pid,
        pss,
        java,
        native,
        graphics,
        threads,
        fds,
        codecs,
        sf_layers,
        mem_avail,
        swap_free,
        pswpin,
        pswpout,
        lmk,
        mirroring,
        restart,
    ]
    return "\t".join("NA" if v is None else str(v) for v in fields)


def write_tsv(rows):
    fh = tempfile.NamedTemporaryFile(mode="w", suffix=".tsv", delete=False, newline="")
    fh.write(HEADER + "\n")
    for r in rows:
        fh.write(r + "\n")
    fh.close()
    return fh.name


class TestParseTsv(unittest.TestCase):
    def test_parses_numeric_and_na(self):
        rows = [_row(0, pss=50000), _row(60, pss=None)]
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            self.assertEqual(len(parsed), 2)
            self.assertEqual(parsed[0]["pss_total_kb"], 50000)
            self.assertIsNone(parsed[1]["pss_total_kb"])
            self.assertEqual(parsed[0]["phase"], "run")
        finally:
            os.unlink(path)


class TestWarmupCutoff(unittest.TestCase):
    def test_min_one_sample(self):
        self.assertEqual(leak_trend.warmup_cutoff(1), 0)
        self.assertEqual(leak_trend.warmup_cutoff(5), 1)
        self.assertEqual(leak_trend.warmup_cutoff(100), 10)


class TestFlatSeriesPasses(unittest.TestCase):
    def test_flat_pss_is_pass(self):
        rows = []
        for i in range(20):
            rows.append(_row(i * 60, pss=50000, native=8000, graphics=5000, threads=20))
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            self.assertTrue(analysis["overall_pass"], analysis["verdicts"])
            self.assertEqual(analysis["verdicts"], [])
        finally:
            os.unlink(path)


class TestLinearGrowthFlagged(unittest.TestCase):
    def test_20mb_per_hour_growth_is_flagged(self):
        # 20 MB/saat = 20*1024 KB / 3600 sn -> saniyede artis
        kb_per_sec = (20 * 1024.0) / 3600.0
        rows = []
        n = 60
        interval_s = 60
        for i in range(n):
            ts = i * interval_s
            pss = int(50000 + kb_per_sec * ts)
            rows.append(_row(ts, pss=pss, native=8000, graphics=5000, threads=20))
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            self.assertFalse(analysis["overall_pass"])
            joined = " ".join(analysis["verdicts"])
            self.assertIn("SIZINTI SUPHESI", joined)
            slope = analysis["metrics"]["pss_total_kb"]["slope_per_hour"]
            self.assertIsNotNone(slope)
            self.assertGreater(slope, 8 * 1024.0)
        finally:
            os.unlink(path)


class TestIdleCodecLeakFlagged(unittest.TestCase):
    def test_codec_present_while_idle_is_flagged(self):
        rows = []
        for i in range(10):
            rows.append(_row(i * 60, mirroring=0, codecs=1))
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            self.assertFalse(analysis["overall_pass"])
            joined = " ".join(analysis["verdicts"])
            self.assertIn("BIRAKILMAYAN CODEC", joined)
            self.assertEqual(analysis["idle_codec_samples"], 10)
        finally:
            os.unlink(path)

    def test_codec_present_while_mirroring_is_not_flagged_for_codec(self):
        rows = []
        for i in range(10):
            rows.append(_row(i * 60, mirroring=1, codecs=1, pss=50000, native=8000, graphics=5000))
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            joined = " ".join(analysis["verdicts"])
            self.assertNotIn("BIRAKILMAYAN CODEC", joined)
        finally:
            os.unlink(path)


class TestNAHandling(unittest.TestCase):
    def test_all_na_metric_yields_no_slope_but_no_crash(self):
        rows = [_row(0, pss=None), _row(60, pss=None), _row(120, pss=None)]
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            m = analysis["metrics"]["pss_total_kb"]
            self.assertIsNone(m["slope_per_hour"])
            self.assertIsNone(m["start"])
            self.assertIsNone(m["max"])
        finally:
            os.unlink(path)

    def test_mixed_na_still_computes_from_valid_points(self):
        rows = [
            _row(0, pss=50000),
            _row(60, pss=None),
            _row(120, pss=50000),
            _row(180, pss=None),
        ]
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            m = analysis["metrics"]["pss_total_kb"]
            self.assertEqual(m["min"], 50000)
            self.assertEqual(m["max"], 50000)
        finally:
            os.unlink(path)


class TestRestartsAndLmk(unittest.TestCase):
    def test_restart_flag_counted_and_flagged(self):
        rows = [
            _row(0, pid=1000),
            _row(60, pid=1001, restart=1),
            _row(120, pid=1001),
        ]
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            self.assertEqual(analysis["restarts"], 1)
            self.assertFalse(analysis["overall_pass"])
        finally:
            os.unlink(path)

    def test_lmk_delta_flags(self):
        rows = [_row(0, lmk=0), _row(60, lmk=0), _row(120, lmk=2)]
        path = write_tsv(rows)
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            self.assertEqual(analysis["lmk_delta"], 2)
            self.assertFalse(analysis["overall_pass"])
        finally:
            os.unlink(path)


class TestEmptyInput(unittest.TestCase):
    def test_shifted_row_with_embedded_tab_is_skipped(self):
        # Eski 65-leak-watch "Threads:\t30" yaziyordu: fazladan sekme sutunlari
        # kaydirip PID degisimi / LMK / MemAvailable'i yanlis okutuyordu.
        good = [_row(i * 60, pss=40000, native=7000, graphics=6000, threads=30) for i in range(10)]
        bad = _row(700, pss=40000, native=7000, graphics=6000, threads=30).replace("\t30\t", "\tThreads:\t30\t", 1)
        path = write_tsv(good + [bad])
        try:
            rows = leak_trend.parse_tsv(path)
            self.assertEqual(len(rows), 10)
            self.assertEqual(leak_trend.SKIPPED_ROWS, 1)
            analysis = leak_trend.analyze(rows)
            self.assertEqual(analysis["restarts"], 0)
            self.assertIn("1 satir atlandi", leak_trend.render_markdown(analysis))
        finally:
            os.unlink(path)

    def test_empty_file(self):
        path = write_tsv([])
        try:
            parsed = leak_trend.parse_tsv(path)
            analysis = leak_trend.analyze(parsed)
            self.assertFalse(analysis["overall_pass"])
            md = leak_trend.render_markdown(analysis)
            self.assertIn("SUPHELI", md)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
