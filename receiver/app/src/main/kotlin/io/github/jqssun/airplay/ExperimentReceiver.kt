package io.github.jqssun.airplay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

// diagnostic switches for on-device A/B measurements; reachable only via adb (DUMP permission)
// and held in memory for the process lifetime, so a restart always returns to defaults
object Experiments {
    const val ACTION = "io.github.fuzun45.tvmirror.EXPERIMENT"

    // rewrite the H.264 SPS to limited range (HWC video-plane test); shifts colours slightly
    @Volatile var limitedRange = false
}

class ExperimentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Experiments.ACTION) return
        intent.getStringExtra("range")?.let { Experiments.limitedRange = it == "limited" }
        Log.i(TAG, "experiments: limitedRange=${Experiments.limitedRange} (applies from next keyframe)")
    }

    companion object {
        private const val TAG = "TvMirrorExperiment"
    }
}
