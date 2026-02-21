package com.aura.mobile.aura_mobile.assistant

sealed class ParsedCommand {
    data class OpenApp(val appName: String) : ParsedCommand()
    data class CallContact(val contactName: String) : ParsedCommand()
    data class SendSms(val contactName: String, val message: String) : ParsedCommand()
    data class TurnTorch(val state: Boolean) : ParsedCommand()
    data class SetTimer(val minutes: Int) : ParsedCommand()
    data class SetAlarm(val hour: Int, val minute: Int) : ParsedCommand()
    data class WebSearch(val query: String) : ParsedCommand()
    data class PlayYouTube(val query: String) : ParsedCommand()
    object GetTime : ParsedCommand()
    object GetDate : ParsedCommand()
    object GetBattery : ParsedCommand()
    object MaxVolume : ParsedCommand()
    object MuteVolume : ParsedCommand()
    object OpenCamera : ParsedCommand()
    object OpenWifiSettings : ParsedCommand()
    object OpenBluetoothSettings : ParsedCommand()
    object OpenSettings : ParsedCommand()
    object Unknown : ParsedCommand()
}

object CommandParser {
    fun parse(rawText: String): ParsedCommand {
        var text = rawText.lowercase().trim()

        // 1. Remove filler words to make parsing robust
        val fillers = listOf(
            "can you ", "could you ", "please ", "for me", "hey aura ", "aura ",
            "just ", "quickly ", "i want to ", "i need to ", "i'd like to ",
            "i would like to ", "go ahead and ", "would you ", "will you ",
            "kindly ", "hey ", "yo "
        )
        for (filler in fillers) {
            text = text.replace(filler, "")
        }
        text = text.trim()

        // YouTube Search / Play
        if (text.contains("on youtube") || text.contains("in youtube") || text.startsWith("play ") || text.startsWith("youtube ")) {
            var query = text.replace("play ", "")
                .replace("on youtube", "")
                .replace("in youtube", "")
                .replace("open ", "")
                .replace("search for ", "")
                .replace("youtube ", "")
                .trim()
            if (query.isNotEmpty() && (text.contains("youtube") || text.startsWith("play "))) {
                return ParsedCommand.PlayYouTube(query)
            }
        }

        // Open App (expanded: fire up, pull up, bring up, load)
        val openPrefixes = listOf("open ", "launch ", "start ", "fire up ", "pull up ", "bring up ", "load ")
        val matchedOpenPrefix = openPrefixes.firstOrNull { text.startsWith(it) }
        if (matchedOpenPrefix != null &&
            !text.contains("camera") && !text.contains("settings") && !text.contains("wifi") && !text.contains("bluetooth")) {
            val appName = text.removePrefix(matchedOpenPrefix).trim()
            if (appName.isNotEmpty()) {
                // Check for compound "open youtube and play/search X" pattern
                val compoundPlayRegex = Regex("^youtube\\s+and\\s+(play|search|search for)\\s+(.+)", RegexOption.IGNORE_CASE)
                val compoundMatch = compoundPlayRegex.find(appName)
                if (compoundMatch != null) {
                    val query = compoundMatch.groupValues[2].trim()
                    if (query.isNotEmpty()) return ParsedCommand.PlayYouTube(query)
                }
                return ParsedCommand.OpenApp(appName)
            }
        }

        // Call Contact (expanded: ring up, phone, buzz, give X a call/ring)
        val callPrefixes = listOf("call ", "dial ", "ring up ", "phone ", "buzz ")
        val matchedCallPrefix = callPrefixes.firstOrNull { text.startsWith(it) }
        if (matchedCallPrefix != null) {
            val contactName = text.removePrefix(matchedCallPrefix).trim()
            if (contactName.isNotEmpty()) return ParsedCommand.CallContact(contactName)
        }
        // "give X a call/ring/buzz" pattern
        val giveCallRegex = Regex("^give\\s+(.+?)\\s+a\\s+(call|ring|buzz)")
        val giveCallMatch = giveCallRegex.find(text)
        if (giveCallMatch != null) {
            val contactName = giveCallMatch.groupValues[1].trim()
            if (contactName.isNotEmpty()) return ParsedCommand.CallContact(contactName)
        }

        // Send SMS (expanded: drop a text/message to, shoot a message to)
        // Format 1: "send message to [name] saying/as [message]"
        if (text.startsWith("send message to ") || text.startsWith("send sms to ") || text.startsWith("send text to ")) {
            val prefixes = listOf("send message to ", "send sms to ", "send text to ")
            val prefix = prefixes.first { text.startsWith(it) }
            val remainder = text.removePrefix(prefix).trim()
            // Split on "saying" or "as" separator
            val separatorRegex = Regex("\\s+(saying|as)\\s+")
            val splitMatch = separatorRegex.find(remainder)
            if (splitMatch != null) {
                val name = remainder.substring(0, splitMatch.range.first).trim()
                val msg = remainder.substring(splitMatch.range.last + 1).trim()
                return ParsedCommand.SendSms(name, msg)
            }
            if (remainder.isNotEmpty()) {
                return ParsedCommand.SendSms(remainder, "")
            }
        }

        // Format 1b: "drop a text/message to [name]", "shoot a message to [name]"
        val dropSmsRegex = Regex("^(drop a (text|line|message)|shoot a (message|text))\\s+to\\s+(.+)")
        val dropSmsMatch = dropSmsRegex.find(text)
        if (dropSmsMatch != null) {
            val afterTo = dropSmsMatch.groupValues[4].trim()
            val sepRegex = Regex("\\s+(saying|as)\\s+")
            val sepMatch = sepRegex.find(afterTo)
            if (sepMatch != null) {
                val name = afterTo.substring(0, sepMatch.range.first).trim()
                val msg = afterTo.substring(sepMatch.range.last + 1).trim()
                return ParsedCommand.SendSms(name, msg)
            }
            if (afterTo.isNotEmpty()) return ParsedCommand.SendSms(afterTo, "")
        }

        // Format 2: "text [name] [message]" — with phone-number-aware parsing
        if (text.startsWith("text ")) {
            val remainder = text.removePrefix("text ").trim()
            val tokens = remainder.split(Regex("\\s+"))
            if (tokens.isNotEmpty()) {
                val hasLetters = { s: String -> s.any { it.isLetter() } }
                if (hasLetters(tokens.first())) {
                    // Name token (e.g. "text appu as hai" or "text john hello")
                    val name = tokens.first()
                    var msg = remainder.substring(name.length).trim()
                    // Strip "as" / "saying" separator from message start
                    val separatorRegex = Regex("^(as|saying)\\s+", RegexOption.IGNORE_CASE)
                    msg = msg.replace(separatorRegex, "")
                    if (name.isNotEmpty()) return ParsedCommand.SendSms(name, msg)
                } else {
                    // Phone number with possible spaces (e.g. "text 98445 56496 hello")
                    val phoneParts = mutableListOf<String>()
                    var digitCount = 0
                    val maxDigits = if (tokens.first().startsWith("+")) 14 else 10
                    var processedCount = 0
                    for (token in tokens) {
                        if (hasLetters(token) || digitCount >= maxDigits) break
                        phoneParts.add(token)
                        digitCount += token.count { it.isDigit() }
                        processedCount++
                    }
                    if (phoneParts.isNotEmpty()) {
                        val name = phoneParts.joinToString(" ")
                        val msg = tokens.drop(processedCount).joinToString(" ")
                        return ParsedCommand.SendSms(name, msg)
                    }
                }
            }
        }

        // Torch Control (expanded: turn the light on/off, light up, lights on/off)
        if (text.contains("turn on torch") || text.contains("flashlight on") || text.contains("torch on") ||
            text.contains("turn the light on") || text.contains("light up my phone") || text.contains("lights on")) {
            return ParsedCommand.TurnTorch(true)
        }
        if (text.contains("turn off torch") || text.contains("flashlight off") || text.contains("torch off") ||
            text.contains("turn the light off") || text.contains("lights off")) {
            return ParsedCommand.TurnTorch(false)
        }

        // Time & Date
        if (text.contains("what time is it") || text == "time") {
            return ParsedCommand.GetTime
        }
        if (text.contains("what is today") || text.contains("today's date") || text == "date") {
            return ParsedCommand.GetDate
        }

        // Battery
        if (text.contains("battery") || text.contains("how much juice")) {
            return ParsedCommand.GetBattery
        }

        // Volume
        if (text.contains("max volume") || text.contains("volume to max") || text.contains("turn it up")) {
            return ParsedCommand.MaxVolume
        }
        if (text.contains("mute") || text.contains("silence my phone")) {
            return ParsedCommand.MuteVolume
        }

        // Timers & Alarms (Basic regex parsing)
        if (text.contains("timer for")) {
            val words = text.split(" ")
            for (i in words.indices) {
                if (words[i] == "timer" || words[i] == "for") {
                    val num = words.getOrNull(i + 1)?.toIntOrNull()
                        ?: words.getOrNull(i + 2)?.toIntOrNull()
                    if (num != null) {
                        return ParsedCommand.SetTimer(num)
                    }
                }
            }
        }

        // Web Search
        if (text.startsWith("search ") || text.startsWith("google ") || text.startsWith("look up ")) {
            val query = text.replace("search for ", "").replace("search ", "")
                            .replace("google ", "").replace("look up ", "").trim()
            if (query.isNotEmpty()) return ParsedCommand.WebSearch(query)
        }

        // Open Camera (expanded: snap a photo/pic, shoot a picture, capture, take a snap/selfie)
        if (text.contains("open camera") || text.contains("take photo") || text.contains("take a picture") ||
            text.contains("snap a photo") || text.contains("snap a pic") || text.contains("shoot a picture") ||
            text.contains("capture a photo") || text.contains("take a snap") || text.contains("take a selfie") ||
            text.contains("capture a selfie")) {
            return ParsedCommand.OpenCamera
        }

        // Open Settings (expanded: take me to X settings, bring up wifi/bluetooth)
        if (text.contains("wifi settings") || text.contains("bring up wifi") || text.contains("take me to wifi")) {
            return ParsedCommand.OpenWifiSettings
        }
        if (text.contains("bluetooth settings") || text.contains("bring up bluetooth") || text.contains("take me to bluetooth")) {
            return ParsedCommand.OpenBluetoothSettings
        }
        if (text.contains("open settings") || text.contains("take me to settings") || text.contains("bring up settings")) {
            return ParsedCommand.OpenSettings
        }

        return ParsedCommand.Unknown
    }
}
