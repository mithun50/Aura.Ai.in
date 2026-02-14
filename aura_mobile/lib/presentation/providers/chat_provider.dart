import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/core/services/voice_service.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

// Voice Service
final voiceServiceProvider = Provider((ref) => VoiceService());

// Chat State
class ChatState {
  final List<Map<String, String>> messages;
  final bool isListening;
  final bool isThinking;

  ChatState({this.messages = const [], this.isThinking = false, this.isListening = false});

  ChatState copyWith({List<Map<String, String>>? messages, bool? isThinking, bool? isListening}) {
    return ChatState(
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
      isListening: isListening ?? this.isListening,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  bool _isProcessing = false; // Mutex for concurrent call prevention

  ChatNotifier(this._ref) : super(ChatState()) {
    _initializeAI();
  }

  Future<void> _initializeAI() async {
    try {
      state = state.copyWith(isThinking: true);
      final llmService = _ref.read(llmServiceProvider);
      await llmService.initialize();
      // Only load model if we know it exists, otherwise Onboarding should have handled it.
      // For now, we assume it's there or will be loaded by UI.
      // await llmService.loadModel('assets/models/smollm2-360m.gguf'); 
    } catch (e) {
      print('Error initializing AI: $e');
    } finally {
      state = state.copyWith(isThinking: false);
    }
  }

  Future<void> sendMessage(String text) async {
    // Prevent concurrent LLM calls
    if (_isProcessing) {
      print('Already processing a message, ignoring new request');
      return;
    }
    _isProcessing = true;

    // 1. Add User Message
    state = state.copyWith(
      messages: [...state.messages, {'role': 'user', 'content': text}],
      isThinking: true,
    );
    
    // Placeholder for Assistant Response
    state = state.copyWith(
      messages: [...state.messages, {'role': 'assistant', 'content': ''}],
    );

    try {
      final intentService = _ref.read(intentDetectionServiceProvider);
      final memoryService = _ref.read(memoryServiceProvider);
      final documentService = _ref.read(documentServiceProvider);
      final contextBuilder = _ref.read(contextBuilderServiceProvider);
      final llmService = _ref.read(llmServiceProvider);

      // 2. Detect Intent
      // In a real app, we'd check if specific documents are active/selected.
      // For now, we assume global document context access if any exist.
      final intent = intentService.detectIntent(text, hasDocuments: true);

      if (intent == IntentType.storeMemory) {
        // --- MEMORY STORE FLOW ---
        final contentToSave = intentService.extractMemoryContent(text);
        await memoryService.saveMemory(contentToSave);
        
        // Update UI directly without LLM
        _updateLastMessage("I've saved that to your permanent memory.");
      
      } else {
        // --- CHAT / RAG FLOW ---
        
        // Build Prompt (Includes RAG & Memory retrieval internally)
        // Limit to last 3 messages for performance
        final allHistory = state.messages
            .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
            .map((m) => "${m['role'] == 'user' ? 'User' : 'Assistant'}: ${m['content']}")
            .toList();
        final history = allHistory.length > 3 
            ? allHistory.sublist(allHistory.length - 3) 
            : allHistory;

        final fullPrompt = await contextBuilder.buildPrompt(
          userMessage: text,
          chatHistory: history,
          includeMemories: intent == IntentType.retrieveMemory || intent == IntentType.normalChat,
          includeDocuments: intent == IntentType.queryDocument || intent == IntentType.normalChat,
        );

        // Stream Response
        final stream = llmService.chat(text, systemPrompt: fullPrompt);
        
        String fullResponse = '';
        await for (final chunk in stream) {
          fullResponse += chunk;
          _updateLastMessage(fullResponse);
        }
        
        // Save to history automatically via state update
      }

    } catch (e) {
      print('Error in sendMessage: $e');
      _updateLastMessage('Error processing request: $e');
    } finally {
      state = state.copyWith(isThinking: false);
      _isProcessing = false; // Release mutex
    }
  }

  void _updateLastMessage(String newContent) {
    final newMessages = List<Map<String, String>>.from(state.messages);
    if (newMessages.isNotEmpty && newMessages.last['role'] == 'assistant') {
      newMessages.last = {'role': 'assistant', 'content': newContent};
      state = state.copyWith(messages: newMessages);
    }
  }

  Future<void> stopListening() async {
    final voiceService = _ref.read(voiceServiceProvider);
    await voiceService.stopListening();
    state = state.copyWith(isListening: false);
  }

  Future<void> startListening() async {
    final voiceService = _ref.read(voiceServiceProvider);
    await voiceService.initialize();
    state = state.copyWith(isListening: true);
    
    await voiceService.startListening(onResult: (text) {
      if (text.isNotEmpty) {
        state = state.copyWith(isListening: false);
        sendMessage(text);
        stopListening();
      }
    });
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});
