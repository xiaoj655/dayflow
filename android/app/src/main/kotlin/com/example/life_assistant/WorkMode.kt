package com.example.life_assistant

import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import android.app.*
import android.content.*
import android.os.Build
import java.util.Calendar
import java.util.TimeZone

/** Local alarms, independent of Flutter and the database. */
class WorkMode(private val context: Context, private val clock: () -> Long = System::currentTimeMillis) {
    private val prefs = context.getSharedPreferences("dayflow_work", Context.MODE_PRIVATE)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private fun now() = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply { timeInMillis = clock() }
    private fun alarm() = PendingIntent.getBroadcast(context, 81, Intent(context, WorkReminderReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun end(): Long = prefs.getLong("end", 0)
    fun snapshot(): Map<String, Any> {
        if (end() != 0L && clock() >= end()) stop()
        return mapOf("active" to (end() > clock()), "end" to end(), "waterInterval" to prefs.getInt("waterInterval", prefs.getInt("water", 60).takeIf { it > 0 } ?: 60), "eyesInterval" to prefs.getInt("eyesInterval", prefs.getInt("eyes", 30).takeIf { it > 0 } ?: 30), "water" to prefs.getInt("water", 60), "eyes" to prefs.getInt("eyes", 30), "started" to prefs.getLong("started",0), "lunchStart" to prefs.getInt("lunchStart",720), "lunchEnd" to prefs.getInt("lunchEnd",840), "dinnerStart" to prefs.getInt("dinnerStart",1080), "dinnerEnd" to prefs.getInt("dinnerEnd",1140), "autoEnd" to prefs.getBoolean("autoEnd",true), "endMinute" to prefs.getInt("endMinute",1320))
    }
    fun stop() {
        context.getSystemService(NotificationManager::class.java).cancel(82)
        check(prefs.edit().putLong("end", 0).commit())
        alarms.cancel(alarm())
        context.getSystemService(NotificationManager::class.java).cancel(81)
    }
    fun handle(method: String, args: Map<*, *>): Map<String, Any> {
        when (method) {
            "start" -> {
                val current = now()
                check(!prefs.getBoolean("autoEnd",true) || current.get(Calendar.HOUR_OF_DAY)*60+current.get(Calendar.MINUTE) < prefs.getInt("endMinute",1320)) { "已过自动关闭时间，请调整提醒时段或明天再开启" }
                if (Build.VERSION.SDK_INT >= 33) check(context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) { "请先允许通知权限" }
                check(Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) { "请先允许闹钟和提醒权限" }
                current.set(Calendar.HOUR_OF_DAY, prefs.getInt("endMinute",1320)/60); current.set(Calendar.MINUTE, prefs.getInt("endMinute",1320)%60); current.set(Calendar.SECOND, 0); current.set(Calendar.MILLISECOND, 0)
                check(prefs.edit().putLong("started",clock()).putLong("end", if(prefs.getBoolean("autoEnd",true)) current.timeInMillis else Long.MAX_VALUE).commit())
                resetDue()
            }
            "stop" -> stop()
            "rules" -> {
                val start=(args["lunchStart"] as Number).toInt(); val finish=(args["lunchEnd"] as Number).toInt();val endMinute=(args["endMinute"] as Number).toInt()
                val dinnerStart=(args["dinnerStart"] as? Number)?.toInt() ?: prefs.getInt("dinnerStart",1080)
                val dinnerEnd=(args["dinnerEnd"] as? Number)?.toInt() ?: prefs.getInt("dinnerEnd",1140)
                require(dinnerStart in 0..1435 && dinnerEnd in 0..1435 && dinnerStart<dinnerEnd)
                require(start in 0..1435 && finish in 0..1435 && start<finish && endMinute in 0..1435)
                check(prefs.edit().putInt("dinnerStart",dinnerStart).putInt("dinnerEnd",dinnerEnd).putInt("lunchStart",start).putInt("lunchEnd",finish).putBoolean("autoEnd",args["autoEnd"]==true).putInt("endMinute",endMinute).commit())
                if(end()>0){ val c=now();c.set(Calendar.HOUR_OF_DAY,endMinute/60);c.set(Calendar.MINUTE,endMinute%60);c.set(Calendar.SECOND,0);check(prefs.edit().putLong("end",if(args["autoEnd"]==true)c.timeInMillis else Long.MAX_VALUE).commit()) }
            }
            "configure" -> {
                val water = (args["water"] as Number).toInt(); val eyes = (args["eyes"] as Number).toInt()
                require(water in 0..180 && eyes in 0..180 && water % 5 == 0 && eyes % 5 == 0)
                val editor = prefs.edit().putInt("water", water).putInt("eyes", eyes)
                // Editing one reminder must not postpone the other one's deadline.
                if (water != prefs.getInt("water", 60)) editor.putLong("waterDue", clock() + water * 60000L)
                if (eyes != prefs.getInt("eyes", 30)) editor.putLong("eyesDue", clock() + eyes * 60000L)
                if (water > 0) editor.putInt("waterInterval", water)
                else if (prefs.getInt("water", 60) > 0) editor.putInt("waterInterval", prefs.getInt("water", 60))
                if (eyes > 0) editor.putInt("eyesInterval", eyes)
                else if (prefs.getInt("eyes", 30) > 0) editor.putInt("eyesInterval", prefs.getInt("eyes", 30))
                check(editor.commit())
            }
        }
        schedule()
        return snapshot()
    }
    private fun quietEnd(minute: Int): Int? = listOf(
        prefs.getInt("lunchStart",720) to prefs.getInt("lunchEnd",840),
        prefs.getInt("dinnerStart",1080) to prefs.getInt("dinnerEnd",1140)
    ).filter { minute >= it.first && minute < it.second }.maxOfOrNull { it.second }

    private fun resetDue(base: Long = clock()) {
        check(prefs.edit().putLong("waterDue", base + prefs.getInt("water",60)*60000L).putLong("eyesDue", base + prefs.getInt("eyes",30)*60000L).commit())
    }
    fun schedule() {
        if (end() <= clock()) { stop(); return }
        val nm=context.getSystemService(NotificationManager::class.java)
        val statusChannel=NotificationChannel("work_status","工作提醒状态",NotificationManager.IMPORTANCE_LOW)
        statusChannel.setSound(null,null); statusChannel.enableVibration(false); nm.createNotificationChannel(statusChannel)
        val open=PendingIntent.getActivity(context,82,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val endMinute = prefs.getInt("endMinute",1320)
        val statusText = if (prefs.getBoolean("autoEnd",true))
            "%02d:%02d 自动关闭".format(endMinute / 60, endMinute % 60)
        else "喝水、远眺提醒"
        val builder=NotificationCompat.Builder(context,"work_status").setSmallIcon(R.drawable.ic_notification).setLargeIcon(android.graphics.BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)).setContentTitle("工作提醒已开启").setContentText(statusText).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
        OngoingActivity.Builder(context,82,builder).setStaticIcon(R.drawable.ic_notification).setTouchIntent(open).build().apply(context)
        try { nm.notify(82,builder.build()) } catch (_: SecurityException) { }
        val c = now()
        val minute=c.get(Calendar.HOUR_OF_DAY)*60+c.get(Calendar.MINUTE)
        val quietEnd = quietEnd(minute)
        var next = end()
        for (start in listOf(prefs.getInt("lunchStart",720), prefs.getInt("dinnerStart",1080))) {
            if (minute < start) {
                val boundary = (c.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY,start/60); set(Calendar.MINUTE,start%60)
                    set(Calendar.SECOND,0); set(Calendar.MILLISECOND,0)
                }
                next = minOf(next,boundary.timeInMillis)
            }
        }
        if (quietEnd != null) {
            c.set(Calendar.HOUR_OF_DAY,quietEnd/60); c.set(Calendar.MINUTE,quietEnd%60); c.set(Calendar.SECOND,0); c.set(Calendar.MILLISECOND,0)
            // Start fresh intervals after the break; never replay missed reminders.
            resetDue(c.timeInMillis)
            nm.cancel(81)
            next = minOf(next,c.timeInMillis)
        } else {
            for (key in listOf("water", "eyes")) if (prefs.getInt(key, if(key=="water")60 else 30)>0) next=minOf(next,prefs.getLong(key+"Due",clock()+60000))
        }
        try { alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(next,clock()+1000), alarm()) }
        catch (_: SecurityException) { stop() }
    }
    fun receive() {
        if (end() <= clock()) { stop(); return }
        val current = now()
        val minute = current.get(Calendar.HOUR_OF_DAY)*60+current.get(Calendar.MINUTE)
        if (quietEnd(minute) != null) { schedule(); return }
        val focused = FocusTimer(context, clock).isRunningFocus()
        val due = listOf("water", "eyes").filter { prefs.getInt(it,if(it=="water")60 else 30)>0 && prefs.getLong(it+"Due",0) <= clock()+60000 }
        if (focused) {
            val edit=prefs.edit(); for(key in due) edit.putLong(key+"Due", minOf(end(),clock()+60000)); check(edit.commit())
        } else if (due.isNotEmpty()) {
            // An alarm delivered very late is skipped rather than replayed in a burst.
            val timely = due.filter { clock()-prefs.getLong(it+"Due",0)<5*60000 }
            if (timely.isNotEmpty()) {
                val nm=context.getSystemService(NotificationManager::class.java)
                val channel=NotificationChannel("work_reminders","工作休息提醒",NotificationManager.IMPORTANCE_HIGH)
                channel.setSound(null,null); channel.enableVibration(true); channel.vibrationPattern=longArrayOf(0,80)
                nm.createNotificationChannel(channel)
                val message=timely.joinToString("，") { if(it=="water") "喝口水" else "看看远处，休息眼睛" }
                val open=PendingIntent.getActivity(context,81,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val notification=Notification.Builder(context,"work_reminders").setSmallIcon(R.drawable.ic_notification).setLargeIcon(android.graphics.BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)).setContentTitle(message).setContentIntent(open).setAutoCancel(true).setTimeoutAfter(5000).build()
                try { nm.notify(81,notification) } catch (_: SecurityException) { }
            }
            val edit=prefs.edit(); for(key in due) edit.putLong(key+"Due",clock()+prefs.getInt(key,60)*60000L); check(edit.commit())
        }
        schedule()
    }
}
class WorkReminderReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context,intent: Intent) {
        if(intent.action==Intent.ACTION_BOOT_COMPLETED) WorkMode(context).schedule() else WorkMode(context).receive()
    }
}
