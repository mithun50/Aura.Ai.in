import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IntentType {
  normalChat,
  webSearch,
  urlScrape,
  memoryStore,
  memoryRetrieve,
  openApp,
  closeApp,
  openSettings,
  openCamera,
  dialContact,
  sendSMS,
  torchControl
}

final intentDetectionServiceProvider = Provider((ref) => IntentDetectionService());

class IntentDetectionService {
  /// Strictly rule-based intent detection as per SuperGravity architecture.
  /// Does NOT use LLM.
  Future<IntentType> detectIntent(String message, {List<Map<String, String>>? history, bool hasDocuments = false}) async {
    debugPrint("INTENT_DETECTION: Analyzing message: '$message'");
    final lowerMessage = message.trim().toLowerCase();

    // 0️⃣ Torch / Flashlight (High Priority)
    final torchRegex = RegExp(
      r'\b(torch|flashlight|flash\s*light)\b',
      caseSensitive: false,
    );
    if (torchRegex.hasMatch(lowerMessage)) {
       if (lowerMessage.contains("on") ||
           lowerMessage.contains("off") ||
           lowerMessage.contains("enable") ||
           lowerMessage.contains("disable") ||
           lowerMessage.startsWith("torch") ||
           lowerMessage.startsWith("flashlight")) {
           return IntentType.torchControl;
       }
    }
    // "turn the light on/off", "light up my phone", "lights on/off"
    final torchNaturalRegex = RegExp(
      r'(turn\s+the\s+light\s+(on|off)|light\s+up\s+my\s+phone|lights?\s+(on|off))',
      caseSensitive: false,
    );
    if (torchNaturalRegex.hasMatch(lowerMessage)) {
      return IntentType.torchControl;
    }

    // 1️⃣ Memory Store
    // Matches: "remember ...", "don't forget ...", "keep in mind ...", "save this", "remind me"
    final memoryStoreRegex = RegExp(
      r'^(remember|don\x27t\s+forget|keep\s+in\s+mind|memorize|save\s+this|store\s+this|note\s+that|remind\s+me)\b',
      caseSensitive: false,
    );

    if (memoryStoreRegex.hasMatch(lowerMessage)) {
      debugPrint("INTENT_DETECTION: Detected Memory Store trigger -> memoryStore");
      return IntentType.memoryStore;
    }

    // 2️⃣ Memory Retrieve
    // Matches: "recall ...", "what was ...", "remind me ...", "bring up ..."
    final memoryRetrieveRegex = RegExp(
      r'^(recall|remember|remind\s+me|what\s+(was|did|is)|when\s+(was|is)|where\s+(was|is|did)|bring\s+up|search\s+memory|find\s+in\s+memory)\b',
      caseSensitive: false,
    );

    if (memoryRetrieveRegex.hasMatch(lowerMessage) || 
        lowerMessage.contains("do you remember") ||
        lowerMessage.contains("my memory")) {
      debugPrint("INTENT_DETECTION: Detected Memory Retrieval keywords -> memoryRetrieve");
      return IntentType.memoryRetrieve;
    }

    // 3️⃣ App Control / Device Actions
    
    // Open/Launch (expanded with natural variations)
    final openAppRegex = RegExp(
      r'^(open|launch|start|run|go\s+to|switch\s+to|fire\s+up|pull\s+up|bring\s+up|load)\s+(.+)',
      caseSensitive: false,
    );
    
    // Close/Kill
    final closeAppRegex = RegExp(
      r'^(close|kill|stop|exit|quit|shut\s+down)\s+(.+)',
      caseSensitive: false,
    );

    if (openAppRegex.hasMatch(lowerMessage)) {
       if (lowerMessage.contains("settings")) return IntentType.openSettings;
       if (lowerMessage.contains("camera")) return IntentType.openCamera;
       return IntentType.openApp;
    }

    if (closeAppRegex.hasMatch(lowerMessage)) {
      return IntentType.closeApp;
    }

    // Settings (expanded: "take me to X settings", "bring up wifi/bluetooth")
    final settingsRegex = RegExp(
      r'\b(settings|configuration|preferences|config)\b',
      caseSensitive: false,
    );

    if (settingsRegex.hasMatch(lowerMessage) &&
       (lowerMessage.contains("open") || lowerMessage.contains("show") || lowerMessage.contains("manage") || lowerMessage.contains("change") || lowerMessage.contains("take me") || lowerMessage.contains("bring up") || lowerMessage.contains("wifi") || lowerMessage.contains("bluetooth"))) {
      return IntentType.openSettings;
    }
    // "take me to wifi/bluetooth settings", "bring up wifi/bluetooth"
    final settingsNaturalRegex = RegExp(
      r'(take\s+me\s+to\s+.*(settings|wifi|bluetooth)|bring\s+up\s+(wifi|bluetooth))',
      caseSensitive: false,
    );
    if (settingsNaturalRegex.hasMatch(lowerMessage)) {
      return IntentType.openSettings;
    }

    // Camera (expanded: standalone "snap/shoot/capture a photo/pic/selfie")
    final cameraRegex = RegExp(
      r'\b(camera|photo|picture|selfie|pic)\b',
      caseSensitive: false,
    );

    if (cameraRegex.hasMatch(lowerMessage) &&
       (lowerMessage.contains("open") || lowerMessage.contains("start") || lowerMessage.contains("take") || lowerMessage.contains("capture") || lowerMessage.contains("snap") || lowerMessage.contains("shoot"))) {
      return IntentType.openCamera;
    }
    // Standalone camera commands: "snap a photo", "shoot a picture", "take a snap", "capture a selfie"
    final cameraNaturalRegex = RegExp(
      r'\b(snap|shoot|capture|take)\s+(a\s+)?(photo|picture|pic|selfie|snap)\b',
      caseSensitive: false,
    );
    if (cameraNaturalRegex.hasMatch(lowerMessage)) {
      return IntentType.openCamera;
    }

    // Calls (expanded: "ring up", "buzz", "give X a call/ring")
    final callRegex = RegExp(
      r'^(call|dial|phone|ring\s+up|ring|buzz|contact)\s+(.+)',
      caseSensitive: false,
    );
    if (callRegex.hasMatch(lowerMessage)) {
      return IntentType.dialContact;
    }
    // "give X a call/ring" pattern
    final callNaturalRegex = RegExp(
      r'give\s+(.+?)\s+a\s+(call|ring|buzz)',
      caseSensitive: false,
    );
    if (callNaturalRegex.hasMatch(lowerMessage)) {
      return IntentType.dialContact;
    }

    // SMS (expanded: "drop a text/line/message to X", "shoot a message to")
    final smsRegex = RegExp(
      r'^(send|write|shoot|text|message|msg)\s+.*(sms|text|message|msg)?',
      caseSensitive: false,
    );
    if (smsRegex.hasMatch(lowerMessage) && !lowerMessage.startsWith("remember") && !lowerMessage.startsWith("save")) {
       if (lowerMessage.startsWith("text") ||
           lowerMessage.startsWith("message") ||
           lowerMessage.contains(" sms ") ||
           lowerMessage.endsWith(" sms")) {
          return IntentType.sendSMS;
       }
    }
    // "drop a text/line/message to X", "shoot a message to X"
    final smsNaturalRegex = RegExp(
      r'(drop\s+a\s+(text|line|message)\s+to\s+|shoot\s+a\s+(message|text)\s+to\s+)',
      caseSensitive: false,
    );
    if (smsNaturalRegex.hasMatch(lowerMessage)) {
      return IntentType.sendSMS;
    }

    // 4️⃣ Web Search (Explicit Commands & Keywords)
    // Expanded keywords: google, how to, who is, what is, define, explain...
    final searchPrefixRegex = RegExp(
      r'^(search\s+for|search|find|lookup|look\s+up|google|browse|research|who\s+(is|was)|what\s+(is|was|are|were)|how\s+(to|do|can)|define|explain|tell\s+me\s+about)\s+(.+)',
      caseSensitive: false,
    );
    
    final contextKeywords = RegExp(r'\b(latest|news|weather|forecast|price\s+of|rate|stock|score)\b', caseSensitive: false);

    if (searchPrefixRegex.hasMatch(lowerMessage) ||
        lowerMessage.startsWith("[search]") ||
        contextKeywords.hasMatch(lowerMessage)) {
      debugPrint("INTENT_DETECTION: Detected search keywords -> webSearch");
      return IntentType.webSearch;
    }

    // 5️⃣ URL Detection (Fallback for direct URL input)
    if (containsURL(message)) {
      debugPrint("INTENT_DETECTION: Detected URL -> urlScrape");
      return IntentType.urlScrape;
    }

    // 5️⃣ Default
    return IntentType.normalChat;
  }

