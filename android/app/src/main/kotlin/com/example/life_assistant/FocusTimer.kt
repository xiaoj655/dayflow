package com.example.life_assistant

import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject

/** The OS alarm and persisted state survive the Flutter engine and screen turning off. */
class FocusTimer(private val context: Context) {
    private val prefs = context.getSharedPreferences("focus_timer_v1", Context.MODE_PRIVATE)
    private val dnd = FocusDnd(context)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val boot: Int get() = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, 0)

    private fun state(): JSONObject? = prefs.getString("state", null)?.let { JSONObject(it) }
    private fun save(value: JSONObject) { check(prefs.edit().putString("state", value.toString()).commit()) }
    private fun records(): JSONArray = JSONArray(prefs.getString("records", "[]"))
    private fun alarmIntent(id: String): PendingIntent = PendingIntent.getBroadcast(
        context, 71, Intent(context, FocusAlarmReceiver::class.java).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    private fun remaining(value: JSONObject): Long {
        if (value.getString("status") != "running") return value.getLong("remainingMillis")
        return if (value.optInt("boot", -1) == boot) {
            (value.getLong("deadlineElapsed") - SystemClock.elapsedRealtime()).coerceAtLeast(0)
        } else (value.getLong("deadlineWall") - System.currentTimeMillis()).coerceAtLeast(0)
    }
    private fun cancel(value: JSONObject) { alarms.cancel(alarmIntent(value.getString("id"))) }
    private fun schedule(value: JSONObject) {
        if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms()) {
            throw SecurityException("请在系统设置中允许闹钟和提醒")
        }
        alarms.setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + remaining(value), alarmIntent(value.getString("id"))
        )
    }
    private fun channels() {
        if (Build.VERSION.SDK_INT >= 26) {
            val progress = NotificationChannel("focus_progress", "正在专注", NotificationManager.IMPORTANCE_LOW)
            progress.setSound(null, null)
            progress.enableVibration(false)
            val end = NotificationChannel("focus_finished", "专注结束", NotificationManager.IMPORTANCE_HIGH)
            end.setSound(null, null)
            end.enableVibration(false) // Exactly two pulses are played by the receiver.
            notifications.createNotificationChannels(listOf(progress, end))
        }
    }
    private fun notify(value: JSONObject, finished: Boolean = false) {
        channels()
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val open = PendingIntent.getActivity(context, 72,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(context, if (finished) "focus_finished" else "focus_progress")
        val rest = value.getString("kind") == "rest"
        builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (finished) { if (rest) "休息结束" else "本次专注完成" } else value.getString("taskTitle"))
            .setContentText(if (finished) value.getString("taskTitle") else if (rest) "休息中" else if (value.getString("status") == "paused") "已暂停" else "专注中")
            .setContentIntent(open).setOngoing(!finished).setAutoCancel(finished)
            .setTimeoutAfter(if (finished) 5000L else 0L)
            .setOnlyAlertOnce(true).setCategory(if (finished) Notification.CATEGORY_ALARM else Notification.CATEGORY_PROGRESS)
        if (!finished && value.getString("status") == "running") {
            builder.setWhen(System.currentTimeMillis() + remaining(value)).setUsesChronometer(true).setChronometerCountDown(true)
        }
        if (!finished && value.getString("status") == "running") {
            OngoingActivity.Builder(context, 73, builder).setStaticIcon(android.R.drawable.ic_lock_idle_alarm).setTouchIntent(open).build().apply(context)
        }
        notifications.notify(73, builder.build())
    }
    private fun record(value: JSONObject, status: String) {
        val existing = records()
        if ((0 until existing.length()).any { existing.getJSONObject(it).getString("id") == value.getString("id") }) return
        val planned = value.getInt("plannedSeconds")
        val actual = if (status == "completed") planned else ((planned * 1000L - remaining(value)) / 1000).toInt().coerceIn(0, planned)
        if (value.getString("kind") == "focus" && actual < 180) return
        existing.put(JSONObject().put("id", value.getString("id"))
            .put("space", value.optString("space", "life")).put("taskId", value.getString("taskId")).put("taskTitle", value.getString("taskTitle"))
            .put("kind", value.getString("kind")).put("plannedSeconds", planned)
            .put("actualSeconds", actual).put("status", status)
            .put("startedAt", value.getLong("startedAt")).put("endedAt", System.currentTimeMillis()))
        check(prefs.edit().putString("records", existing.toString()).commit())
    }
    fun finish(expectedId: String? = null) {
        val value = state() ?: return
        if (value.getString("status") != "running" || (expectedId != null && value.getString("id") != expectedId) || remaining(value) > 0) return
        // Journal the completed session before changing state. ID-based replay is safe.
        record(value, "completed")
        value.put("status", "finished").put("remainingMillis", 0)
        save(value)
        cancel(value)
        dnd.release()
        notify(value, true)
        val vibrator = context.getSystemService(Vibrator::class.java)
        val pattern = longArrayOf(0, 220, 160, 220)
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
        if (Build.VERSION.SDK_INT >= 26) vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1), attributes)
        else vibrator?.vibrate(pattern, -1, attributes)
    }
    fun restoreAfterBoot() {
        val value = state() ?: run { dnd.release(); return }
        if (value.getString("status") != "running") { dnd.release(); return }
        val left = remaining(value)
        value.put("boot", boot).put("deadlineElapsed", SystemClock.elapsedRealtime() + left)
        save(value)
        if (left == 0L) finish() else {
            if (value.getString("kind") == "focus" && dnd.granted) runCatching { dnd.acquire() }
            schedule(value); notify(value)
        }
    }
    fun snapshot(): Map<String, Any?> {
        finish()
        val value = state()
        if (value != null) value.put("remainingMillis", remaining(value))
        if (dnd.needsRelease && (value == null || value.optString("status") != "running" || value.optString("kind") != "focus")) dnd.release()
        return mapOf("state" to value?.let { toMap(it) },
            "lastMinutes" to prefs.getInt("lastMinutes", 25),
            "dndGranted" to dnd.granted,
            "dndEnabled" to (notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL &&
                notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN),
            "records" to (0 until records().length()).map { toMap(records().getJSONObject(it)) })
    }
    fun handle(method: String, args: Map<*, *>): Map<String, Any?> {
        when (method) {
            "start" -> {
                finish()
                val previous = state()
                check(previous == null || previous.getString("status") == "finished") { "已有进行中的计时" }
                val minutes = (args["minutes"] as Number).toInt()
                require(minutes in 5..180 && minutes % 5 == 0)
                val kind = args["kind"] as String
                require(kind == "focus" || kind == "rest")
                val now = System.currentTimeMillis()
                val value = JSONObject().put("id", args["id"]).put("taskId", args["taskId"])
                    .put("space", args["space"] ?: "life").put("taskTitle", args["taskTitle"]).put("startAction", args["startAction"] ?: JSONObject.NULL).put("kind", kind).put("status", "running")
                    .put("plannedSeconds", minutes * 60).put("remainingMillis", minutes * 60000L)
                    .put("startedAt", now).put("deadlineWall", now + minutes * 60000L)
                    .put("deadlineElapsed", SystemClock.elapsedRealtime() + minutes * 60000L).put("boot", boot)
                schedule(value) // Do not accept a timer if exact scheduling is denied.
                try {
                    if (kind == "focus") dnd.acquire() else dnd.release()
                    save(value)
                } catch (error: Exception) {
                    cancel(value); dnd.release(); throw error
                }
                if (kind == "focus") check(prefs.edit().putInt("lastMinutes", minutes).commit())
                notify(value)
            }
            "pause" -> {
                finish()
                val value = state()
                if (value != null && value.getString("status") == "running") {
                    value.put("remainingMillis", remaining(value)).put("status", "paused")
                    save(value); cancel(value); dnd.release(); notify(value)
                }
            }
            "resume" -> {
                val value = state()
                if (value != null && value.getString("status") == "paused") {
                    val left = value.getLong("remainingMillis")
                    value.put("status", "running").put("deadlineWall", System.currentTimeMillis() + left)
                        .put("deadlineElapsed", SystemClock.elapsedRealtime() + left).put("boot", boot)
                    schedule(value)
                    try {
                        if (value.getString("kind") == "focus") dnd.acquire()
                        save(value)
                    } catch (error: Exception) {
                        cancel(value); dnd.release(); throw error
                    }
                    notify(value)
                }
            }
            "stop" -> {
                finish()
                val value = state()
                if (value != null && value.getString("status") != "finished") record(value, "interrupted")
                if (value != null) cancel(value)
                check(prefs.edit().remove("state").commit())
                dnd.release()
                notifications.cancel(73)
            }
            "dismiss" -> {
                val value = state()
                check(value == null || value.getString("status") == "finished")
                check(prefs.edit().remove("state").commit()); dnd.release(); notifications.cancel(73)
            }
            "ack" -> {
                val ids = (args["ids"] as? List<*>)?.toSet() ?: emptySet<Any>()
                val kept = JSONArray()
                val all = records()
                for (i in 0 until all.length()) if (!ids.contains(all.getJSONObject(i).getString("id"))) kept.put(all.getJSONObject(i))
                check(prefs.edit().putString("records", kept.toString()).commit())
            }
            "get" -> Unit
            else -> throw IllegalArgumentException("Unknown timer method")
        }
        return snapshot()
    }
    private fun toMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith {
        json.get(it).let { value -> if (value == JSONObject.NULL) null else value }
    }
}

class FocusAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val timer = FocusTimer(context)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) timer.restoreAfterBoot()
        else timer.finish(intent.getStringExtra("id"))
    }
}
