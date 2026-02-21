import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/services/web_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';

final assistantAiBridgeProvider = Provider((ref) {
  return AssistantAiBridge(ref);
});

/// Bridges the native voice assistant to the Flutter AI pipeline.
/// Unlike the chat UI orchestrator, this produces clean spoken-text output
/// (no markdown, no emojis, no source URLs) suitable for TTS.
class AssistantAiBridge {
  static const _channel = MethodChannel('com.aura.ai/assistant_ai');
  final Ref _ref;

  AssistantAiBridge(this._ref) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'processAIQuery') {
      final query = call.arguments as String? ?? '';
      if (query.isEmpty) return;
      await _processQuery(query);
    }
  }

  Future<void> _processQuery(String query) async {
    try {
      final llmService = _ref.read(llmServiceProvider);

      // Auto-load model if not loaded yet
      if (!llmService.isModelLoaded) {
        debugPrint('AI_BRIDGE: Model not loaded, attempting auto-load...');
        final prefs = await SharedPreferences.getInstance();
        final modelPath = prefs.getString('selected_model_path');
        if (modelPath != null && modelPath.isNotEmpty) {
          await llmService.initialize();
          await llmService.loadModel(modelPath);
          debugPrint('AI_BRIDGE: Model auto-loaded from $modelPath');
        } else {
          debugPrint('AI_BRIDGE: No model path found, sending fallback');
          await _sendChunk(
              'The AI model is not loaded yet. Please open the app and download a model first.');
          await _sendComplete();
          return;
        }
      }

      // Determine if this is a web search or plain AI chat
      final intentService = _ref.read(intentDetectionServiceProvider);
      final intent = await intentService.detectIntent(query);

      if (intent == IntentType.webSearch) {
        await _handleVoiceWebSearch(query, llmService, intentService);
      } else {
        // Plain AI chat — stream LLM response directly
        await _handleVoiceChat(query, llmService);
      }
    } catch (e) {
      debugPrint('AI_BRIDGE: Error processing query: $e');
      await _sendChunk('Sorry, I encountered an error processing your request.');
      await _sendComplete();
    }
  }

  /// Handle web search for voice — search the web, synthesize answer via LLM,
  /// but output clean spoken text (no emojis, no source URLs).
  Future<void> _handleVoiceWebSearch(
      String query, LLMService llmService, IntentDetectionService intentService) async {
    final cleanQuery = intentService.extractSearchQuery(query);
    debugPrint('AI_BRIDGE: Voice web search for: $cleanQuery');

    await _sendChunk('Searching for $cleanQuery.');

    try {
      final webService = _ref.read(webServiceProvider);
      final results = await webService.search(cleanQuery);

      if (results.isEmpty) {
        await _sendChunk("I couldn't find any recent information for $cleanQuery.");
        await _sendComplete();
        return;
      }

      // Build context and stream LLM synthesis — voice-friendly, no sources
      final contextBuilder = _ref.read(contextBuilderServiceProvider);
      final prompt = contextBuilder.injectWeb(results, cleanQuery);

      await _streamLlmForVoice(llmService, prompt,
          systemPrompt:
              'You have web access. Use the Search Results to answer the user directly. '
              'Keep your answer concise and conversational — this will be read aloud. '
              'Do not include URLs, links, or source references. Do not use markdown formatting.');
    } catch (e) {
      debugPrint('AI_BRIDGE: Web search failed: $e');
      // Fallback to plain LLM chat
      await _handleVoiceChat(query, llmService);
      return;
    }

    await _sendComplete();
  }

  /// Handle plain AI chat for voice — stream LLM response with voice-friendly cleanup.
  Future<void> _handleVoiceChat(String query, LLMService llmService) async {
    await _streamLlmForVoice(llmService, query,
        systemPrompt:
            'You are a helpful voice assistant. Keep answers concise and conversational — '
            'this will be read aloud. Do not use markdown, URLs, or formatting.');
    await _sendComplete();
  }

  /// Stream LLM tokens, group into sentences, clean for voice, and send as chunks.
  Future<void> _streamLlmForVoice(LLMService llmService, String prompt,
      {String? systemPrompt}) async {
    final stream = llmService.chat(prompt, systemPrompt: systemPrompt);
    String pendingText = '';

    await for (final token in stream) {
      pendingText += token;

      final extracted = _extractCompleteSentences(pendingText);
      if (extracted.sentences.isNotEmpty) {
        final cleaned = _cleanForVoice(extracted.sentences);
        if (cleaned.trim().isNotEmpty) {
          await _sendChunk(cleaned);
        }
        pendingText = extracted.remainder;
      }
    }

    // Send remaining text
    if (pendingText.trim().isNotEmpty) {
      final cleaned = _cleanForVoice(pendingText.trim());
      if (cleaned.trim().isNotEmpty) {
        await _sendChunk(cleaned);
      }
    }
  }

  Future<void> _sendChunk(String text) async {
    await _channel.invokeMethod('sendAIChunk', text);
  }

  Future<void> _sendComplete() async {
    await _channel.invokeMethod('sendAIComplete', null);
  }

  /// Extracts complete sentences from accumulated text.
  _SentenceExtraction _extractCompleteSentences(String text) {
    int lastBoundary = -1;
    for (int i = 0; i < text.length - 1; i++) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?') {
        final next = text[i + 1];
        if (next == ' ' || next == '\n' || next == '\r') {
          lastBoundary = i + 1;
        }
      } else if (c == '\n') {
        lastBoundary = i + 1;
      }
    }

    if (lastBoundary > 0) {
      return _SentenceExtraction(
        sentences: text.substring(0, lastBoundary).trim(),
        remainder: text.substring(lastBoundary),
      );
    }

    return _SentenceExtraction(sentences: '', remainder: text);
  }

  /// Clean text for TTS — strip markdown, emojis, URLs, source blocks.
  String _cleanForVoice(String text) {
    String cleaned = text;

    // Strip markdown
    cleaned = cleaned
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'__(.+?)__'), r'$1')
        .replaceAll(RegExp(r'_(.+?)_'), r'$1')
        .replaceAll(RegExp(r'~~(.+?)~~'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // Strip markdown links — keep text, drop URL
    cleaned = cleaned.replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1');
    // Strip markdown images
    cleaned = cleaned.replaceAll(RegExp(r'!\[.*?\]\(.+?\)'), '');

    // Strip raw URLs
    cleaned = cleaned.replaceAll(
        RegExp(r'https?://[^\s\)]+', caseSensitive: false), '');

    // Strip "Top Sources" / "Sources" blocks and everything after
    cleaned = cleaned.replaceAll(
        RegExp(r'(🌐\s*)?Top Sources:.*', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\nSources:.*', caseSensitive: false, dotAll: true), '');

    // Strip emojis (common Unicode ranges)
    cleaned = cleaned.replaceAll(
        RegExp(
            r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|'
            r'[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|'
            r'[\u{FE00}-\u{FE0F}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|'
            r'[\u{1FA70}-\u{1FAFF}]|[\u{200D}]|[\u{20E3}]|[\u{E0020}-\u{E007F}]|'
            r'[▶️⚙️📸📞📨💡🌑🚀🔍🌐❌⚠️]',
            unicode: true),
        '');

    // Collapse excess whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r'  +'), ' ');

    return cleaned.trim();
  }
}

class _SentenceExtraction {
  final String sentences;
  final String remainder;
  _SentenceExtraction({required this.sentences, required this.remainder});
}
