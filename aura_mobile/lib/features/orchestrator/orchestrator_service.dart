import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final orchestratorServiceProvider = Provider((ref) => OrchestratorService(
  ref.read(intentDetectionServiceProvider),
  ref.read(memoryServiceProvider),
  ref.read(documentServiceProvider),
  ref.read(contextBuilderServiceProvider),
  ref.read(llmServiceProvider),
));

class OrchestratorService {
  final IntentDetectionService _intentService;
  final MemoryService _memoryService;
  final DocumentService _documentService;
  final ContextBuilderService _contextBuilder;
  final LLMService _llmService;

  // Keep track of internal history if needed, or pass it in. 
  // For now, we assume the UI provider manages the history list and passes it here,
  // OR we manage it here. The prompt requires "Recent Chat History".
  // Let's accept it as an argument to keep this service stateless-ish.

  OrchestratorService(
    this._intentService,
    this._memoryService,
    this._documentService,
    this._contextBuilder,
    this._llmService,
  );

  Stream<String> processMessage({
    required String message,
    required List<String> chatHistory,
    bool hasDocuments = false, // passed from UI state
  }) async* {
    // 1. Intent Detection
    final intent = _intentService.detectIntent(message, hasDocuments: hasDocuments);

    // 2. Routing
    switch (intent) {
      case IntentType.storeMemory:
        await _handleStoreMemory(message);
        yield "Memory saved.";
        break;

      case IntentType.retrieveMemory:
        yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: false);
        break;

      case IntentType.queryDocument:
        yield* _handleLLMFlow(message, chatHistory, includeMemories: false, includeDocuments: true);
        break;

      case IntentType.normalChat:
      default:
        yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: false);
        break;
    }
  }

  Future<void> _handleStoreMemory(String message) async {
    final content = _intentService.extractMemoryContent(message);
    await _memoryService.saveMemory(content);
  }

  Stream<String> _handleLLMFlow(
    String message,
    List<String> history, {
    required bool includeMemories,
    required bool includeDocuments,
  }) async* {
    // 3. Context Building
    final prompt = await _contextBuilder.buildPrompt(
      userMessage: message,
      chatHistory: history,
      includeMemories: includeMemories,
      includeDocuments: includeDocuments,
    );

    // 4. LLM Execution
    // We pass the full prompt. System prompt is embedded in it.
    yield* _llmService.chat(prompt);
  }
}
