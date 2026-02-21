import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/core/services/voice_service.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

import 'package:uuid/uuid.dart';
import 'package:aura_mobile/domain/repositories/chat_history_repository.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';
import 'package:aura_mobile/presentation/providers/chat_history_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';

// Voice Service
final voiceServiceProvider = Provider((ref) => VoiceService());

// Chat State
class ChatState {
  final String? sessionId;
  final List<Map<String, String>> messages;
  final bool isListening;
  final bool isThinking;
  final String partialVoiceText;
  final bool isModelLoading;

  ChatState({
    this.sessionId,
    this.messages = const [],
    this.isThinking = false,
    this.isListening = false,
    this.partialVoiceText = '',
    this.isModelLoading = false,
  });

  ChatState copyWith({
    String? sessionId,
    List<Map<String, String>>? messages,
    bool? isThinking,
    bool? isListening,
    String? partialVoiceText,
    bool? isModelLoading,
  }) {
    return ChatState(
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
      isListening: isListening ?? this.isListening,
      partialVoiceText: partialVoiceText ?? this.partialVoiceText,
      isModelLoading: isModelLoading ?? this.isModelLoading,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  bool _isProcessing = false; // Mutex for concurrent call prevention
  final _uuid = const Uuid();

  ChatNotifier(this._ref) : super(ChatState()) {
    _initializeAI();
    _startNewSession();
  }

  void _startNewSession() {
    state = state.copyWith(
      sessionId: _uuid.v4(),
      messages: [],
      isThinking: false,
    );
  }

  Future<void> _initializeAI() async {
    try {
      state = state.copyWith(isModelLoading: true);
      final llmService = _ref.read(llmServiceProvider);
      await llmService.initialize();
      
      // Auto-load last selected model
      final prefs = await SharedPreferences.getInstance();
      final modelPath = prefs.getString('selected_model_path');
      
      if (modelPath != null && modelPath.isNotEmpty) {
        print('ChatNotifier: Auto-loading model from $modelPath');
        await llmService.loadModel(modelPath);
      } else {
        print('ChatNotifier: No model selected. User must select a model.');
      }
    } catch (e) {
      print('Error initializing AI: $e');
    } finally {
      state = state.copyWith(isModelLoading: false);
    }
  }

  Future<void> loadSession(ChatSession session) async {
    // Load full session logic
    // Repository might return metadata only, check if messages are empty
    var fullSession = session;
    if (session.messages.isEmpty) {
        final repo = _ref.read(chatHistoryRepositoryProvider);
        final loaded = await repo.getSession(session.id);
        if (loaded != null) fullSession = loaded;
    }

    state = state.copyWith(
      sessionId: fullSession.id,
      messages: fullSession.messages,
    );
  }

  Future<void> _saveChat() async {
    if (state.messages.isEmpty) return;
    
    try {
      final repo = _ref.read(chatHistoryRepositoryProvider);
      
      // Generate a title based on the first user message if possible
      String title = "New Chat";
      final firstUserMsg = state.messages.firstWhere(
        (m) => m['role'] == 'user',
        orElse: () => {},
      );
      if (firstUserMsg.isNotEmpty && firstUserMsg['content'] != null) {
        final content = firstUserMsg['content']!;
        title = content.length > 30 ? "${content.substring(0, 30)}..." : content;
      }

      final session = ChatSession(
        id: state.sessionId ?? _uuid.v4(),
        title: title,
        lastModified: DateTime.now(),
        messages: state.messages,
      );

      // Update state ID if it was null (shouldn't be, but safe)
      if (state.sessionId == null) {
        state = state.copyWith(sessionId: session.id);
      }

      await repo.saveSession(session);
      // Invalidate history provider to refresh list
      _ref.invalidate(chatHistoryProvider);
    } catch (e) {
      print("Error saving chat: $e");
    }
  }

  Future<void> sendMessage(String text) async {
    // 0. Safety Checks
    final modelState = _ref.read(modelSelectorProvider);
    if (modelState.activeModelId == null || state.isModelLoading) {
      print('Model not ready, ignoring message');
      return;
    }

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
    _saveChat(); // Save after user message
    
    // Placeholder for Assistant Response
    state = state.copyWith(
      messages: [...state.messages, {'role': 'assistant', 'content': ''}],
    );

    try {
      final orchestrator = _ref.read(orchestratorServiceProvider);
      
      // Get chat history for context
      final allHistory = state.messages
            .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
            .map((m) => "${m['role'] == 'user' ? 'User' : 'Assistant'}: ${m['content']}")
            .toList();
            
      // Limit history to last 3 messages to match context_builder_service pruning
      final history = allHistory.length > 3
          ? allHistory.sublist(allHistory.length - 3)
          : allHistory;

      // Check if documents are available
      final documentService = _ref.read(documentServiceProvider);
      final hasDocuments = await documentService.hasDocuments();

      // Delegate to Orchestrator
      print("ChatNotifier: Delegating message to Orchestrator");
      final stream = orchestrator.processMessage(
        message: text,
        chatHistory: history,
        hasDocuments: hasDocuments,
      );

      String fullResponse = '';
      await for (final chunk in stream) {
        fullResponse += chunk;
        _updateLastMessage(fullResponse);
      }
      print('ChatNotifier: Stream completed. Full response length: ${fullResponse.length}');
      _saveChat(); // Save after full response

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
    state = state.copyWith(isListening: true, partialVoiceText: '');
    
    await voiceService.startListening(onResult: (text, isFinal) {
      if (text.isNotEmpty) {
        if (isFinal) {
          state = state.copyWith(isListening: false, partialVoiceText: '');
          sendMessage(text);
          stopListening();
        } else {
          state = state.copyWith(partialVoiceText: text);
        }
      }
    });
  }

  void clearChat() {
     _startNewSession();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});