  bool containsURL(String text) {
    // Matches http/https OR common domain patterns like domain.com
    final urlRegex = RegExp(
      r'((https?:\/\/)|(www\.)|([-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]{2,6}))[^\s]*',
      caseSensitive: false
    );
    return urlRegex.hasMatch(text);
  }


  /// Extracts the clean search query by stripping command words.
  String extractSearchQuery(String message) {
    String clean = message.trim();
    // Regex to match the command prefix
    final commandRegex = RegExp(
      r'^(search\s+(for\s+)?|find\s+|lookup\s+|look\s+up\s+|google\s+|browse\s+|research\s+|who\s+(is|was)\s+|what\s+(is|was|are|were)\s+|how\s+(to|do|can)\s+|define\s+|explain\s+|tell\s+me\s+about\s+|\[search\]\s*)',
      caseSensitive: false,
    );
    
    final match = commandRegex.firstMatch(clean);
    if (match != null) {
      return clean.substring(match.end).trim();
    }
    return clean;
  }

  /// Extracts the URL from a message, potentially stripping "search" or "analyze"
  String extractUrl(String message) {
    final urlRegex = RegExp(
      r'((https?:\/\/)|(www\.)|([-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]{2,6}))[^\s]*',
      caseSensitive: false
    );
    final match = urlRegex.firstMatch(message);
    return match?.group(0) ?? message;
  }

