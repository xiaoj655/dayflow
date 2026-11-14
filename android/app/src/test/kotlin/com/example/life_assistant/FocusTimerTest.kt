package com.example.life_assistant

import android.app.AlarmManager
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Vibrator
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

    @Test fun earlyFinishKeepsAnAccurateSummaryAndClearsActiveEffectsWithoutVibrating() {
        start()
        elapse(Duration.ofMillis(189600))
        val snapshot = timer.handle("finishEarly", mapOf("id" to "session-1"))
        val state = snapshot["state"] as Map<*, *>
        assertEquals("finished", state["status"])
        assertEquals("interrupted", state["completionStatus"])
        assertEquals(189, state["actualSeconds"])
        assertEquals(110400L, state["remainingMillis"])
        assertEquals(300, state["plannedSeconds"])
        val record = (snapshot["records"] as List<*>).single() as Map<*, *>
        assertEquals("interrupted", record["status"])
        assertEquals(189, record["actualSeconds"])
        assertEquals(wall, record["endedAt"])
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
        assertNull(shadowOf(context.getSystemService(AlarmManager::class.java)).nextScheduledAlarm)
        assertNull(shadowOf(manager).getNotification(73))
        assertFalse(shadowOf(context.getSystemService(Vibrator::class.java)).isVibrating)
    }

    @Test fun earlyFinishWhilePausedExcludesTheEntirePause() {
        start()
        elapse(Duration.ofSeconds(190))
        timer.handle("pause", emptyMap<Any, Any>())
        elapse(Duration.ofHours(1))
        val snapshot = timer.handle("finishEarly", emptyMap<Any, Any>())
        val state = snapshot["state"] as Map<*, *>
        assertEquals(190, state["actualSeconds"])
        assertEquals(110000L, state["remainingMillis"])
        assertEquals(190, ((snapshot["records"] as List<*>).single() as Map<*, *>)["actualSeconds"])
        elapse(Duration.ofHours(1))
        assertEquals(state, createTimer().snapshot()["state"])
    }

    @Test fun earlyFinishUnderThreeMinutesKeepsASummaryWithoutRecordingFocus() {
        start()
        elapse(Duration.ofMillis(179999))
        val snapshot = timer.handle("finishEarly", emptyMap<Any, Any>())
        val state = snapshot["state"] as Map<*, *>
        assertEquals("interrupted", state["completionStatus"])
        assertEquals(179, state["actualSeconds"])
        assertTrue((snapshot["records"] as List<*>).isEmpty())
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
    }

    @Test fun earlyFinishAtThreeActiveMinutesRecordsAnInterruptedRound() {
        start()
        elapse(Duration.ofSeconds(179))
        timer.handle("pause", emptyMap<Any, Any>())
        elapse(Duration.ofHours(1))
        timer.handle("resume", emptyMap<Any, Any>())
        elapse(Duration.ofSeconds(1))
        val snapshot = timer.handle("finishEarly", emptyMap<Any, Any>())
        val record = (snapshot["records"] as List<*>).single() as Map<*, *>
        assertEquals(180, record["actualSeconds"])
        assertEquals("interrupted", record["status"])
        assertEquals(180, (snapshot["state"] as Map<*, *>)["actualSeconds"])
    }

    @Test fun earlyFinishSurvivesRestorationAndCannotReplayAnAcknowledgedRecord() {
        start()
        elapse(Duration.ofSeconds(181))
        timer.handle("finishEarly", mapOf("id" to "session-1"))
        val restored = createTimer()
        restored.restoreAfterBoot()
        val repeated = restored.handle("finishEarly", mapOf("id" to "session-1"))
        assertEquals(1, (repeated["records"] as List<*>).size)
        val state = repeated["state"] as Map<*, *>
        assertEquals(181, state["actualSeconds"])
        restored.handle("ack", mapOf("ids" to listOf("session-1")))
        val afterAck = createTimer().handle("finishEarly", mapOf("id" to "session-1"))
        assertEquals(state, afterAck["state"])
        assertTrue((afterAck["records"] as List<*>).isEmpty())
        val rest = start("next-rest", "rest")["state"] as Map<*, *>
        assertEquals("next-rest", rest["id"])
        assertEquals("running", rest["status"])
    }

    @Test fun earlyFinishSettlesAnAlreadyExpiredRoundAsNaturalCompletion() {
        start()
        elapse(Duration.ofMinutes(6))
        timer.handle("finishEarly", mapOf("id" to "session-1"))
        val repeated = timer.handle("finishEarly", mapOf("id" to "session-1"))
        val state = repeated["state"] as Map<*, *>
        assertEquals("completed", state["completionStatus"])
        assertEquals(300, state["actualSeconds"])
        assertEquals(0L, state["remainingMillis"])
        val record = (repeated["records"] as List<*>).single() as Map<*, *>
        assertEquals("completed", record["status"])
        assertEquals(300, record["actualSeconds"])
    }

    @Test fun earlyFinishWithAnOldIdCannotEndTheCurrentSession() {
        start("new-session")
        elapse(Duration.ofSeconds(190))
        val snapshot = timer.handle("finishEarly", mapOf("id" to "old-session"))
        val state = snapshot["state"] as Map<*, *>
        assertEquals("running", state["status"])
        assertEquals("new-session", state["id"])
        assertEquals(110000L, state["remainingMillis"])
        assertTrue((snapshot["records"] as List<*>).isEmpty())
        assertEquals(Condition.STATE_TRUE, FocusDnd(context).condition().state)
        assertNotNull(shadowOf(context.getSystemService(AlarmManager::class.java)).nextScheduledAlarm)
    }

    @Test fun earlyFinishOfAShortRestStillRecordsTheRest() {
        start(kind = "rest")
        elapse(Duration.ofSeconds(10))
        val snapshot = timer.handle("finishEarly", emptyMap<Any, Any>())
        assertEquals(10, (snapshot["state"] as Map<*, *>)["actualSeconds"])
        val record = (snapshot["records"] as List<*>).single() as Map<*, *>
        assertEquals(10, record["actualSeconds"])
        assertEquals("rest", record["kind"])
        assertEquals("interrupted", record["status"])
        assertEquals(Condition.STATE_FALSE, FocusDnd(context).condition().state)
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
