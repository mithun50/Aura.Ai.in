package com.aura.mobile.aura_mobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.aura.mobile.aura_mobile.assistant.AssistantForegroundService

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.aura.ai/memory"
    private val APP_CONTROL_CHANNEL = "com.aura.ai/app_control"
    private val ASSISTANT_STATE_CHANNEL = "com.aura.ai/assistant_state"
    private val ASSISTANT_AI_CHANNEL = "com.aura.ai/assistant_ai"

    private var assistantStateSink: EventChannel.EventSink? = null
    private var assistantAiChannel: MethodChannel? = null

    private val assistantStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getStringExtra("state")
            if (state != null) {
                assistantStateSink?.success(state)
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Event Channel for Assistant State
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ASSISTANT_STATE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    assistantStateSink = events
                    val filter = IntentFilter("com.aura.mobile.assistant.STATE_CHANGE")
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(assistantStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(assistantStateReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    assistantStateSink = null
                    try {
                        unregisterReceiver(assistantStateReceiver)
                    } catch (e: Exception) {
                        // Receiver might not be registered
                    }
                }
            }
        )

        // Assistant AI Channel — bridges native voice assistant to Flutter AI pipeline
        assistantAiChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ASSISTANT_AI_CHANNEL)
        assistantAiChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendAIResponse" -> {
                    // Legacy full response — treat as single chunk + complete
                    val response = call.arguments as? String ?: ""
                    AssistantForegroundService.onAiChunk?.invoke(response)
                    AssistantForegroundService.onAiComplete?.invoke()
                    result.success(null)
                }
                "sendAIChunk" -> {
                    val chunk = call.arguments as? String ?: ""
                    AssistantForegroundService.onAiChunk?.invoke(chunk)
                    result.success(null)
                }
                "sendAIComplete" -> {
                    AssistantForegroundService.onAiComplete?.invoke()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Register as the AI request handler — direct call, no broadcasts
        AssistantForegroundService.aiRequestHandler = { query ->
            runOnUiThread {
                assistantAiChannel?.invokeMethod("processAIQuery", query)
            }
        }

        // If a query was pending (Flutter was dead when it arrived), forward it now
        val pending = AssistantForegroundService.pendingAiQuery
        if (pending != null) {
            AssistantForegroundService.pendingAiQuery = null
            assistantAiChannel?.invokeMethod("processAIQuery", pending)
        }

        // Memory Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAvailableMemory") {
                val availMem = getAvailableMemory()
                if (availMem != -1L) result.success(availMem) else result.error("UNAVAILABLE", "RAM not available.", null)
            } else if (call.method == "getTotalMemory") {
                 val totalMem = getTotalMemory()
                 if (totalMem != -1L) result.success(totalMem) else result.error("UNAVAILABLE", "RAM not available.", null)
            } else {
                result.notImplemented()
            }
        }

        // App Control Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApp" -> {
                    val appName = call.argument<String>("appName")
                    if (appName != null) {
                        launchApp(appName, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "App name is required", null)
                    }
                }
                "closeApp" -> {
                    // Android doesn't support force closing apps easily without root/accessibility
                    // We can just try to go to home screen or ignore for now to avoid crashes
                    result.success("Closing apps programmatically is restricted on Android.")
                }
                "openSettings" -> {
                    val type = call.argument<String>("type")
                    openSettings(type, result)
                }
                "openCamera" -> {
                    openCamera(result)
                }
                "dialContact" -> {
                    val name = call.argument<String>("name")
                    dialContact(name, result)
                }
                "sendSMS" -> {
                    val name = call.argument<String>("name")
                    val message = call.argument<String>("message")
                    sendSMS(name, message, result)
                }
                "sendSMSDirect" -> {
                    val number = call.argument<String>("number")
                    val message = call.argument<String>("message")
                    if (number != null && message != null) {
                        sendSMSDirect(number, message, result)
                    } else {
                        result.error("INVALID", "Number and message required", null)
                    }
                }
                "callPhoneDirect" -> {
                    val number = call.argument<String>("number")
                    if (number != null) {
                        callPhoneDirect(number, result)
                    } else {
                        result.error("INVALID", "Number required", null)
                    }
                }
                "toggleTorch" -> {
                    val state = call.argument<Boolean>("state")
                    if (state != null) {
                        toggleTorch(state, result)
                    } else {
                        result.error("INVALID", "State required", null)
                    }
                }
                "startAssistant" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this@MainActivity)) {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName")
                        )
                        startActivityForResult(intent, 1234)
                        result.error("NEEDS_OVERLAY_PERMISSION", "Please grant Display Over Other Apps permission.", null)
                    } else {
                        val serviceIntent = android.content.Intent(this@MainActivity, com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success("Assistant Started")
                    }
                }
                "stopAssistant" -> {
                    val serviceIntent = android.content.Intent(this@MainActivity, com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java)
                    stopService(serviceIntent)
                    result.success("Assistant Stopped")
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission(result)
                }
                "isAssistantRunning" -> {
                    result.success(isServiceRunning(com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java))
                }
                "setGestureMode" -> {
                    val mode = call.argument<String>("mode") ?: "both"
                    val intent = android.content.Intent("com.aura.mobile.assistant.SET_GESTURE_MODE")
                    intent.putExtra("mode", mode)
                    sendBroadcast(intent)
                    result.success("Gesture mode set to $mode")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                val intent = android.content.Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, 1234)
                result.success("Requested Settings")
            } else {
                result.success("Already Granted")
            }
        } else {
            result.success("Not required below M")
        }
    }

    private fun launchApp(appName: String, result: MethodChannel.Result) {
        val pm = packageManager
        val packages = pm.getInstalledPackages(0)

        // Simple fuzzy match algorithm
        var bestMatchPkg: String? = null
        var bestMatchLabel: String? = null
        val query = appName.lowercase()

        for (pkg in packages) {
            val appInfo = pkg.applicationInfo
            if (appInfo == null) continue

            val label = pm.getApplicationLabel(appInfo).toString()
            if (label.lowercase() == query) {
                bestMatchPkg = pkg.packageName
                bestMatchLabel = label
                break // Exact match found
            }
            if (label.lowercase().contains(query)) {
                // Keep the first partial match or improve logic
                if (bestMatchPkg == null) {
                   bestMatchPkg = pkg.packageName
                   bestMatchLabel = label
                }
            }
        }

        if (bestMatchPkg != null) {
            try {
                val launchIntent = pm.getLaunchIntentForPackage(bestMatchPkg)
                if (launchIntent != null) {
                    startActivity(launchIntent)
                    result.success("Launched $bestMatchLabel")
                } else {
                    result.error("LAUNCH_FAILED", "Could not create intent for $bestMatchPkg", null)
                }
            } catch (e: Exception) {
                 result.error("ERROR", e.message, null)
            }
        } else {
            result.error("APP_NOT_FOUND", "Could not find app '$appName'", null)
        }
    }

    private fun openSettings(type: String?, result: MethodChannel.Result) {
        try {
            val intent = when (type) {
                "wifi" -> android.content.Intent(android.provider.Settings.ACTION_WIFI_SETTINGS)
                "bluetooth" -> android.content.Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                else -> android.content.Intent(android.provider.Settings.ACTION_SETTINGS)
            }
            startActivity(intent)
            result.success("Settings opened")
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun openCamera(result: MethodChannel.Result) {
         try {
            val intent = android.content.Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)
            startActivity(intent)
            result.success("Camera opened")
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun dialContact(name: String?, result: MethodChannel.Result) {
        if (name == null) {
             result.error("INVALID", "Name required", null)
             return
        }

        // Check if it looks like a number
        if (name.all { it.isDigit() || it == '+' || it == ' ' || it == '-' }) {
             val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
             intent.data = android.net.Uri.parse("tel:$name")
             startActivity(intent)
             result.success("Dialing $name")
             return
        }

        // Try to find contact by name
        try {
            val resolver = contentResolver
            val cursor = resolver.query(
                android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                null,
                "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                null
            )

            var number: String? = null
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (index != -1) number = cursor.getString(index)
                cursor.close()
            }

            if (number != null) {
                 val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
                 intent.data = android.net.Uri.parse("tel:$number")
                 startActivity(intent)
                 result.success("Dialing $name ($number)")
            } else {
                 // Fallback to searching in contacts app
                 val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                 intent.data = android.net.Uri.withAppendedPath(android.provider.ContactsContract.Contacts.CONTENT_FILTER_URI, android.net.Uri.encode(name))
                 startActivity(intent)
                 result.success("Searching contact $name")
            }

        } catch (e: Exception) {
             val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
             startActivity(intent)
             result.success("Opened Dialer (Contact search failed or permission denied)")
        }
    }

    private fun sendSMS(name: String?, message: String?, result: MethodChannel.Result) {
         if (name == null) {
             result.error("INVALID", "Name/Number required", null)
             return
         }

         // 1. Resolve number (reuse logic or duplication)
         var number = name
         if (!name.all { it.isDigit() || it == '+' || it == ' ' || it == '-' }) {
             try {
                val cursor = contentResolver.query(
                    android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    null,
                    "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                    arrayOf("%$name%"),
                    null
                )
                if (cursor != null && cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                    if (index != -1) number = cursor.getString(index)
                    cursor.close()
                }
             } catch (e: Exception) {
                 // Ignore
             }
         }

         try {
             val intent = android.content.Intent(android.content.Intent.ACTION_SENDTO)
             intent.data = android.net.Uri.parse("smsto:$number")
             intent.putExtra("sms_body", message ?: "")
             startActivity(intent)
             result.success("Opened SMS app for $number")
         } catch (e: Exception) {
             result.error("ERROR", e.message, null)
         }
    }

    // Existing helper methods
    private fun getAvailableMemory(): Long {
        val memoryInfo = ActivityManager.MemoryInfo()
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.availMem
    }

    private fun getTotalMemory(): Long {
        val memoryInfo = ActivityManager.MemoryInfo()
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.totalMem
    }

    private fun sendSMSDirect(number: String, message: String, result: MethodChannel.Result) {
        try {
            val smsManager = SmsManager.getDefault()
            smsManager.sendTextMessage(number, null, message, null, null)
            result.success("SMS Sent to $number")
        } catch (e: Exception) {
            result.error("SMS_FAILED", e.message, null)
        }
    }

    private fun callPhoneDirect(number: String, result: MethodChannel.Result) {
        try {
            val intent = android.content.Intent(android.content.Intent.ACTION_CALL)
            intent.data = android.net.Uri.parse("tel:$number")
            startActivity(intent)
            result.success("Call initiated to $number")
        } catch (e: Exception) {
            result.error("CALL_FAILED", e.message, null)
        }
    }

    private fun toggleTorch(state: Boolean, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) {
            result.error("UNSUPPORTED", "Torch requires Android M+", null)
            return
        }
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
            // Find a camera with flash support
            var cameraId: String? = null
            for (id in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val hasFlash = characteristics.get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE)
                if (hasFlash == true) {
                    cameraId = id
                    break
                }
            }

            if (cameraId != null) {
                cameraManager.setTorchMode(cameraId, state)
                result.success("Torch toggled to $state")
            } else {
                result.error("NO_FLASH", "No camera with flash found", null)
            }
        } catch (e: Exception) {
            result.error("TORCH_ERROR", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }

    override fun onDestroy() {
        super.onDestroy()
        // Clear handler to prevent stale refs to dead Flutter engine
        AssistantForegroundService.aiRequestHandler = null
    }
}
