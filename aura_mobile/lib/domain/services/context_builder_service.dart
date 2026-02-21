
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
        buffer.writeln("\nRelevant Memories from your past conversations:");
        for (var mem in topMemories) {
          buffer.writeln("- $mem");
        }
      }
    }

    // 3. Document Context
    if (includeDocuments) {
      final docContext = await _documentService.retrieveRelevantContext(userMessage);
      if (docContext.isNotEmpty) {
        final topDocs = docContext.take(2).toList();
        buffer.writeln("\nRelevant Document Context:");
        for (var chunk in topDocs) {
          buffer.writeln(chunk);
        }
      }
    }

    // 4. Chat History (LOWER PRIORITY for tool use cases)
    if (chatHistory.isNotEmpty) {
      buffer.writeln("\n--- PREVIOUS CONVERSATION CONTEXT (Do not repeat previous answers) ---");
      final limitedHistory = chatHistory.length > 3 
          ? chatHistory.sublist(chatHistory.length - 3) 
          : chatHistory;
      
      for (var msg in limitedHistory) {
        buffer.writeln(msg);
      }
      buffer.writeln("--- END OF PREVIOUS CONVERSATION ---\n");
    }
    
    buffer.writeln("CURRENT USER REQUEST: \"$userMessage\"");
    buffer.writeln("ASSISTANT RESPONSE:");
    
    return buffer.toString();
  }

  String injectMemory(List<String> memories, String message) {
    final buffer = StringBuffer();
    buffer.writeln("You are AURA. The user asked: \"$message\"");
    buffer.writeln("\nBased on the following retrieved memories, provide a helpful answer:");
    for (var memory in memories) {
      buffer.writeln("- $memory");
    }
    return buffer.toString();
  }

  String injectWeb(List<dynamic> results, String message) {
    final buffer = StringBuffer();
    buffer.writeln("Web Search Results for: \"$message\"");
    for (var result in results) {
      buffer.writeln("\nTITLE: ${result.title}");
      buffer.writeln("CONTENT: ${result.snippet}");
    }
    buffer.writeln("\nTASK: Synthesize the information above to answer: \"$message\"");
    buffer.writeln("If the results are partial, answer based on what is available. Do not explicitly say you couldn't find details unless the results are completely irrelevant.");
    buffer.writeln("\nANSWER:");
    return buffer.toString();
  }

  String injectURL(dynamic content, String message) {
    final buffer = StringBuffer();
    buffer.writeln("Webpage Content for: \"$message\"");
    buffer.writeln("PAGE TITLE: ${content.title}");
    buffer.writeln("PAGE EXCERPT:\n${content.snippet}");
    buffer.writeln("\nTASK: Summarize this page to answer: \"$message\"");
    buffer.writeln("\nANSWER:");
    return buffer.toString();
  }
}
