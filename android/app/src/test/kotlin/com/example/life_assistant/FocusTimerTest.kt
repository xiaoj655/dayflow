package com.example.life_assistant

import android.app.AlarmManager
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.provider.Settings
import android.service.notification.Condition
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Resetter
import org.robolectric.shadows.ShadowNotificationManager
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34, 35], shadows = [RuleStateNotificationManager::class])
class FocusTimerTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager
    private lateinit var timer: FocusTimer
    private var wall = 0L

    private fun createTimer() = FocusTimer(context) { wall }
    private fun elapse(duration: Duration) {
        wall += duration.toMillis()
        ShadowSystemClock.advanceBy(duration)
    }

    @Before fun prepare() {
        context = RuntimeEnvironment.getApplication()
        manager = context.getSystemService(NotificationManager::class.java)
        shadowOf(manager).setNotificationPolicyAccessGranted(true)
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(true)
        wall = Instant.parse("2026-11-08T02:00:00Z").toEpochMilli()
        timer = createTimer()
    }

    private fun start(id: String = "session-1", kind: String = "focus") = timer.handle("start", mapOf(
        "id" to id, "taskId" to "task:2026-10-24", "taskTitle" to "阅读",
        "startAction" to "先读一节", "minutes" to 5, "kind" to kind))

    @Test fun focusPauseResumeAndStopOnlyChangeTheAppRule() {
        val userRule = AutomaticZenRule("用户原有规则", ComponentName(context, FocusDndConditionService::class.java),
            Uri.parse("condition://user/night"), NotificationManager.INTERRUPTION_FILTER_NONE, true)
        val userId = manager.addAutomaticZenRule(userRule)
        start()
        assertEquals(Condition.STATE_TRUE, FocusDnd(context).condition().state)
        assertEquals(2, manager.automaticZenRules.size)
        val ownId = manager.automaticZenRules.keys.single { it != userId }
        assertEquals(NotificationManager.INTERRUPTION_FILTER_ALARMS, manager.getAutomaticZenRule(ownId)!!.interruptionFilter)
        val ruleStates = shadowOf(manager) as RuleStateNotificationManager
        assertEquals(Condition.STATE_TRUE, ruleStates.stateOf(ownId))
        timer.handle("pause", emptyMap<Any, Any>())
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
        assertNotNull(manager.getAutomaticZenRule(userId))
        assertEquals(Condition.STATE_FALSE, ruleStates.stateOf(ownId))
        timer.handle("resume", emptyMap<Any, Any>())
        assertEquals(Condition.STATE_TRUE, FocusDnd(context).condition().state)
        assertEquals(Condition.STATE_TRUE, ruleStates.stateOf(ownId))
        timer.handle("stop", emptyMap<Any, Any>())
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
        assertEquals(Condition.STATE_FALSE, ruleStates.stateOf(ownId))
        assertEquals(NotificationManager.INTERRUPTION_FILTER_NONE, manager.getAutomaticZenRule(userId)!!.interruptionFilter)
    }

    @Test fun naturalCompletionReleasesDndAndJournalsOnlyOnce() {
        start()
        elapse(Duration.ofMinutes(5))
        timer.finish("session-1")
        timer.finish("session-1")
        val snapshot = timer.snapshot()
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
        assertEquals("finished", (snapshot["state"] as Map<*, *>)["status"])
        val records = snapshot["records"] as List<*>
        assertEquals(1, records.size)
        assertEquals("completed", (records.single() as Map<*, *>)["status"])
        start("rest-1", "rest")
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
        assertEquals(5, timer.snapshot()["lastMinutes"])
    }

    @Test fun delayedNaturalCompletionEndsAtTheTimerDeadline() {
        val startedAt = (start()["state"] as Map<*, *>)["startedAt"] as Long
        elapse(Duration.ofMinutes(10))
        timer.finish("session-1")
        val record = (timer.snapshot()["records"] as List<*>).single() as Map<*, *>
        assertEquals(startedAt + Duration.ofMinutes(5).toMillis(), record["endedAt"])
        assertEquals(300, record["actualSeconds"])
    }

    @Test fun delayedCompletionPreservesThePauseBeforeItsDeadline() {
        val startedAt = (start()["state"] as Map<*, *>)["startedAt"] as Long
        elapse(Duration.ofMinutes(2))
        timer.handle("pause", emptyMap<Any, Any>())
        elapse(Duration.ofMinutes(10))
        timer.handle("resume", emptyMap<Any, Any>())
        elapse(Duration.ofMinutes(8))
        timer.finish("session-1")
        val record = (timer.snapshot()["records"] as List<*>).single() as Map<*, *>
        assertEquals(startedAt + Duration.ofMinutes(15).toMillis(), record["endedAt"])
        assertEquals(300, record["actualSeconds"])
    }

    @Test fun overdueCompletionAfterBootKeepsTheOriginalWallDeadline() {
        val startedAt = (start()["state"] as Map<*, *>)["startedAt"] as Long
        elapse(Duration.ofMinutes(10))
        val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, 0)
        Settings.Global.putInt(context.contentResolver, Settings.Global.BOOT_COUNT, boot + 1)
        createTimer().restoreAfterBoot()
        val record = (timer.snapshot()["records"] as List<*>).single() as Map<*, *>
        assertEquals(startedAt + Duration.ofMinutes(5).toMillis(), record["endedAt"])
        assertEquals(300, record["actualSeconds"])
    }

    @Test fun missingDndPermissionDoesNotAcceptATimer() {
        shadowOf(manager).setNotificationPolicyAccessGranted(false)
        assertThrows(IllegalStateException::class.java) { start() }
        assertNull(timer.snapshot()["state"])
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
    }

    @Test fun revokedPermissionStillAllowsStopAndKeepsItsRecord() {
        start()
        elapse(Duration.ofMinutes(3))
        shadowOf(manager).setNotificationPolicyAccessGranted(false)
        timer.handle("stop", emptyMap<Any, Any>())
        val snapshot = timer.snapshot()
        assertNull(snapshot["state"])
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
        assertEquals("interrupted", (((snapshot["records"] as List<*>).single()) as Map<*, *>)["status"])
    }

    @Test fun shortFocusIsDiscardedEvenAfterALongPause() {
        start()
        elapse(Duration.ofSeconds(179))
        timer.handle("pause", emptyMap<Any, Any>())
        elapse(Duration.ofHours(1))
        val snapshot = timer.handle("stop", emptyMap<Any, Any>())
        assertNull(snapshot["state"])
        assertTrue((snapshot["records"] as List<*>).isEmpty())
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
    }

    @Test fun exactlyThreeMinutesOfActiveFocusIsRecorded() {
        start()
        elapse(Duration.ofSeconds(179))
        timer.handle("pause", emptyMap<Any, Any>())
        elapse(Duration.ofHours(1))
        timer.handle("resume", emptyMap<Any, Any>())
        elapse(Duration.ofSeconds(1))
        val snapshot = timer.handle("stop", emptyMap<Any, Any>())
        assertEquals(180, ((snapshot["records"] as List<*>).single() as Map<*, *>)["actualSeconds"])
    }

    @Test fun shortRestIsStillRecorded() {
        start(kind = "rest")
        elapse(Duration.ofSeconds(10))
        val snapshot = timer.handle("stop", emptyMap<Any, Any>())
        assertEquals(10, ((snapshot["records"] as List<*>).single() as Map<*, *>)["actualSeconds"])
    }

    @Test fun nativeSnapshotRetainsTaskNameAndStartupAction() {
        start()
        val restored = createTimer().snapshot()["state"] as Map<*, *>
        assertEquals("阅读", restored["taskTitle"])
        assertEquals("先读一节", restored["startAction"])
        assertTrue((restored["remainingMillis"] as Long) > 0)
    }
}

// Robolectric 4.16 does not shadow set/getAutomaticZenRuleState. Record the
// application's published conditions while retaining its existing rule shadow.
@Implements(NotificationManager::class)
class RuleStateNotificationManager : ShadowNotificationManager() {
    companion object {
        private val conditions = mutableMapOf<String, Condition>()

        @JvmStatic @Resetter fun resetRuleStates() {
            conditions.clear()
            ShadowNotificationManager.reset()
        }
    }

    @Implementation(minSdk = 29)
    protected fun setAutomaticZenRuleState(id: String, condition: Condition) {
        checkNotNull(getAutomaticZenRule(id)) { "Cannot publish a condition for an unknown rule" }
        conditions[id] = condition
    }

    fun stateOf(id: String): Int = conditions[id]?.state ?: Condition.STATE_UNKNOWN
}
