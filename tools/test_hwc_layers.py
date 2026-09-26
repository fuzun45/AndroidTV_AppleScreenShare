import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from hwc_layers import parse  # noqa: E402

TABLE = """Display 0 (active) HWC layers:
---------------------------------------------------------------------------------------------------------------------------------------------------------------
 Layer name
           Z |  Window Type |  Comp Type |  Transform |   Disp Frame (LTRB) |          Source Crop (LTRB) |     Frame Rate (Explicit) (Seamlessness) [Focused]
---------------------------------------------------------------------------------------------------------------------------------------------------------------
 SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity](BLAST)#512
  rel     -2 |            1 |     DEVICE |          0 |    0    0 3840 2160 |    0.0    0.0 1920.0 1080.0 |                                              [ ]
---------------------------------------------------------------------------------------------------------------------------------------------------------------
 io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity#508
  rel      0 |            1 |     CLIENT |          0 |    0    0 3840 2160 |    0.0    0.0 1920.0 1080.0 |                                              [*]
---------------------------------------------------------------------------------------------------------------------------------------------------------------

Display 1 HWC layers:
"""

INLINE = """SurfaceView[...youtube...](BLAST)#54416   Comp Type = DEVICE   Disp Frame 0 0 3840 2160
com.google.android.youtube.tv/...#54413   Comp Type = CLIENT
"""


class T(unittest.TestCase):
    def test_table(self):
        r = parse(TABLE)
        self.assertEqual(r[0][0], "DEVICE")
        self.assertIn("SurfaceView[io.github.fuzun45.tvmirror", r[0][1])
        self.assertEqual(r[1][0], "CLIENT")
        self.assertEqual(len(r), 2)

    def test_inline(self):
        r = parse(INLINE)
        self.assertEqual(r, [("DEVICE", "SurfaceView[...youtube...](BLAST)#54416"),
                             ("CLIENT", "com.google.android.youtube.tv/...#54413")])

    def test_empty(self):
        self.assertEqual(parse("nothing here"), [])


if __name__ == "__main__":
    unittest.main()
