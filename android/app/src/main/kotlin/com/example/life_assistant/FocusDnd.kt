package com.example.life_assistant

import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.service.notification.Condition
import android.service.notification.ConditionProviderService

/** App-owned local rule plus an owned Xiaomi phone-sync flag, preserving existing DND. */
class FocusDnd(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val phoneSync = PhoneDndSync.get(context)
    private val prefs = context.getSharedPreferences("focus_dnd_v1", Context.MODE_PRIVATE)
    private val owner get() = ComponentName(context, FocusDndConditionService::class.java)
    val active: Boolean get() = prefs.getBoolean("active", false)
    val granted: Boolean get() = manager.isNotificationPolicyAccessGranted
    val phoneSyncPermissionRequired: Boolean get() = phoneSync.supported && !phoneSync.granted
    val needsRelease: Boolean get() = active || phoneSync.pending
    private val conditionId get() = Uri.parse("condition://${context.packageName}/focus")

    fun condition(): Condition = Condition(conditionId, "Dayflow 专注",
        if (prefs.getBoolean("active", false)) Condition.STATE_TRUE else Condition.STATE_FALSE)

    fun acquire() {
        check(granted) { "请先允许 Dayflow 控制勿扰模式" }
        phoneSync.prepare()
        try {
            var id = prefs.getString("ruleId", null)
            val existing = id?.let { manager.getAutomaticZenRule(it) }
            if (existing == null) {
                // Allow alarms, including the end-of-focus vibration; silence other interruptions.
                id = manager.addAutomaticZenRule(AutomaticZenRule("Dayflow 专注", owner,
                    conditionId, NotificationManager.INTERRUPTION_FILTER_ALARMS, true))
                check(id != null) { "系统未能创建专注勿扰规则" }
                check(prefs.edit().putString("ruleId", id).commit())
            } else if (!existing.isEnabled) {
                existing.isEnabled = true
                check(manager.updateAutomaticZenRule(id!!, existing)) { "请在系统设置中启用专注勿扰规则" }
            }
            check(prefs.edit().putBoolean("active", true).commit())
            publish(id!!)
            phoneSync.activate()
        } catch (error: Exception) {
            release()
            throw error
        }
    }

    fun release() {
        check(prefs.edit().putBoolean("active", false).commit())
        // Permission may have been revoked during focus. Local state must still be cleared.
        if (granted) runCatching { prefs.getString("ruleId", null)?.let { publish(it) } }
        phoneSync.release()
    }

    private fun publish(id: String) {
        if (Build.VERSION.SDK_INT >= 29) manager.setAutomaticZenRuleState(id, condition())
        else {
            FocusDndConditionService.publish(condition())
            ConditionProviderService.requestRebind(owner)
        }
    }
}

class FocusDndConditionService : ConditionProviderService() {
    companion object {
        private var connected: FocusDndConditionService? = null
        fun publish(condition: Condition) { connected?.notifyCondition(condition) }
    }
    override fun onConnected() {
        connected = this
        notifyCondition(FocusDnd(this).condition())
    }
    override fun onSubscribe(conditionId: Uri) { notifyCondition(FocusDnd(this).condition()) }
    override fun onUnsubscribe(conditionId: Uri) {}
    override fun onDestroy() { if (connected === this) connected = null; super.onDestroy() }
}
