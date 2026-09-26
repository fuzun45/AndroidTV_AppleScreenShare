package io.github.jqssun.airplay.renderer

import java.io.ByteArrayOutputStream

// experiment: clears the H.264 SPS VUI video_full_range_flag so the decoder tags its output as
// limited range. Apple mirroring is full range; the MTK HWC accepts limited-range video layers
object SpsRange {

    // returns a new Annex-B buffer if an SPS was rewritten, otherwise the same array
    fun limitH264(data: ByteArray): ByteArray {
        val nals = _nalRanges(data)
        if (nals.none { (s, _) -> (data[s].toInt() and 0x1F) == NAL_SPS }) return data
        var changed = false
        val out = ByteArrayOutputStream(data.size + 8)
        var copied = 0
        for ((start, end) in nals) {
            if ((data[start].toInt() and 0x1F) != NAL_SPS) continue
            val rbsp = unescape(data, start, end)
            val bit = fullRangeBit(rbsp) ?: continue
            val byteIdx = bit / 8
            val mask = 0x80 ushr (bit % 8)
            if (rbsp[byteIdx].toInt() and mask == 0) continue
            rbsp[byteIdx] = (rbsp[byteIdx].toInt() and mask.inv()).toByte()
            out.write(data, copied, start - copied)
            val esc = escape(rbsp)
            out.write(esc, 0, esc.size)
            copied = end
            changed = true
        }
        if (!changed) return data
        out.write(data, copied, data.size - copied)
        return out.toByteArray()
    }

    // [start, end) of each NAL unit (header byte included, start code excluded)
    internal fun _nalRanges(d: ByteArray): List<Pair<Int, Int>> {
        val starts = ArrayList<Int>()
        var i = 0
        while (i + 2 < d.size) {
            if (d[i].toInt() == 0 && d[i + 1].toInt() == 0 && d[i + 2].toInt() == 1) {
                starts.add(i + 3)
                i += 3
            } else i++
        }
        return starts.mapIndexed { k, s ->
            var e = if (k + 1 < starts.size) starts[k + 1] - 3 else d.size
            // a 4-byte start code leaves one extra zero before the next NAL
            if (k + 1 < starts.size && e > s && d[e - 1].toInt() == 0) e--
            s to e
        }.filter { (s, e) -> e > s }
    }

    internal fun unescape(d: ByteArray, start: Int, end: Int): ByteArray {
        val out = ByteArrayOutputStream(end - start)
        var zeros = 0
        for (i in start until end) {
            val b = d[i].toInt() and 0xFF
            if (zeros >= 2 && b == 3) { zeros = 0; continue }
            out.write(b)
            zeros = if (b == 0) zeros + 1 else 0
        }
        return out.toByteArray()
    }

    internal fun escape(rbsp: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(rbsp.size + 4)
        var zeros = 0
        for (x in rbsp) {
            val b = x.toInt() and 0xFF
            if (zeros >= 2 && b <= 3) { out.write(3); zeros = 0 }
            out.write(b)
            zeros = if (b == 0) zeros + 1 else 0
        }
        return out.toByteArray()
    }

    // bit offset of video_full_range_flag inside the RBSP (header byte at 0), null if absent
    internal fun fullRangeBit(rbsp: ByteArray): Int? = try {
        val r = BitReader(rbsp)
        r.u(8) // nal header
        val profile = r.u(8)
        r.u(8); r.u(8) // constraint flags, level
        r.ue() // sps id
        if (profile in HIGH_PROFILES) {
            val chroma = r.ue()
            if (chroma == 3) r.u(1)
            r.ue(); r.ue() // bit depths
            r.u(1) // qpprime_y_zero_transform_bypass
            if (r.u(1) == 1) {
                for (i in 0 until (if (chroma != 3) 8 else 12)) {
                    if (r.u(1) == 1) _skipScalingList(r, if (i < 6) 16 else 64)
                }
            }
        }
        r.ue() // log2_max_frame_num
        when (r.ue()) {
            0 -> r.ue()
            1 -> {
                r.u(1); r.se(); r.se()
                repeat(r.ue()) { r.se() }
            }
        }
        r.ue(); r.u(1) // max_num_ref_frames, gaps
        r.ue(); r.ue() // width, height in mbs
        if (r.u(1) == 0) r.u(1) // frame_mbs_only, mb_adaptive
        r.u(1) // direct_8x8
        if (r.u(1) == 1) repeat(4) { r.ue() } // cropping
        if (r.u(1) == 0) null else {
            if (r.u(1) == 1 && r.u(8) == 255) { r.u(16); r.u(16) } // aspect ratio
            if (r.u(1) == 1) r.u(1) // overscan
            if (r.u(1) == 0) null else {
                r.u(3) // video_format
                r.pos
            }
        }
    } catch (_: IndexOutOfBoundsException) {
        null
    }

    private fun _skipScalingList(r: BitReader, size: Int) {
        var last = 8
        var next = 8
        repeat(size) {
            if (next != 0) next = (last + r.se() + 256) % 256
            last = if (next == 0) last else next
        }
    }

    internal class BitReader(private val d: ByteArray) {
        var pos = 0; private set

        fun u(n: Int): Int {
            var v = 0
            repeat(n) {
                val b = (d[pos / 8].toInt() ushr (7 - pos % 8)) and 1
                v = (v shl 1) or b
                pos++
            }
            return v
        }

        fun ue(): Int {
            var zeros = 0
            while (u(1) == 0) {
                zeros++
                if (zeros > 31) throw IndexOutOfBoundsException("bad exp-golomb")
            }
            return if (zeros == 0) 0 else (1 shl zeros) - 1 + u(zeros)
        }

        fun se(): Int {
            val k = ue()
            return if (k % 2 == 1) (k + 1) / 2 else -(k / 2)
        }
    }

    private const val NAL_SPS = 7
    private val HIGH_PROFILES = setOf(100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135)
}
