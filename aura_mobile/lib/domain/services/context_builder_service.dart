
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final contextBuilderServiceProvider = Provider((ref) => ContextBuilderService(
  ref.read(memoryServiceProvider),
  ref.read(documentServiceProvider),
));

class ContextBuilderService {
  final MemoryService _memoryService;
  final DocumentService _documentService;

  ContextBuilderService(this._memoryService, this._documentService);

  Future<String> buildPrompt({
    required String userMessage,
    required List<String> chatHistory,
    bool includeMemories = true,
    bool includeDocuments = true,
  }) async {
    final buffer = StringBuffer();

    // 1. System Instruction
    buffer.writeln("You are AURA, a privacy-first offline AI assistant. Answer concisely and helpfully.");
    
    // 2. Memory Context
    if (includeMemories) {
      final memories = await _memoryService.retrieveRelevantMemories(userMessage);
      if (memories.isNotEmpty) {
        final topMemories = memories.take(3).toList();
        buffer.writeln("\nRelevant Memories:");
        for (var mem in topMemories) {
          buffer.writeln("- $mem");
        }
      }
    }

    // 3. Document Context
    if (includeDocuments) {
      final docContext = await _documentService.retrieveRelevantContext(userMessage);
      if (docContext.isNotEmpty) {
        final topDocs = docContext.take(2).toList(); // Reduce to 2 for speed/context window
        buffer.writeln("\nDocument Context:");
        for (var chunk in topDocs) {
          buffer.writeln(chunk);
        }
      }
    }

    // 4. Chat History
    // Note: In ChatML, history should ideally be passed as separate messages, but for now we'll embed it in system 
    // or just rely on the fact that we are only passing the 'systemPrompt' to RunAnywhere which puts it in <|im_start|>system.
    // Putting chat history in system prompt is suboptimal but works for simple context state.
    if (chatHistory.isNotEmpty) {
      final limitedHistory = chatHistory.length > 5 
          ? chatHistory.sublist(chatHistory.length - 5) 
          : chatHistory;
      
      buffer.writeln("\nPrevious Conversation:");
      for (var msg in limitedHistory) {
        buffer.writeln(msg);
      }
    }
    
    // We do NOT add the user message here. RunAnywhere adds it as <|im_start|>user
    
    return buffer.toString();
  }
}
