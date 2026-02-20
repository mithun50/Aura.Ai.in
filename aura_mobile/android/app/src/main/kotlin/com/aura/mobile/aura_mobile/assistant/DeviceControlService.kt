package com.aura.mobile.aura_mobile.assistant

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.telephony.SmsManager
import android.hardware.camera2.CameraManager

class DeviceControlService(private val context: Context) {

    /** Represents a single contact match with display name and phone number */
    data class ContactMatch(val displayName: String, val number: String)

    /** Find all contacts whose display name contains [name], returning up to 10 results */
    fun findContacts(name: String): List<ContactMatch> {
        val results = mutableListOf<ContactMatch>()
        try {
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )
            cursor?.use { c ->
                val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val seen = mutableSetOf<String>()
                while (c.moveToNext() && results.size < 10) {
                    val displayName = if (nameIdx != -1) c.getString(nameIdx) else continue
                    val number = if (numIdx != -1) c.getString(numIdx) else continue
                    // Deduplicate by number
                    val key = "${displayName.lowercase()}|${number.replace(" ", "")}"
                    if (seen.add(key)) {
                        results.add(ContactMatch(displayName, number))
                    }
                }
            }
        } catch (e: Exception) {
            // Missing permission handled by caller
        }
        return results
    }

    /** Call a specific phone number directly */
    fun callByNumber(number: String, label: String, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_CALL)
            intent.data = Uri.parse("tel:${number.replace(" ", "")}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Calling $label")
        } catch (e: Exception) {
            val intent = Intent(Intent.ACTION_DIAL)
            intent.data = Uri.parse("tel:${number.replace(" ", "")}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    fun executeCommand(command: ParsedCommand, ttsManager: TtsManager?) {
        when (command) {
            is ParsedCommand.OpenApp -> openApp(command.appName, ttsManager)
            is ParsedCommand.CallContact -> callContact(command.contactName, ttsManager)
            is ParsedCommand.SendSms -> {
                // Should only be called if properly confirmed. AssistantForegroundService will handle confirmation logic.
            }
            is ParsedCommand.TurnTorch -> turnTorch(command.state, ttsManager)
            is ParsedCommand.OpenCamera -> openCamera(ttsManager)
            is ParsedCommand.OpenWifiSettings -> openWifiSettings(ttsManager)
            is ParsedCommand.OpenBluetoothSettings -> openBluetoothSettings(ttsManager)
            is ParsedCommand.OpenSettings -> openSettings(ttsManager)
            is ParsedCommand.Unknown -> {
                ttsManager?.speak("I didn't understand the command.")
            }
        }
    }

    fun openApp(appName: String, ttsManager: TtsManager? = null) {
        val pm = context.packageManager
        val packages = pm.getInstalledPackages(0)
        
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
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(launchIntent)
                    ttsManager?.speak("Opening $bestMatchLabel")
                } else {
                    ttsManager?.speak("Could not open $appName")
                }
            } catch (e: Exception) {
                ttsManager?.speak("Error opening $appName")
            }
        } else {
            ttsManager?.speak("App $appName not found")
        }
    }

    fun callContact(name: String, ttsManager: TtsManager? = null) {
        val matches = findContacts(name)
        if (matches.isEmpty()) {
            ttsManager?.speak("Contact $name not found")
            return
        }
        // Only one match — call immediately
        val first = matches.first()
        callByNumber(first.number, first.displayName, ttsManager)
    }

    fun sendSMSDirect(name: String, message: String, ttsManager: TtsManager? = null) {
        var number: String? = null
        try {
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                null
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (index != -1) number = cursor.getString(index)
                cursor.close()
            }
        } catch (e: Exception) {
        }

        if (number != null) {
            try {
                val smsManager = SmsManager.getDefault()
                smsManager.sendTextMessage(number, null, message, null, null)
                ttsManager?.speak("Message sent to $name")
            } catch (e: Exception) {
                ttsManager?.speak("Failed to send message")
            }
        } else {
             ttsManager?.speak("Contact $name not found for messaging")
        }
    }

    fun turnTorch(state: Boolean, ttsManager: TtsManager? = null) {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
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
                ttsManager?.speak(if (state) "Torch turned on" else "Torch turned off")
            } else {
                ttsManager?.speak("No flashlight found")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Error toggling torch")
        }
    }

    fun openCamera(ttsManager: TtsManager? = null) {
        try {
             // For simplicity, opening the default camera intent
             // In foreground service, starting an activity requires FLAG_ACTIVITY_NEW_TASK
            val intent = Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening camera")
        } catch (e: Exception) {
            ttsManager?.speak("Error opening camera")
        }
    }

    fun openWifiSettings(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening Wi-Fi settings")
        } catch (e: Exception) { }
    }

    fun openBluetoothSettings(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening Bluetooth settings")
        } catch (e: Exception) { }
    }

    fun openSettings(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Settings.ACTION_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening settings")
        } catch (e: Exception) { }
    }
}
