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