  /// Extracts the content to be saved from a memory command.
  String extractMemoryContent(String message) {
    // Regex matching the prefix commands to strip them
    final memoryCommandRegex = RegExp(
      r'^(remember\s*(that|to)?|don\x27t\s+forget\s*(to)?|keep\s+in\s+mind\s*(that)?|memorize\s*(that)?|save\s+this|store\s+this|note\s+that|remind\s+me\s*(to|that)?)\s*',
      caseSensitive: false,
    );
    
    // Replace the matched prefix with empty string to get the content
    final content = message.replaceFirst(memoryCommandRegex, '').trim();
    
    // If for some reason the replace didn't work (shouldn't happen if detectIntent passed), return original
    if (content.isEmpty) return message;
    
    // If the content starts with "that" or "to" redundantly after stripping (edge cases), strip it again if it makes sense
    // e.g. "remember that my key is 123" -> regex might strip "remember" leaving "that my key..." if not careful.
    // The regex above includes (that)? capture groups to handle this, so it should be fine.
    
    return content;
  }
  String extractAppName(String message) {
    final clean = message.trim();
    final commandRegex = RegExp(
      r'^(open|launch|start|run|go\s+to|switch\s+to|fire\s+up|pull\s+up|bring\s+up|load|close|kill|stop|exit|quit|shut\s+down)\s+',
      caseSensitive: false,
    );

    final match = commandRegex.firstMatch(clean);
    if (match != null) {
      return clean.substring(match.end).trim();
    }
    return clean;
  }

