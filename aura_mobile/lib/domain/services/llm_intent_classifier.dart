import 'package:flutter/foundation.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';

/// Carries the classified intent type and extracted parameters.
class ClassifiedIntent {
  final IntentType type;
  final Map<String, String> params;

  const ClassifiedIntent(this.type, [this.params = const {}]);

  @override
  String toString() => 'ClassifiedIntent($type, $params)';
}

/// LLM-based fallback intent classifier.
/// Used when rule-based detection returns `normalChat` to catch creative phrasings.
class LLMIntentClassifier {
  final LLMService _llmService;

  LLMIntentClassifier(this._llmService);

  static const _systemPrompt =
      'Classify commands. Reply ONLY with: CATEGORY|params\n'
      'Categories: OPEN_APP|name, DIAL_CONTACT|name, SEND_SMS|name|message, '
      'TORCH|on/off, OPEN_CAMERA, OPEN_SETTINGS|type, WEB_SEARCH|query, '
      'PLAY_YOUTUBE|query, NORMAL_CHAT\n'
      'Examples:\n'
      '"ring up John" -> DIAL_CONTACT|John\n'
      '"fire up Chrome" -> OPEN_APP|Chrome\n'
      '"snap a pic" -> OPEN_CAMERA\n'
      '"drop a text to Mom saying hi" -> SEND_SMS|Mom|hi\n'
      '"turn the light on" -> TORCH|on\n'
      '"take me to wifi settings" -> OPEN_SETTINGS|wifi\n'
      '"open youtube and play toxic teaser" -> PLAY_YOUTUBE|toxic teaser\n'
      '"play despacito on youtube" -> PLAY_YOUTUBE|despacito\n'
      '"what is quantum physics" -> NORMAL_CHAT';

  /// Classify a user message using the on-device LLM.
  /// Returns `null` if the model is not loaded or classification fails.
  Future<ClassifiedIntent?> classify(String message) async {
    if (!_llmService.isModelLoaded) {
      debugPrint('LLM_CLASSIFIER: Model not loaded, skipping');
      return null;
    }

    try {
      final buffer = StringBuffer();
      await for (final token in _llmService.chat(
        message,
        systemPrompt: _systemPrompt,
        maxTokens: 30,
      )) {
        buffer.write(token);
      }

      final raw = buffer.toString().trim();
      debugPrint('LLM_CLASSIFIER: Raw output: "$raw"');
      return _parse(raw);
    } catch (e) {
      debugPrint('LLM_CLASSIFIER: Error during classification: $e');
      return null;
    }
  }

  /// Parse the LLM output into a ClassifiedIntent.
  ClassifiedIntent? _parse(String raw) {
    if (raw.isEmpty) return null;

    // Take only the first line
    var line = raw.split('\n').first.trim();

    // Strip leading "-> " if present
    if (line.startsWith('->')) {
      line = line.substring(2).trim();
    }
    // Strip surrounding quotes
    if ((line.startsWith('"') && line.endsWith('"')) ||
        (line.startsWith("'") && line.endsWith("'"))) {
      line = line.substring(1, line.length - 1).trim();
    }

    final parts = line.split('|').map((p) => p.trim()).toList();
    if (parts.isEmpty) return null;

    final category = parts[0].toUpperCase().replaceAll(' ', '_');

    switch (category) {
      case 'OPEN_APP':
        final name = parts.length > 1 ? parts[1] : '';
        if (name.isEmpty) return null;
        return ClassifiedIntent(IntentType.openApp, {'appName': name});

      case 'DIAL_CONTACT':
        final name = parts.length > 1 ? parts[1] : '';
        if (name.isEmpty) return null;
        return ClassifiedIntent(IntentType.dialContact, {'contactName': name});

      case 'SEND_SMS':
        final name = parts.length > 1 ? parts[1] : '';
        final msg = parts.length > 2 ? parts[2] : '';
        if (name.isEmpty) return null;
        return ClassifiedIntent(IntentType.sendSMS, {'name': name, 'message': msg});

      case 'TORCH':
        final state = parts.length > 1 ? parts[1].toLowerCase() : 'on';
        return ClassifiedIntent(IntentType.torchControl, {'state': state});

      case 'OPEN_CAMERA':
        return ClassifiedIntent(IntentType.openCamera);

      case 'OPEN_SETTINGS':
        final type = parts.length > 1 ? parts[1].toLowerCase() : 'general';
        return ClassifiedIntent(IntentType.openSettings, {'type': type});

      case 'WEB_SEARCH':
        final query = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (query.isEmpty) return null;
        return ClassifiedIntent(IntentType.webSearch, {'query': query});

      case 'PLAY_YOUTUBE':
        final query = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (query.isEmpty) return null;
        return ClassifiedIntent(IntentType.playYoutube, {'query': query});

      case 'NORMAL_CHAT':
        return ClassifiedIntent(IntentType.normalChat);

      default:
        debugPrint('LLM_CLASSIFIER: Unknown category "$category"');
        return null;
    }
  }
}
