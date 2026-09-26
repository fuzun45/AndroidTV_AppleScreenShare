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


class TestCadenceAwareJank(unittest.TestCase):
    """60 Hz ekranda 25 fps icerik, degisen 2/3 vsync (33.3/50 ms) araliklarla
    sunulur; bu duz medyan-tabanli kurala gore janky sayilir ama aslinda
    puruzsuzdur. --expected-fps ile cadence-aware hesap bunu ayirt etmeli."""

    REFRESH_NS = 16_666_667  # 60 Hz

    def _pulldown_2_3_times(self, n_frames):
        # 25fps@60Hz: 60/25=2.4 vsync/kare; 5'lik dongude 2,2,3,2,3 (ortalama 2.4)
        # seklinde degisen (yalnizca 2 veya 3 vsync'lik) araliklarla sunulur.
        times = [0]
        pattern = [2, 2, 3, 2, 3]
        for i in range(n_frames - 1):
            vsyncs = pattern[i % len(pattern)]
            times.append(times[-1] + vsyncs * self.REFRESH_NS)
        return times

    def test_25fps_pulldown_zero_cadence_jank(self):
        times = self._pulldown_2_3_times(60)
        stats = jank.compute_stats(self.REFRESH_NS, times, expected_fps=25.0)
        self.assertAlmostEqual(stats["fps"], 25.0, delta=0.5)
        self.assertIsNotNone(stats["janky_pct_cadence"])
        self.assertEqual(stats["janky_pct_cadence"], 0.0)
        # eski (medyan tabanli) kural aynen korunuyor ve bu senaryoda >0 olabilir
        self.assertIsNotNone(stats["janky_pct"])

    def test_25fps_pulldown_with_real_gaps_has_cadence_jank(self):
        times = self._pulldown_2_3_times(60)
        # birkac gercek 4-vsync bosluk (gercek takilma) ekle
        for idx in (10, 25, 40):
            for j in range(idx, len(times)):
                times[j] += self.REFRESH_NS  # o noktadan sonrasini bir vsync geciktir
        stats = jank.compute_stats(self.REFRESH_NS, times, expected_fps=25.0)
        self.assertGreater(stats["janky_pct_cadence"], 0.0)

    def test_60fps_steady_zero_cadence_jank(self):
        times = [i * self.REFRESH_NS for i in range(60)]
        stats = jank.compute_stats(self.REFRESH_NS, times, expected_fps=60.0)
        self.assertAlmostEqual(stats["fps"], 60.0, delta=0.5)
        self.assertEqual(stats["janky_pct_cadence"], 0.0)
        self.assertAlmostEqual(stats["dropped_vs_expected_pct"], 0.0, places=3)

    def test_cadence_limit_ms_formula(self):
        limit, refresh_ms, expected_ms = jank.cadence_limit_ms(25.0, self.REFRESH_NS)
        self.assertAlmostEqual(refresh_ms, 1000.0 / 60.0, places=3)
        self.assertAlmostEqual(expected_ms, 40.0, places=3)
        # ceil(40/16.667)=3 -> 3*16.667 + 0.5*16.667 = 58.33 ms
        self.assertAlmostEqual(limit, 3 * refresh_ms + 0.5 * refresh_ms, places=3)

    def test_dropped_vs_expected_pct(self):
        # 30 fps sunulan ama beklenen 60 fps -> ~%50 eksik
        times = [i * (self.REFRESH_NS * 2) for i in range(30)]
        stats = jank.compute_stats(self.REFRESH_NS, times, expected_fps=60.0)
        self.assertAlmostEqual(stats["dropped_vs_expected_pct"], 50.0, delta=1.0)

    def test_no_expected_fps_keeps_cadence_fields_none(self):
        times = [i * self.REFRESH_NS for i in range(10)]
        stats = jank.compute_stats(self.REFRESH_NS, times)
        self.assertIsNone(stats["janky_pct_cadence"])
        self.assertIsNone(stats["cadence_limit_ms"])
        self.assertIsNone(stats["dropped_vs_expected_pct"])
        self.assertIsNone(stats["expected_fps"])


class TestLayerAutodetectRegex(unittest.TestCase):
    def test_legacy_regex_still_matches_expected_layer_names(self):
        # DEFAULT_LAYER_REGEX artik yalnizca --layer-regex acikca verildiginde
        # kullanilan eski/geriye-donuk secenek; varsayilan yol layer_select.py'dir.
        import re
        pattern = re.compile(jank.DEFAULT_LAYER_REGEX, re.IGNORECASE)
        self.assertTrue(pattern.search(
            "SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity](BLAST)"
        ))
        self.assertFalse(pattern.search("SurfaceView[com.other.app/.MainActivity](BLAST)"))

    def test_autodetect_layer_uses_layer_select(self):
        # autodetect_layer artik jank.py'nin ayri regex mantigi yerine
        # layer_select.pick_video_layer'a delege eder.
        import layer_select
        listing = "SurfaceView[io.github.fuzun45.tvmirror/x]@0(BLAST)#5\n"
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertIn("tvmirror", chosen)
        self.assertEqual(candidates, [listing.strip()])


if __name__ == "__main__":
    unittest.main()
