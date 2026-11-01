package com.example.life_assistant

import android.Manifest
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewConfiguration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var rotaryChannel: MethodChannel? = null
    private val touchHaptics by lazy { TouchHaptics(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        rotaryChannel = MethodChannel(messenger, "life_assistant/rotary")
        MethodChannel(messenger, "life_assistant/focus")
            .setMethodCallHandler { call, result ->
                try {
                    if (call.method == "permissions") {
                        check(permissionResult == null) { "正在等待系统授权" }
                        permissionResult = result
                        advancePermissions()
                    } else {
                        result.success(FocusTimer(this).handle(call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
                    }
                } catch (error: Exception) {
                    result.error("FOCUS_ERROR", error.message, null)
                }
            }
        MethodChannel(messenger, "life_assistant/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method != "selection" && call.method != "rotary") result.notImplemented()
                else try {
                    if (call.method == "rotary") touchHaptics.rotary(window.decorView)
                    else touchHaptics.selection(window.decorView)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("HAPTIC_ERROR", error.message, null)
                }
            }
        MethodChannel(messenger, "life_assistant/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isScreenRound" -> result.success(resources.configuration.isScreenRound)
                    else -> result.notImplemented()
                }
            }
    }

    private fun permissionError(message: String) {
        permissionResult?.error("PERMISSION_REQUIRED", message, null)
        permissionResult = null
    }

    private fun advancePermissions() {
        try {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 74)
                return
            }
            if (Build.VERSION.SDK_INT >= 31 && !getSystemService(AlarmManager::class.java).canScheduleExactAlarms()) {
                startActivityForResult(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")), 75)
                return
            }
            if (!FocusDnd(this).granted) {
                startActivityForResult(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS), 76)
                return
            }
            if (FocusDnd(this).phoneSyncPermissionRequired) {
                permissionError("手机勿扰联动尚未授权，请连接电脑完成一次授权")
                return
            }
            permissionResult?.success(FocusTimer(this).snapshot())
            permissionResult = null
        } catch (error: ActivityNotFoundException) {
            permissionError("手表系统未提供所需的权限设置入口，请先在连接电脑时完成一次授权，再开始专注")
        } catch (error: Exception) {
            permissionError(error.message ?: "请在系统设置中允许通知、闹钟和勿扰控制")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 74 && permissionResult != null) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) advancePermissions()
            else permissionError("需要通知权限，才能在专注结束时提醒你")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (permissionResult == null) return
        when (requestCode) {
            75 -> if (Build.VERSION.SDK_INT < 31 || getSystemService(AlarmManager::class.java).canScheduleExactAlarms()) advancePermissions()
                else permissionError("请允许闹钟和提醒，确保熄屏后专注计时仍能提醒")
            76 -> if (FocusDnd(this).granted) advancePermissions()
                else permissionError("请允许 Dayflow 控制勿扰模式，专注结束后会自动撤销专注勿扰")
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        // Handle before FlutterView, which only forwards pointer-class scrolling.
        if (event.action == MotionEvent.ACTION_SCROLL &&
            event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER) &&
            rotaryChannel != null
        ) {
            val axis = event.getAxisValue(MotionEvent.AXIS_SCROLL)
            if (axis != 0f) {
                val pixelsPerTick = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ViewConfiguration.get(this).scaledVerticalScrollFactor
                } else {
                    48f * resources.displayMetrics.density
                }
                // Some watch themes configure a very large generic scroll factor.
                // Keep one encoder unit controllable on a 240dp display, while
                // retaining fractional movement and faster continuous turns.
                val logicalPixelsPerTick =
                    (pixelsPerTick / resources.displayMetrics.density).coerceIn(12f, 32f)
                val logicalDelta = -axis * logicalPixelsPerTick * 2.04f
                rotaryChannel?.invokeMethod("scroll", logicalDelta.toDouble())
                return true
            }
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        rotaryChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
