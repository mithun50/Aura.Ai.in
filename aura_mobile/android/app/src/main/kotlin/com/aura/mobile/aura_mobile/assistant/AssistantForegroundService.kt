package com.aura.mobile.aura_mobile.assistant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat


class AssistantForegroundService : Service() {

    companion object {
        var currentState: String = "IDLE"
        const val ACTION_LISTEN_NOW = "com.aura.mobile.assistant.LISTEN_NOW"
        const val ACTION_CANCEL = "com.aura.mobile.assistant.CANCEL"
        const val ACTION_AI_REQUEST = "com.aura.mobile.assistant.AI_REQUEST"
        const val ACTION_AI_RESPONSE = "com.aura.mobile.assistant.AI_RESPONSE"
    }

    // Receives the notification action button tap and cancel actions
    private val actionReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_LISTEN_NOW -> triggerAssistant()
                ACTION_CANCEL -> cancelAssistant()
            }
        }
    }

    private lateinit var shakeDetector: ShakeDetector
    private lateinit var voiceRecognitionService: VoiceRecognitionService
    private lateinit var deviceControlService: DeviceControlService
    private lateinit var ttsManager: TtsManager
    private lateinit var overlayManager: OverlayManager
    private lateinit var powerButtonDetector: PowerButtonDetector

    private val CHANNEL_ID = "AuraAssistantChannel"
    private val NOTIFICATION_ID = 1001

    private var isWaitingForConfirmation = false
    private var isWaitingForMessage = false
    private var isWaitingForContactSelection = false
    private var pendingCommand: ParsedCommand? = null
    private var pendingCallContacts: List<DeviceControlService.ContactMatch> = emptyList()

    private var isWaitingForAI = false
    private val aiTimeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val aiTimeoutRunnable = Runnable {
        if (isWaitingForAI) {
            isWaitingForAI = false
            ttsManager.speak("AI is taking too long. Please try again.")
            broadcastState("IDLE")
        }
    }

    // Receives AI_RESPONSE from MainActivity (which got it from Flutter)
    private val aiResponseReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            if (!isWaitingForAI) return
            isWaitingForAI = false
            aiTimeoutHandler.removeCallbacks(aiTimeoutRunnable)
            val response = intent?.getStringExtra("response") ?: "I couldn't get a response."
            broadcastState("SPEAKING")
            ttsManager.speak(response)
            broadcastState("IDLE")
        }
    }

    // Gesture mode: "shake", "power", or "both" (default)
    private var gestureMode: String = "both"
    private val gestureModeReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            if (intent?.action == "com.aura.mobile.assistant.SET_GESTURE_MODE") {
                gestureMode = intent.getStringExtra("mode") ?: "both"
                Log.d("AuraAssistant", "Gesture mode changed to: $gestureMode")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("AuraAssistant", "Service Created")

        createNotificationChannel()

        overlayManager = OverlayManager(this)
        deviceControlService = DeviceControlService(this)
        
        ttsManager = TtsManager(this) {
            Log.d("AuraAssistant", "TTS Initialized")
        }

        voiceRecognitionService = VoiceRecognitionService(this,
            onResult = { text ->
                Log.d("AuraAssistant", "Recognized: $text")
                handleRecognizedText(text)
            },
            onError = { error ->
                Log.e("AuraAssistant", "Voice Error: $error")
                if (error != "Speech timeout" && error != "No match") {
                    ttsManager.speak("Sorry, I didn't catch that.")
                }
            }
        )

        shakeDetector = ShakeDetector(this) {
            Log.d("AuraAssistant", "Shake Detected!")
            if (gestureMode == "shake" || gestureMode == "both") triggerAssistant()
        }
        shakeDetector.start()

        // Power button double-press detector
        powerButtonDetector = PowerButtonDetector {
            Log.d("AuraAssistant", "Power double-press detected!")
            if (gestureMode == "power" || gestureMode == "both") triggerAssistant()
        }
        val powerFilter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(powerButtonDetector, powerFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(powerButtonDetector, powerFilter)
        }

        // Listen for gesture mode changes from settings page
        val gestureModeFilter = IntentFilter("com.aura.mobile.assistant.SET_GESTURE_MODE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(gestureModeReceiver, gestureModeFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(gestureModeReceiver, gestureModeFilter)
        }

        // Show the floating mic bubble (easy one-tap trigger)
        overlayManager.showFloatingBubble { triggerAssistant() }

        // Listen for AI responses from Flutter via MainActivity
        val aiResponseFilter = IntentFilter(ACTION_AI_RESPONSE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(aiResponseReceiver, aiResponseFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(aiResponseReceiver, aiResponseFilter)
        }

        // Listen for notification action taps and cancel actions
        val actionFilter = IntentFilter().apply {
            addAction(ACTION_LISTEN_NOW)
            addAction(ACTION_CANCEL)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, actionFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(actionReceiver, actionFilter)
        }
    }

    /** Shared trigger for both shake and power-button activation */
    private fun triggerAssistant() {
        if (isWaitingForConfirmation || isWaitingForContactSelection || isWaitingForMessage || isWaitingForAI) return
        vibrate()
        broadcastState("LISTENING")
        overlayManager.showOverlay("LISTENING")
        ttsManager.speak("Listening")
        voiceRecognitionService.startListening()
    }

    private fun cancelAssistant() {
        voiceRecognitionService.stopListening()
        ttsManager.stop()
        isWaitingForConfirmation = false
        isWaitingForMessage = false
        isWaitingForContactSelection = false
        isWaitingForAI = false
        aiTimeoutHandler.removeCallbacks(aiTimeoutRunnable)
        pendingCommand = null
        broadcastState("IDLE")
    }

    private fun broadcastState(state: String) {
        currentState = state
        overlayManager.updateState(state) // Update native overlay
        val intent = Intent("com.aura.mobile.assistant.STATE_CHANGE")
        intent.putExtra("state", state)
        sendBroadcast(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notificationIntent = Intent(this, com.aura.mobile.aura_mobile.MainActivity::class.java)
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val listenPendingIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(ACTION_LISTEN_NOW),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AURA Assistant")
            .setContentText("Shake, bubble, or tap Listen to activate")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(openPendingIntent)
            .addAction(android.R.drawable.ic_btn_speak_now, "🎤 Listen", listenPendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    /** When the app is swiped from recents, restart the service automatically */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d("AuraAssistant", "Task removed — scheduling service restart")
        val restartIntent = Intent(applicationContext, AssistantForegroundService::class.java)
        val pendingRestart = PendingIntent.getService(
            applicationContext,
            1,
            restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        alarmManager.set(
            android.app.AlarmManager.ELAPSED_REALTIME,
            android.os.SystemClock.elapsedRealtime() + 1000L,
            pendingRestart
        )
    }

    private fun handleRecognizedText(text: String) {
        if (isWaitingForMessage && pendingCommand != null) {
            if (pendingCommand is ParsedCommand.SendSms) {
               val oldCmd = pendingCommand as ParsedCommand.SendSms
               pendingCommand = ParsedCommand.SendSms(oldCmd.contactName, text)
               isWaitingForMessage = false
               isWaitingForConfirmation = true
               ttsManager.speak("Do you want to send this message to ${oldCmd.contactName}? $text")
               voiceRecognitionService.startListening()
               return
            }
        }
        if (isWaitingForConfirmation && pendingCommand != null) {
            broadcastState("PROCESSING")
            val response = text.lowercase()
            if (response == "yes" || response == "yeah" || response == "sure" || response == "send it") {
                executePendingCommand()
            } else {
                ttsManager.speak("Cancelled.")
                overlayManager.updateState("IDLE")
            }
            broadcastState("IDLE")
            isWaitingForConfirmation = false
            pendingCommand = null
            return
        }

        broadcastState("PROCESSING")
        val command = CommandParser.parse(text)
        when (command) {
            is ParsedCommand.SendSms -> {
                pendingCommand = command
                if (command.message.isEmpty()) {
                     isWaitingForMessage = true
                     ttsManager.speak("What is the message for ${command.contactName}?")
                     broadcastState("LISTENING")
                     voiceRecognitionService.startListening()
                } else {
                     isWaitingForConfirmation = true
                     ttsManager.speak("Do you want to send this message to ${command.contactName}? ${command.message}")
                     broadcastState("LISTENING")
                     voiceRecognitionService.startListening()
                }
            }
            is ParsedCommand.CallContact -> {
                // Look up all matching contacts first
                val matches = deviceControlService.findContacts(command.contactName)
                when {
                    matches.isEmpty() -> {
                        ttsManager.speak("I couldn't find a contact named ${command.contactName}")
                        broadcastState("IDLE")
                    }
                    matches.size == 1 -> {
                        // Single match: confirm and call
                        pendingCommand = command
                        pendingCallContacts = matches
                        isWaitingForConfirmation = true
                        ttsManager.speak("Do you want to call ${matches.first().displayName}?")
                        broadcastState("LISTENING")
                        voiceRecognitionService.startListening()
                    }
                    else -> {
                        // Multiple matches: show disambiguation UI in overlay
                        pendingCallContacts = matches
                        isWaitingForContactSelection = true
                        val names = matches.mapIndexed { i, c -> "${i + 1}. ${c.displayName}" }.joinToString(", ")
                        ttsManager.speak("I found ${matches.size} contacts named ${command.contactName}. ${names}. Please tap one to call.")
                        overlayManager.showContactPicker(matches) { selected ->
                            isWaitingForContactSelection = false
                            deviceControlService.callByNumber(selected.number, selected.displayName, ttsManager)
                            broadcastState("IDLE")
                        }
                    }
                }
            }
            is ParsedCommand.WebSearch -> {
                requestAIProcessing("search for: ${command.query}")
            }
            is ParsedCommand.Unknown -> {
                requestAIProcessing(text)
            }
            else -> {
                deviceControlService.executeCommand(command, ttsManager)
                broadcastState("IDLE")
            }
        }
    }

    private fun requestAIProcessing(text: String) {
        isWaitingForAI = true
        broadcastState("PROCESSING")
        ttsManager.speak("Let me think about that.")

        val intent = Intent(ACTION_AI_REQUEST)
        intent.putExtra("query", text)
        sendBroadcast(intent)

        // 30-second timeout in case Flutter engine is not running
        aiTimeoutHandler.postDelayed(aiTimeoutRunnable, 30_000L)
    }

    private fun executePendingCommand() {
        pendingCommand?.let { cmd ->
            when (cmd) {
                is ParsedCommand.SendSms -> deviceControlService.sendSMSDirect(cmd.contactName, cmd.message, ttsManager)
                is ParsedCommand.CallContact -> {
                    val contact = pendingCallContacts.firstOrNull()
                    if (contact != null) {
                        deviceControlService.callByNumber(contact.number, contact.displayName, ttsManager)
                    } else {
                        deviceControlService.callContact(cmd.contactName, ttsManager)
                    }
                }
                else -> deviceControlService.executeCommand(cmd, ttsManager)
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "AURA Assistant Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun vibrate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            val vibrator = vibratorManager.defaultVibrator
            vibrator.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(100)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        shakeDetector.stop()
        voiceRecognitionService.destroy()
        ttsManager.shutdown()
        overlayManager.hideOverlay()
        overlayManager.hideFloatingBubble()
        try { unregisterReceiver(powerButtonDetector) } catch (e: Exception) { }
        try { unregisterReceiver(gestureModeReceiver) } catch (e: Exception) { }
        try { unregisterReceiver(actionReceiver) } catch (e: Exception) { }
        try { unregisterReceiver(aiResponseReceiver) } catch (e: Exception) { }
        aiTimeoutHandler.removeCallbacks(aiTimeoutRunnable)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
