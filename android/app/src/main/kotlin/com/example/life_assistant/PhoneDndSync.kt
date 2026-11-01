package com.example.life_assistant

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log

/** Xiaomi Watch 5's existing phone-sync path, not a generic Android DND API. */
internal class PhoneDndSync private constructor(private val context: Context) {
    companion object {
        private const val KEY = "mcu.persist.disturb_manual_state"
        @Volatile private var instance: PhoneDndSync? = null
        fun get(context: Context): PhoneDndSync = instance ?: synchronized(this) {
            instance ?: PhoneDndSync(context.applicationContext).also { instance = it }
        }
    }
    private val resolver = context.contentResolver
    private val prefs = context.getSharedPreferences("phone_dnd_sync_v1", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(NotificationManager::class.java)
    val supported: Boolean get() = Settings.Secure.getString(resolver, KEY) != null
    val granted: Boolean get() = context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
    private val lease = DndSyncLease(object : DndSyncLease.Store {
        override var state: DndSyncLease.State
            get() = runCatching { DndSyncLease.State.valueOf(prefs.getString("lease", "IDLE")!!) }
                .getOrDefault(DndSyncLease.State.IDLE)
            set(value) { check(prefs.edit().putString("lease", value.name).commit()) }
    },
        read = { Settings.Secure.getInt(resolver, KEY, -1) },
        dndWasOn = { manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL },
        write = { value ->
            check(Settings.Secure.putInt(resolver, KEY, value)) { "系统未能更新手机勿扰联动" }
            // The Xiaomi settings app explicitly notifies even for same-value writes.
            resolver.notifyChange(Settings.Secure.getUriFor(KEY), null)
        },
        canWrite = { granted },
    )
    val pending: Boolean get() = lease.pending
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) { runCatching { lease.observe() } }
    }
    init {
        if (supported) resolver.registerContentObserver(Settings.Secure.getUriFor(KEY), false, observer)
    }
    fun prepare() { if (supported) lease.prepare() }
    fun activate() { if (supported) lease.activate() }
    fun release() {
        if (!pending) return
        runCatching { lease.release() }.onFailure {
            Log.w("DayflowDnd", "Phone DND restoration remains pending", it)
        }
    }
}
