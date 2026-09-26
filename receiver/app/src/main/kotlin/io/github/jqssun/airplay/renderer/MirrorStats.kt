package io.github.jqssun.airplay.renderer

import android.util.Log
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

// measurement-only: once-per-second logcat line comparing requested -> received -> decoded ->
// presented, plus session start/end summaries. no behavior change; disable via ENABLED.
object MirrorStats {
    const val ENABLED = true

    private const val TAG = "TvMirrorStats"
    private const val EMIT_INTERVAL_MS = 1000L

    // requested display size/fps advertised to the sender (nativeSetDisplaySize)
    @Volatile private var reqW = 0
    @Volatile private var reqH = 0
    @Volatile private var reqFps = 0

    // received stream size as reported by the sender (onVideoSize / _video_report_size)
    @Volatile private var recvW = 0
    @Volatile private var recvH = 0

    @Volatile private var codecLabel = ""
    @Volatile private var decoderName = ""
    @Volatile private var audioLabel = "none"
    @Volatile private var outputLabel = "none"

    private val framesIn = AtomicLong(0)
    private val framesOut = AtomicLong(0)
    private val dropped = AtomicLong(0)

    @Volatile private var sessionActive = false
    private var sessionStartNs = 0L
    private var sessionFramesInBase = 0L
    private var sessionFramesOutBase = 0L
    private var sessionDroppedBase = 0L

    private var lastEmitMs = 0L
    private var lastFramesIn = 0L
    private var lastFramesOut = 0L

    fun setRequested(w: Int, h: Int, fps: Int) {
        if (!ENABLED) return
        reqW = w; reqH = h; reqFps = fps
    }

    fun setReceived(w: Int, h: Int) {
        if (!ENABLED) return
        recvW = w; recvH = h
    }

    // codec output path: "direct" (display surface) or "gl" (pipeline sink)
    fun setOutput(label: String) {
        if (!ENABLED) return
        outputLabel = label
    }

    fun setAudio(label: String) {
        if (!ENABLED) return
        audioLabel = label
    }

    // codec created / (re)started
    fun onSessionStart(h265: Boolean, decoder: String) {
        if (!ENABLED) return
        codecLabel = if (h265) "H.265" else "H.264"
        decoderName = decoder
        sessionFramesInBase = framesIn.get()
        sessionFramesOutBase = framesOut.get()
        sessionDroppedBase = dropped.get()
        sessionStartNs = System.nanoTime()
        lastEmitMs = 0L
        lastFramesIn = sessionFramesInBase
        lastFramesOut = sessionFramesOutBase
        sessionActive = true
        Log.i(TAG, "session start req=${reqW}x${reqH}@$reqFps codec=$codecLabel decoder=$decoderName")
    }

    // codec stopped / released
    fun onSessionEnd() {
        if (!ENABLED || !sessionActive) return
        sessionActive = false
        val framesInCount = framesIn.get() - sessionFramesInBase
        val framesOutCount = framesOut.get() - sessionFramesOutBase
        val droppedCount = dropped.get() - sessionDroppedBase
        val durationS = ((System.nanoTime() - sessionStartNs) / 1_000_000_000L).toInt()
        Log.i(TAG, "session end frames_in=$framesInCount frames_out=$framesOutCount " +
            "dropped=$droppedCount duration_s=$durationS")
    }

    // a compressed access unit was queued into the decoder (queueInputBuffer)
    fun onFrameIn() {
        if (!ENABLED) return
        framesIn.incrementAndGet()
    }

    // a decoded output buffer was released for rendering (releaseOutputBuffer)
    fun onFrameOut() {
        if (!ENABLED) return
        framesOut.incrementAndGet()
        _maybeEmit()
    }

    // a received frame was discarded before decode, or a queued input buffer was dropped
    fun onDropped() {
        if (!ENABLED) return
        dropped.incrementAndGet()
    }

    private fun _maybeEmit() {
        val now = System.currentTimeMillis()
        if (lastEmitMs == 0L) {
            lastEmitMs = now
            return
        }
        val elapsedMs = now - lastEmitMs
        if (elapsedMs < EMIT_INTERVAL_MS) return
        val elapsedS = elapsedMs / 1000.0
        val fIn = framesIn.get()
        val fOut = framesOut.get()
        val inFps = (fIn - lastFramesIn) / elapsedS
        val decFps = (fOut - lastFramesOut) / elapsedS
        lastFramesIn = fIn
        lastFramesOut = fOut
        lastEmitMs = now
        Log.i(TAG, "req=${reqW}x${reqH}@$reqFps recv=${recvW}x${recvH} codec=$codecLabel " +
            "decoder=$decoderName in_fps=${String.format(Locale.US, "%.1f", inFps)} " +
            "dec_fps=${String.format(Locale.US, "%.1f", decFps)} dropped=${dropped.get()} audio=$audioLabel " +
            "out=$outputLabel")
    }
}
