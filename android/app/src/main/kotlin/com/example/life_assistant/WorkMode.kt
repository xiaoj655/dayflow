package com.example.life_assistant

import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import android.app.*
import android.content.*
import android.os.Build
import org.json.JSONObject
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
        return mapOf("active" to (end() > clock()), "water" to prefs.getInt("water", 60), "eyes" to prefs.getInt("eyes", 30), "started" to prefs.getLong("started",0), "lunchStart" to prefs.getInt("lunchStart",720), "lunchEnd" to prefs.getInt("lunchEnd",840), "autoEnd" to prefs.getBoolean("autoEnd",true), "endMinute" to prefs.getInt("endMinute",1320))
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
                check(!prefs.getBoolean("autoEnd",true) || current.get(Calendar.HOUR_OF_DAY)*60+current.get(Calendar.MINUTE) < prefs.getInt("endMinute",1320)) { "22:00 后请明天再开始工作" }
                if (Build.VERSION.SDK_INT >= 33) check(context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) { "请先允许通知权限" }
                check(Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) { "请先允许闹钟和提醒权限" }
                current.set(Calendar.HOUR_OF_DAY, prefs.getInt("endMinute",1320)/60); current.set(Calendar.MINUTE, prefs.getInt("endMinute",1320)%60); current.set(Calendar.SECOND, 0); current.set(Calendar.MILLISECOND, 0)
                check(prefs.edit().putLong("started",clock()).putLong("end", if(prefs.getBoolean("autoEnd",true)) current.timeInMillis else Long.MAX_VALUE).commit())
                resetDue()
            }
            "stop" -> stop()
            "rules" -> {
                val start=(args["lunchStart"] as Number).toInt(); val finish=(args["lunchEnd"] as Number).toInt();val endMinute=(args["endMinute"] as Number).toInt()
                require(start in 0..1435 && finish in 0..1435 && start<finish && endMinute in 0..1435)
                check(prefs.edit().putInt("lunchStart",start).putInt("lunchEnd",finish).putBoolean("autoEnd",args["autoEnd"]==true).putInt("endMinute",endMinute).commit())
                if(end()>0){ val c=now();c.set(Calendar.HOUR_OF_DAY,endMinute/60);c.set(Calendar.MINUTE,endMinute%60);c.set(Calendar.SECOND,0);check(prefs.edit().putLong("end",if(args["autoEnd"]==true)c.timeInMillis else Long.MAX_VALUE).commit()) }
            }
            "configure" -> {
                val water = (args["water"] as Number).toInt(); val eyes = (args["eyes"] as Number).toInt()
                require(water in 0..180 && eyes in 0..180 && water % 5 == 0 && eyes % 5 == 0)
                check(prefs.edit().putInt("water", water).putInt("eyes", eyes).commit())
                resetDue()
            }
        }
        schedule()
        return snapshot()
    }
    private fun resetDue() {
        val base = clock()
        check(prefs.edit().putLong("waterDue", base + prefs.getInt("water",60)*60000L).putLong("eyesDue", base + prefs.getInt("eyes",30)*60000L).commit())
    }
    fun schedule() {
        if (end() <= clock()) { stop(); return }
        val nm=context.getSystemService(NotificationManager::class.java)
        val statusChannel=NotificationChannel("work_status","工作状态",NotificationManager.IMPORTANCE_LOW)
        statusChannel.setSound(null,null); statusChannel.enableVibration(false); nm.createNotificationChannel(statusChannel)
        val open=PendingIntent.getActivity(context,82,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=NotificationCompat.Builder(context,"work_status").setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("工作中").setContentText("22:00 自动结束").setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
        OngoingActivity.Builder(context,82,builder).setStaticIcon(android.R.drawable.ic_lock_idle_alarm).setTouchIntent(open).build().apply(context)
        try { nm.notify(82,builder.build()) } catch (_: SecurityException) { }
        val c = now()
        val minute=c.get(Calendar.HOUR_OF_DAY)*60+c.get(Calendar.MINUTE)
        val lunch = minute >= prefs.getInt("lunchStart",720) && minute < prefs.getInt("lunchEnd",840)
        var next = end()
        if (lunch) {
            c.set(Calendar.HOUR_OF_DAY,prefs.getInt("lunchEnd",840)/60); c.set(Calendar.MINUTE,prefs.getInt("lunchEnd",840)%60); c.set(Calendar.SECOND,0)
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
        if (minute >= prefs.getInt("lunchStart",720) && minute < prefs.getInt("lunchEnd",840)) { resetDue(); schedule(); return }
        val focus = context.getSharedPreferences("focus_timer_v1", Context.MODE_PRIVATE).getString("state",null)?.let { JSONObject(it) }
        val focused = focus?.optString("status") == "running" && focus.optString("kind") == "focus" && focus.optLong("deadlineWall") > clock()
        val due = listOf("water", "eyes").filter { prefs.getInt(it,if(it=="water")60 else 30)>0 && prefs.getLong(it+"Due",0) <= clock()+60000 }
        if (focused) {
            val edit=prefs.edit(); for(key in due) edit.putLong(key+"Due", minOf(end(),clock()+60000)); check(edit.commit())
        } else if (due.isNotEmpty()) {
            // An alarm delivered very late is skipped rather than replayed in a burst.
            val timely = due.any { clock()-prefs.getLong(it+"Due",0)<5*60000 }
            if (timely) {
                val nm=context.getSystemService(NotificationManager::class.java)
                val channel=NotificationChannel("work_reminders","工作休息提醒",NotificationManager.IMPORTANCE_HIGH)
                channel.setSound(null,null); channel.enableVibration(true); channel.vibrationPattern=longArrayOf(0,80)
                nm.createNotificationChannel(channel)
                val message=due.joinToString("，") { if(it=="water") "喝口水" else "看看远处，休息眼睛" }
                val open=PendingIntent.getActivity(context,81,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val notification=Notification.Builder(context,"work_reminders").setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(message).setContentIntent(open).setAutoCancel(true).setTimeoutAfter(5000).build()
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
