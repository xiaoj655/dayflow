package com.example.life_assistant

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.view.View

/** Xiaomi Watch 5 CLOCK_TICK/Flutter selectionClick plays a ~10s TEXTURE_TICK.
 * Use the supported 13ms TICK primitive; never fall back to that broken preset.
 */
@Suppress("DEPRECATION")
class TouchHaptics(private val context: Context) {
    private val vibrator = context.getSystemService(Vibrator::class.java)
    private val supportsTick by lazy {
        Build.VERSION.SDK_INT >= 31 && vibrator?.arePrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_TICK
        )?.firstOrNull() == true
    }
    private var lastTick = -80L
    private var lastRotaryTick = -80L

    fun rotary(view: View) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastRotaryTick < 80 || !view.isHapticFeedbackEnabled ||
            Settings.System.getInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0 ||
            Build.VERSION.SDK_INT < 34 || !context.resources.configuration.isScreenRound) return
        // Wear's SCROLL_TICK (18) is absent from the public SDK constants.
        // Xiaomi's app list uses this View API; on Watch 5 it plays vendor effect
        // 210 (~50ms), verified from an ordinary app. No CLOCK_TICK fallback.
        if (view.performHapticFeedback(18)) lastRotaryTick = now
    }

    fun selection(view: View) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTick < 80 || !view.isHapticFeedbackEnabled ||
            Settings.System.getInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0 ||
            !supportsTick || Build.VERSION.SDK_INT < 31) return
        val motor = vibrator ?: return
        val effect = VibrationEffect.startComposition()
            .addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, 0.45f)
            .compose()
        if (Build.VERSION.SDK_INT >= 33) {
            motor.vibrate(effect, VibrationAttributes.Builder().setUsage(VibrationAttributes.USAGE_TOUCH).build())
        } else {
            motor.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).build())
        }
        lastTick = now
    }
}
