import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IntentType {
  normalChat,
  storeMemory,
  retrieveMemory,
  queryDocument,
}

final intentDetectionServiceProvider = Provider((ref) => IntentDetectionService());

class IntentDetectionService {
  /// Strictly rule-based intent detection as per SuperGravity architecture.
  /// Does NOT use LLM.
  IntentType detectIntent(String message, {bool hasDocuments = false}) {
    final lowerMessage = message.toLowerCase();

    // 1. Memory Store Rules
    if (lowerMessage.startsWith("remember that") ||
        lowerMessage.startsWith("save this")) {
      return IntentType.storeMemory;
    }

    // 2. Memory Retrieval Rules
    // "If message asks about past saved info -> Memory Retrieval"
    if (lowerMessage.contains("what did i") ||
        lowerMessage.contains("do you remember") ||
        lowerMessage.contains("retrieve") ||
        lowerMessage.contains("recall") ||
        lowerMessage.contains("remind me")) {
      return IntentType.retrieveMemory;
    }

    // 3. Document Mode Rules
    // "If documents exist and similarity score high -> Document Mode"
    // Since we can't check similarity score here without the embedding, 
    // we use a heuristic: if we have docs and the user asks a specific question about them.
    // We will refine this by checking if the query *actually* matches docs in the Orchestrator,
    // but for now, we capture the *intent* to query documents.
    if (hasDocuments) {
       // Heuristic: If it's a question and we have docs, prefer checking docs.
       // Or if explicitly asking to "read" or "summarize".
       if (lowerMessage.contains("read file") || 
           lowerMessage.contains("summarize") || 
           lowerMessage.contains("document") ||
           lowerMessage.contains("pdf")) {
         return IntentType.queryDocument;
       }
    }

    // Default: Normal Chat
    return IntentType.normalChat;
  }

  /// Extracts the content to be saved from a memory command.
  String extractMemoryContent(String message) {
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.startsWith("remember that")) {
      return message.substring("remember that".length).trim();
    }
    if (lowerMessage.startsWith("save this")) {
      return message.substring("save this".length).trim();
    }
    return message;
  }
}
