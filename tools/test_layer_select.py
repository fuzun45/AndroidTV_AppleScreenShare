#!/usr/bin/env python3
"""tools/test_layer_select.py - layer_select.py secim mantigi icin unittest'ler."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import layer_select  # noqa: E402


class TestPickVideoLayer(unittest.TestCase):
    def test_tvmirror_name_matches_directly(self):
        listing = (
            "Layer 0x1 (SomeOtherLayer)\n"
            "Layer 0x2 (SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity]@0(BLAST)#123)\n"
        )
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertIn("tvmirror", chosen)
        self.assertEqual(len(candidates), 1)

    def test_namespace_only_name_matches_via_airplay_token(self):
        listing = "SurfaceView[io.github.jqssun.airplay.MainActivity]@0(BLAST)#88\n"
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertEqual(chosen, "SurfaceView[io.github.jqssun.airplay.MainActivity]@0(BLAST)#88")
        self.assertEqual(candidates, [chosen])

    def test_background_for_layers_excluded(self):
        listing = (
            "Background for SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity]@0#124\n"
            "SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity]@0(BLAST)#123\n"
        )
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertEqual(len(candidates), 1)
        self.assertTrue(chosen.startswith("SurfaceView"))
        self.assertNotIn("Background for", chosen)

    def test_bounds_for_lines_excluded(self):
        listing = (
            "Bounds for SurfaceView[io.github.fuzun45.tvmirror/x]@0#10\n"
            "SurfaceView[io.github.fuzun45.tvmirror/x]@0(BLAST)#11\n"
        )
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertEqual(len(candidates), 1)
        self.assertIn("(BLAST)", chosen)

    def test_multiple_matches_prefer_blast_then_highest_id(self):
        listing = (
            "SurfaceView[io.github.fuzun45.tvmirror/x]@0#100\n"
            "SurfaceView[io.github.fuzun45.tvmirror/x]@0(BLAST)#50\n"
            "SurfaceView[io.github.fuzun45.tvmirror/x]@0(BLAST)#200\n"
        )
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertEqual(len(candidates), 3)
        self.assertTrue(chosen.endswith("#200"))
        self.assertIn("(BLAST)", chosen)

    def test_focus_hint_fallback_with_generic_name(self):
        listing = (
            "SurfaceView[MainActivity](BLAST)#12\n"
            "SurfaceView[SomeOtherApp](BLAST)#13\n"
        )
        focus = (
            "mCurrentFocus=Window{abc u0 "
            "io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity}"
        )
        chosen, candidates = layer_select.pick_video_layer(listing, focus_hint=focus)
        self.assertEqual(chosen, "SurfaceView[MainActivity](BLAST)#12")
        self.assertEqual(len(candidates), 2)

    def test_single_candidate_fallback(self):
        listing = "SurfaceView[com.other.app/.MainActivity](BLAST)#5\n"
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertEqual(chosen, "SurfaceView[com.other.app/.MainActivity](BLAST)#5")
        self.assertEqual(candidates, [chosen])

    def test_no_candidates(self):
        listing = "Layer 0x1 (SomeOtherLayer)\nLayer 0x2 (AnotherLayer)\n"
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertIsNone(chosen)
        self.assertEqual(candidates, [])

    def test_multiple_candidates_no_match_no_focus_returns_none(self):
        listing = (
            "SurfaceView[com.other.app/.MainActivity](BLAST)#5\n"
            "SurfaceView[com.another.app/.MainActivity](BLAST)#6\n"
        )
        chosen, candidates = layer_select.pick_video_layer(listing)
        self.assertIsNone(chosen)
        self.assertEqual(len(candidates), 2)


class TestAppTokenCandidates(unittest.TestCase):
    def test_only_app_matches_returned_ignores_fallback(self):
        listing = "SurfaceView[com.other.app/.MainActivity](BLAST)#5\n"
        self.assertEqual(layer_select.app_token_candidates(listing), [])

    def test_app_match_returned(self):
        listing = (
            "SurfaceView[com.other.app/.MainActivity](BLAST)#5\n"
            "SurfaceView[io.github.fuzun45.tvmirror/x]@0(BLAST)#6\n"
        )
        self.assertEqual(
            layer_select.app_token_candidates(listing),
            ["SurfaceView[io.github.fuzun45.tvmirror/x]@0(BLAST)#6"],
        )


class TestLayerMatches(unittest.TestCase):
    def test_exact_match(self):
        self.assertTrue(layer_select.layer_matches("foo#1", "foo#1"))

    def test_whitespace_trimmed(self):
        self.assertTrue(layer_select.layer_matches("  foo#1 \n", "foo#1"))

    def test_mismatch(self):
        self.assertFalse(layer_select.layer_matches("foo#1", "foo#2"))

    def test_none_values(self):
        self.assertFalse(layer_select.layer_matches(None, "foo#1"))
        self.assertFalse(layer_select.layer_matches("foo#1", None))


if __name__ == "__main__":
    unittest.main()
