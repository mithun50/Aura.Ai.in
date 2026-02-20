package com.aura.mobile.aura_mobile.assistant

sealed class ParsedCommand {
    data class OpenApp(val appName: String) : ParsedCommand()
    data class CallContact(val contactName: String) : ParsedCommand()
    data class SendSms(val contactName: String, val message: String) : ParsedCommand()
    data class TurnTorch(val state: Boolean) : ParsedCommand()
    object OpenCamera : ParsedCommand()
    object OpenWifiSettings : ParsedCommand()
    object OpenBluetoothSettings : ParsedCommand()
    object OpenSettings : ParsedCommand()
    object Unknown : ParsedCommand()
}

object CommandParser {
    fun parse(rawText: String): ParsedCommand {
        val text = rawText.lowercase().trim()

        // Open App
        if (text.startsWith("open ") && !text.contains("camera") && !text.contains("settings") && !text.contains("wifi") && !text.contains("bluetooth")) {
            val appName = text.removePrefix("open ").trim()
            if (appName.isNotEmpty()) return ParsedCommand.OpenApp(appName)
        }
        if (text.startsWith("launch ")) {
            val appName = text.removePrefix("launch ").trim()
            if (appName.isNotEmpty()) return ParsedCommand.OpenApp(appName)
        }

        // Call Contact
        if (text.startsWith("call ")) {
            val contactName = text.removePrefix("call ").trim()
            if (contactName.isNotEmpty()) return ParsedCommand.CallContact(contactName)
        }
        if (text.startsWith("dial ")) {
            val contactName = text.removePrefix("dial ").trim()
            if (contactName.isNotEmpty()) return ParsedCommand.CallContact(contactName)
        }

        // Send SMS
        // Format 1: "send message to [name] saying [message]"
        if (text.startsWith("send message to ")) {
            val remainder = text.removePrefix("send message to ").trim()
            val splitBySaying = remainder.split(" saying ")
            if (splitBySaying.size == 2) {
                return ParsedCommand.SendSms(splitBySaying[0].trim(), splitBySaying[1].trim())
            }
            if (remainder.isNotEmpty()) {
                return ParsedCommand.SendSms(remainder, "") // Ask for message later
            }
        }
        
        // Format 2: "text [name] [message]"
        if (text.startsWith("text ")) {
            val remainder = text.removePrefix("text ").trim()
            val firstSpace = remainder.indexOf(' ')
            if (firstSpace != -1) {
                val name = remainder.substring(0, firstSpace).trim()
                val msg = remainder.substring(firstSpace + 1).trim()
                return ParsedCommand.SendSms(name, msg)
            }
        }

        // Torch Control
        if (text.contains("turn on torch") || text.contains("flashlight on") || text.contains("torch on")) {
            return ParsedCommand.TurnTorch(true)
        }
        if (text.contains("turn off torch") || text.contains("flashlight off") || text.contains("torch off")) {
            return ParsedCommand.TurnTorch(false)
        }

        // Open Camera
        if (text.contains("open camera") || text.contains("take photo")) {
            return ParsedCommand.OpenCamera
        }

        // Open Settings
        if (text.contains("wifi settings")) {
            return ParsedCommand.OpenWifiSettings
        }
        if (text.contains("bluetooth settings")) {
            return ParsedCommand.OpenBluetoothSettings
        }
        if (text.contains("open settings")) {
            return ParsedCommand.OpenSettings
        }

        return ParsedCommand.Unknown
    }
}
