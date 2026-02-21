import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';

final assistantAiBridgeProvider = Provider((ref) {
  return AssistantAiBridge(ref);
});

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
          await _channel.invokeMethod('sendAIChunk',
            'The AI model is not loaded yet. Please open the app and download a model first.');
          await _channel.invokeMethod('sendAIComplete', null);
          return;
        }
      }

      final orchestrator = _ref.read(orchestratorServiceProvider);
      final stream = orchestrator.processMessage(
        message: query,
        chatHistory: [],
        hasDocuments: false,
        isVoiceQuery: true,
      );

      String pendingText = '';

      await for (final chunk in stream) {
        pendingText += chunk;

        // Extract complete sentences and send them as chunks
        final extracted = _extractCompleteSentences(pendingText);
        if (extracted.sentences.isNotEmpty) {
          final cleaned = _stripMarkdown(extracted.sentences);
          if (cleaned.trim().isNotEmpty) {
            await _channel.invokeMethod('sendAIChunk', cleaned);
          }
          pendingText = extracted.remainder;
        }
      }

      // Send any remaining text
      if (pendingText.trim().isNotEmpty) {
        final cleaned = _stripMarkdown(pendingText.trim());
        if (cleaned.trim().isNotEmpty) {
          await _channel.invokeMethod('sendAIChunk', cleaned);
        }
      }

      await _channel.invokeMethod('sendAIComplete', null);
    } catch (e) {
      debugPrint('AI_BRIDGE: Error processing query: $e');
      await _channel.invokeMethod('sendAIChunk',
        'Sorry, I encountered an error processing your request.');
      await _channel.invokeMethod('sendAIComplete', null);
    }
  }

  /// Extracts complete sentences from accumulated text.
  /// Returns the sentences and the leftover remainder.
  _SentenceExtraction _extractCompleteSentences(String text) {
    // Find the last sentence boundary (. ! ? or newline followed by space/newline/end)
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

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1') // bold
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1') // italic
        .replaceAll(RegExp(r'__(.+?)__'), r'$1') // bold alt
        .replaceAll(RegExp(r'_(.+?)_'), r'$1') // italic alt
        .replaceAll(RegExp(r'~~(.+?)~~'), r'$1') // strikethrough
        .replaceAll(RegExp(r'`(.+?)`'), r'$1') // inline code
        .replaceAll(RegExp(r'```[\s\S]*?```'), '') // code blocks
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '') // headers
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '') // list items
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '') // numbered lists
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1') // links
        .replaceAll(RegExp(r'!\[.*?\]\(.+?\)'), '') // images
        .replaceAll(RegExp(r'\n{3,}'), '\n\n') // excess newlines
        .trim();
  }
}

class _SentenceExtraction {
  final String sentences;
  final String remainder;
  _SentenceExtraction({required this.sentences, required this.remainder});
}