  String extractSettingsType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains("wifi") || lower.contains("wi-fi")) return "wifi";
    if (lower.contains("bluetooth")) return "bluetooth";
    if (lower.contains("display") || lower.contains("brightness")) return "display";
    if (lower.contains("sound") || lower.contains("volume")) return "sound";
    return "general";
  }

  String extractContactName(String message) {
    String clean = message.trim();

    // "give X a call/ring/buzz" pattern
    final giveCallRegex = RegExp(
      r'give\s+(.+?)\s+a\s+(call|ring|buzz)',
      caseSensitive: false,
    );
    final giveMatch = giveCallRegex.firstMatch(clean);
    if (giveMatch != null) {
      return giveMatch.group(1)?.trim() ?? clean;
    }

    // Standard prefixes: call, dial, phone, ring up, ring, buzz, contact
    final commandRegex = RegExp(
      r'^(call|dial|phone|ring\s+up|ring|buzz|contact)\s+',
      caseSensitive: false,
    );

    final match = commandRegex.firstMatch(clean);
    if (match != null) {
      return clean.substring(match.end).trim();
    }
    return clean;
  }

  Map<String, String> extractSMSDetails(String message) {
    String clean = message.trim();
    final lower = clean.toLowerCase();
    
    String name = "";
    String body = "";

    // Pattern 1: "Send [Message] to [Name]"
    // e.g., "Send hello there to John"
    if (lower.contains(" to ")) {
      final toIndex = lower.indexOf(" to ");
      // Check if "send" or "text" or "message" is at start
      final prefixRegex = RegExp(r'^(send|write|shoot|text|message|msg)\s+', caseSensitive: false);
      final match = prefixRegex.firstMatch(clean);
      
      if (match != null) {
        // Everything between command and "to" is the message? 
        // Or "Send message to [Name] saying [Body]"?
        // Let's assume "Send [Body] to [Name]" first.
        
        final afterTo = clean.substring(toIndex + 4).trim();
        final potentialBody = clean.substring(match.end, toIndex).trim();
        
        // If "potentialBody" is just "message" or "sms", then the body is likely after name?
        // e.g., "Send message to John saying Hello"
        if (potentialBody.toLowerCase().replaceAll(RegExp(r'^(a\s+)?(sms|text|message|msg)$'), '').trim().isEmpty) {
             // It was just "Send message to..."
             // Check for "saying" or "as" separator
             final separatorRegex = RegExp(r'\s+(saying|as)\s+', caseSensitive: false);
             final sepMatch = separatorRegex.firstMatch(clean.substring(toIndex + 4));
             if (sepMatch != null) {
                final sepStart = toIndex + 4 + sepMatch.start;
                final sepEnd = toIndex + 4 + sepMatch.end;
                name = clean.substring(toIndex + 4, sepStart).trim();
                body = clean.substring(sepEnd).trim();
                return {'name': name, 'message': body};
             }
             // "Send message to John: Hello"
             if (afterTo.contains(":")) {
                final colonIndex = afterTo.indexOf(":");
                name = afterTo.substring(0, colonIndex).trim();
                body = afterTo.substring(colonIndex + 1).trim();
                return {'name': name, 'message': body};
             }
             // Fallback: "Send message to John" (Body empty? or prompt user?)
             name = afterTo;
             return {'name': name, 'message': ''};
        } else {
           // Pattern: "Send Hello World to John"
           // This is risky if the name is multi-word or body has "to". 
           // But let's assume valid.
           body = potentialBody;
           name = afterTo;
           return {'name': name, 'message': body};
        }
      }
    }

    // Pattern 1b: "drop a text/line/message to [Name]" or "shoot a message to [Name]"
    final dropRegex = RegExp(
      r'(drop\s+a\s+(text|line|message)|shoot\s+a\s+(message|text))\s+to\s+(.+)',
      caseSensitive: false,
    );
    final dropMatch = dropRegex.firstMatch(clean);
    if (dropMatch != null) {
      final afterTo = dropMatch.group(4)?.trim() ?? '';
      final sepRegex = RegExp(r'\s+(saying|as)\s+', caseSensitive: false);
      final sepMatch = sepRegex.firstMatch(afterTo);
      if (sepMatch != null) {
        name = afterTo.substring(0, sepMatch.start).trim();
        body = afterTo.substring(sepMatch.end).trim();
      } else {
        name = afterTo;
      }
      return {'name': name, 'message': body};
    }

    // Pattern 2: "Text [Name] [Message]" (Standard)
    // "Text John I'll be late" or "Text 90196 71670 hello"
    final commandRegex = RegExp(r'^(send|write|shoot|text|message|msg)\s+(a\s+)?(sms|text|message|msg)?\s*(to\s+)?', caseSensitive: false);
    final match = commandRegex.firstMatch(clean);
    
    if (match != null) {
      final remaining = clean.substring(match.end).trim();
      
      // New Token-Based Logic to handle "90196 71670"
      final tokens = remaining.split(RegExp(r'\s+'));
      
      // Helper to check for letters
      bool hasLetters(String s) => RegExp(r'[a-zA-Z]').hasMatch(s);

      if (tokens.isNotEmpty) {
        // Case A: Starts with a Name (Letters present)
        if (hasLetters(tokens.first)) {
           name = tokens.first;
           // The rest is body
           int nameIndex = remaining.indexOf(name);
           if (nameIndex != -1) {
              body = remaining.substring(nameIndex + name.length).trim();
           }
           // Strip "as" or "saying" separator from body start
           // e.g. "text appu as hai" → body was "as hai", now "hai"
           final bodySepRegex = RegExp(r'^(as|saying)\s+', caseSensitive: false);
           body = body.replaceFirst(bodySepRegex, '');
        } 
        // Case B: Starts with Number (No letters)
        else {
           List<String> phoneParts = [];
           int processedCount = 0;
           int digitCount = 0;
           bool startsWithPlus = tokens.first.startsWith('+');
           // If starts with +, likely country code + number -> allow ~14 digits (e.g. +91 98765 43210 is 12 digits)
           // If no +, assume standard local number -> 10 digits (India/US)
           int maxDigits = startsWithPlus ? 14 : 10;
           
           for (var token in tokens) {
              if (hasLetters(token)) {
                 // Found the start of the message body (letters)
                 break;
              }
              
              // Count digits in this token
              int tokenDigits = token.replaceAll(RegExp(r'[^0-9]'), '').length;
              
              // If we already have enough digits from previous tokens, this new numeric token is likely the body
              // e.g. "98765 43210 1234" -> after 43210, count is 10. Next extraction should break.
              if (digitCount >= maxDigits) {
                 break;
              }
              
              phoneParts.add(token);
              processedCount++;
              digitCount += tokenDigits;
           }
           
           if (phoneParts.isNotEmpty) {
              name = phoneParts.join(" "); 
              
              // Extract body strictly after the phone parts
              int currentPos = 0;
              for(int i=0; i<processedCount; i++) {
                 int tokenPos = remaining.indexOf(tokens[i], currentPos);
                 if (tokenPos != -1) {
                    currentPos = tokenPos + tokens[i].length;
                 }
              }
              if (currentPos < remaining.length) {
                 body = remaining.substring(currentPos).trim();
              }
           }
        }
      }
      
      return {'name': name, 'message': body};
    }

    return {'name': '', 'message': ''};
  }
}
