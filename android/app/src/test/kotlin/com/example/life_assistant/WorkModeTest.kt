package com.example.life_assistant

import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
class WorkModeTest {
    private lateinit var context: Context
    private var wall = 0L
    private fun createWork() = WorkMode(context) { wall }
    @Before fun prepare() {
        context=RuntimeEnvironment.getApplication()
        context.getSharedPreferences("dayflow_work",Context.MODE_PRIVATE).edit().clear().commit()
        org.robolectric.Shadows.shadowOf(context as android.app.Application).grantPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(true)
        wall = Instant.parse("2026-11-08T02:00:00Z").toEpochMilli()
    }
    @Test fun browsingDoesNotStartWorkAndSettingsSurvive() {
        val work=createWork()
        assertEquals(false,work.handle("get",emptyMap<Any,Any>())["active"])
        work.handle("configure",mapOf("water" to 90,"eyes" to 0))
        assertEquals(90,createWork().snapshot()["water"])
        assertEquals(false,work.snapshot()["active"])
    }
    @Test fun disabledIntervalsSurviveRecreationAndRestore() {
        val work = createWork()
        work.handle("configure", mapOf("water" to 45, "eyes" to 75))
        work.handle("configure", mapOf("water" to 0, "eyes" to 0))
        val saved = createWork().snapshot()
        assertEquals(45, saved["waterInterval"])
        assertEquals(75, saved["eyesInterval"])
        assertEquals(0, saved["water"])
        work.handle("configure", mapOf("water" to saved["waterInterval"]!!, "eyes" to saved["eyesInterval"]!!))
        assertEquals(45, createWork().snapshot()["water"])
        assertEquals(75, createWork().snapshot()["eyes"])
    }
    @Test fun statusNotificationDescribesRemindersAndConfiguredCloseTime() {
        val work = createWork()
        work.handle("rules", mapOf("lunchStart" to 720, "lunchEnd" to 840, "endMinute" to 1200, "autoEnd" to true))
        val state = work.handle("start", emptyMap<Any, Any>())
        assertEquals(Instant.parse("2026-11-08T12:00:00Z").toEpochMilli(), state["end"])
        val notifications = org.robolectric.Shadows.shadowOf(context.getSystemService(android.app.NotificationManager::class.java))
        assertEquals("工作提醒已开启", notifications.getNotification(82).extras.getCharSequence(android.app.Notification.EXTRA_TITLE).toString())
        assertEquals("20:00 自动关闭", notifications.getNotification(82).extras.getCharSequence(android.app.Notification.EXTRA_TEXT).toString())
        work.handle("rules", mapOf("lunchStart" to 720, "lunchEnd" to 840, "endMinute" to 1200, "autoEnd" to false))
        assertEquals("喝水、远眺提醒", notifications.getNotification(82).extras.getCharSequence(android.app.Notification.EXTRA_TEXT).toString())
        work.stop()
        assertEquals(0L, work.snapshot()["end"])
        assertNull(notifications.getNotification(82))
    }
    @Test fun workExpiresAtTenAndDoesNotRestartNextDay() {
        val work=createWork()
        assertEquals(true,work.handle("start",emptyMap<Any,Any>())["active"])
        wall += Duration.ofHours(12).toMillis()
        assertEquals(false,createWork().snapshot()["active"])
        wall += Duration.ofHours(10).toMillis()
        assertEquals(false,createWork().snapshot()["active"])
    }
    @Test fun lunchSchedulesNoImmediateReminderAndStopCancelsAlarms() {
        wall = Instant.parse("2026-11-08T04:30:00Z").toEpochMilli()
        val work=createWork(); work.handle("start",emptyMap<Any,Any>())
        work.receive()
        assertNull(context.getSystemService(android.app.NotificationManager::class.java).getNotificationChannel("work_reminders"))
        work.stop()
        assertEquals(false,work.snapshot()["active"])
    }
    @Test fun dinnerPausesRemindersAndResumesWithoutBacklog() {
        wall = Instant.parse("2026-11-08T09:59:00Z").toEpochMilli()
        val work = createWork()
        work.handle("start",emptyMap<Any,Any>())
        val alarms = org.robolectric.Shadows.shadowOf(context.getSystemService(android.app.AlarmManager::class.java))
        assertEquals(Instant.parse("2026-11-08T10:00:00Z").toEpochMilli(), alarms.nextScheduledAlarm?.triggerAtTime)
        wall = Instant.parse("2026-11-08T10:00:00Z").toEpochMilli()
        work.receive()
        wall = Instant.parse("2026-11-08T10:59:00Z").toEpochMilli()
        createWork().receive()
        val notifications = org.robolectric.Shadows.shadowOf(context.getSystemService(android.app.NotificationManager::class.java))
        assertNull(notifications.getNotification(81))
        assertEquals(true,work.snapshot()["active"])
        wall = Instant.parse("2026-11-08T11:00:00Z").toEpochMilli()
        work.receive()
        assertNull(notifications.getNotification(81))
        wall += Duration.ofMinutes(30).toMillis()
        work.receive()
        assertNotNull(notifications.getNotification(81))
        assertEquals(true,work.snapshot()["active"])
    }
    @Test fun dinnerRulesPersistAndOldClientsKeepDefaults() {
        val work = createWork()
        val rules = mapOf("lunchStart" to 720, "lunchEnd" to 840, "endMinute" to 1320, "autoEnd" to true)
        assertEquals(1080,work.handle("rules",rules)["dinnerStart"])
        work.handle("rules",rules + mapOf("dinnerStart" to 1050, "dinnerEnd" to 1170))
        assertEquals(1050,createWork().snapshot()["dinnerStart"])
        assertEquals(1170,work.handle("rules",rules)["dinnerEnd"])
    }
    @Test fun runningFocusDelaysCombinedReminderAndNoBacklogIsReplayed() {
        val work=createWork(); work.handle("start",emptyMap<Any,Any>())
        val prefs=context.getSharedPreferences("dayflow_work",Context.MODE_PRIVATE)
        wall += Duration.ofHours(1).toMillis()
        val focus=context.getSharedPreferences("focus_timer_v1",Context.MODE_PRIVATE)
        focus.edit().putString("state", """{"status":"running","kind":"focus","deadlineWall":${wall+300000}}""").commit()
        work.receive()
        assertTrue(prefs.getLong("waterDue",0)>wall)
        assertTrue(prefs.getLong("eyesDue",0)>wall)
        assertNull(context.getSystemService(android.app.NotificationManager::class.java).getNotificationChannel("work_reminders"))
        focus.edit().remove("state").commit()
        wall += Duration.ofMinutes(10).toMillis()
        work.receive()
        assertNull(context.getSystemService(android.app.NotificationManager::class.java).getNotificationChannel("work_reminders"))
        assertTrue(prefs.getLong("waterDue",0)>wall)
    }
}
