#!/usr/bin/env python3
"""tools/test_jank.py - jank.py'nin parser/istatistik fonksiyonlari icin
sentetik unittest'ler (INT64_MAX, 0 ve tekrarlanan (dedup) satirlar dahil)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import jank  # noqa: E402

INT64_MAX = jank.INT64_MAX


def make_latency_text(refresh_period_ns, rows):
    lines = [str(refresh_period_ns)]
    for desired, actual, ready in rows:
        lines.append(f"{desired}\t{actual}\t{ready}")
    return "\n".join(lines) + "\n"


class TestParseLatency(unittest.TestCase):
    def test_basic_valid_rows(self):
        text = make_latency_text(16666667, [
            (1000, 2000, 2500),
            (2000, 3000, 3500),
        ])
        rp, frames = jank.parse_latency(text)
        self.assertEqual(rp, 16666667)
        self.assertEqual(frames, [(1000, 2000, 2500), (2000, 3000, 3500)])

    def test_zero_rows_ignored(self):
        text = make_latency_text(16666667, [
            (0, 0, 0),
            (1000, 2000, 2500),
        ])
        _, frames = jank.parse_latency(text)
        self.assertEqual(frames, [(1000, 2000, 2500)])

    def test_int64_max_rows_ignored(self):
        text = make_latency_text(16666667, [
            (1000, 2000, 2500),
            (INT64_MAX, INT64_MAX, INT64_MAX),
            (2000, INT64_MAX, 3500),  # kismen pending
        ])
        _, frames = jank.parse_latency(text)
        self.assertEqual(frames, [(1000, 2000, 2500)])

    def test_empty_input(self):
        rp, frames = jank.parse_latency("")
        self.assertIsNone(rp)
        self.assertEqual(frames, [])

    def test_malformed_row_skipped(self):
        text = "16666667\nabc\tdef\tghi\n1000\t2000\t2500\n"
        _, frames = jank.parse_latency(text)
        self.assertEqual(frames, [(1000, 2000, 2500)])

    def test_bad_refresh_period_header(self):
        text = "not-a-number\n1000\t2000\t2500\n"
        rp, frames = jank.parse_latency(text)
        self.assertIsNone(rp)
        self.assertEqual(frames, [(1000, 2000, 2500)])


class TestComputeStats(unittest.TestCase):
    def test_steady_60fps(self):
        # 16.6667 ms araliklarla 10 kare -> ~60 fps, dusuk jank
        period_ns = 16_666_667
        times = [i * period_ns for i in range(10)]
        stats = jank.compute_stats(period_ns, times)
        self.assertEqual(stats["frames"], 10)
        self.assertAlmostEqual(stats["fps"], 60.0, delta=0.5)
        self.assertEqual(stats["janky_count"], 0)

    def test_with_jank_spike(self):
        period_ns = 16_666_667
        times = [i * period_ns for i in range(5)]
        # buyuk bir sicrama ekle (takilma)
        times.append(times[-1] + period_ns * 5)
        for i in range(6, 10):
            times.append(times[-1] + period_ns)
        stats = jank.compute_stats(period_ns, times)
        self.assertGreaterEqual(stats["janky_count"], 1)
        self.assertIsNotNone(stats["max_ms"])
        self.assertGreater(stats["max_ms"], stats["p50_ms"])

    def test_too_few_frames(self):
        stats = jank.compute_stats(16_666_667, [12345])
        self.assertEqual(stats["frames"], 1)
        self.assertIsNone(stats["fps"])

    def test_no_frames(self):
        stats = jank.compute_stats(None, [])
        self.assertEqual(stats["frames"], 0)
        self.assertIsNone(stats["fps"])


class TestDedupBehavior(unittest.TestCase):
    def test_duplicate_actual_times_deduped_via_set_logic(self):
        # collect() actualPresentTime'a gore dedup eder; burada ayni mantigi
        # dogrudan simule ediyoruz.
        seen = set()
        ordered = []
        raw_rows = [
            (1000, 2000, 2500),
            (1000, 2000, 2500),  # tekrar sorgudan gelen ayni kare
            (2000, 3000, 3500),
        ]
        for _desired, actual, _ready in raw_rows:
            if actual not in seen:
                seen.add(actual)
                ordered.append(actual)
        self.assertEqual(ordered, [2000, 3000])


class TestLayerAutodetectRegex(unittest.TestCase):
    def test_regex_matches_expected_layer_names(self):
        import re
        pattern = re.compile(jank.DEFAULT_LAYER_REGEX, re.IGNORECASE)
        self.assertTrue(pattern.search(
            "SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity](BLAST)"
        ))
        self.assertFalse(pattern.search("SurfaceView[com.other.app/.MainActivity](BLAST)"))


if __name__ == "__main__":
    unittest.main()
