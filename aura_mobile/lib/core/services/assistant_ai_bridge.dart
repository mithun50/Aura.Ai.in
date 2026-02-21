import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      // Check if model is loaded before attempting AI processing
      final llmService = _ref.read(llmServiceProvider);
      if (!llmService.isModelLoaded) {
        debugPrint('AI_BRIDGE: Model not loaded, sending fallback response');
        await _channel.invokeMethod(
          'sendAIResponse',
          'The AI model is not loaded yet. Please open the app and download a model first.',
        );
        return;
      }

      final orchestrator = _ref.read(orchestratorServiceProvider);
      final stream = orchestrator.processMessage(
        message: query,
        chatHistory: [],
        hasDocuments: false,
        isVoiceQuery: true,
      );

      final buffer = StringBuffer();
      await for (final chunk in stream) {
        buffer.write(chunk);
      }

      String response = buffer.toString().trim();
      if (response.isEmpty) {
        response = "I couldn't generate a response right now.";
      }

      // Strip markdown for TTS readability
      response = _stripMarkdown(response);

      await _channel.invokeMethod('sendAIResponse', response);
    } catch (e) {
      debugPrint('AI_BRIDGE: Error processing query: $e');
      await _channel.invokeMethod(
        'sendAIResponse',
        'Sorry, I encountered an error processing your request.',
      );
    }
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
