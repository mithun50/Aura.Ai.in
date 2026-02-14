
import 'dart:io';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/domain/entities/document.dart';
import 'package:aura_mobile/domain/repositories/document_repository.dart';
import 'package:aura_mobile/domain/services/vector_store_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:aura_mobile/data/repositories/document_repository_impl.dart';

final documentServiceProvider = Provider((ref) => DocumentService(
  ref.read(runAnywhereProvider),
  ref.read(documentRepositoryProvider),
  VectorStoreService(),
));

class DocumentService {
  final RunAnywhere _aiService;
  final DocumentRepository _repository;
  final VectorStoreService _vectorStore;

  DocumentService(this._aiService, this._repository, this._vectorStore);

  Future<void> pickAndProcessDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      await processDocument(file);
    }
  }

  Future<void> processDocument(File file) async {
    String text = "";
    try {
      text = await ReadPdfText.getPDFtext(file.path);
    } catch (e) {
      print("Error reading PDF: $e");
      // Fallback or rethrow?
      return; 
    }

    if (text.isEmpty) return;

    final docId = const Uuid().v4();
    final document = Document(
      id: docId,
      filename: p.basename(file.path),
      path: file.path,
      uploadDate: DateTime.now(),
    );

    // 1. Save Document Metadata
    await _repository.saveDocument(document);

    // 2. Chunk Text
    final chunks = _chunkText(text, 500); // 500 chars approx

    // 3. Generate Embeddings & Save Chunks
    List<DocumentChunk> docChunks = [];
    for (int i = 0; i < chunks.length; i++) {
        final chunkContent = chunks[i];
        try {
            final embedding = await _aiService.getEmbeddings(chunkContent);
            docChunks.add(DocumentChunk(
                id: const Uuid().v4(),
                documentId: docId,
                content: chunkContent,
                chunkIndex: i,
                embedding: embedding,
            ));
        } catch (e) {
            print("Error embedding chunk $i: $e");
        }
    }

    await _repository.saveChunks(docChunks);
  }

  List<String> _chunkText(String text, int chunkSize) {
    List<String> chunks = [];
    final cleanText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    int start = 0;
    while (start < cleanText.length) {
      int end = start + chunkSize;
      
      if (end >= cleanText.length) {
        chunks.add(cleanText.substring(start));
        break;
      }
      
      // Backtrack to last space to avoid splitting words
      int lastSpace = cleanText.lastIndexOf(' ', end);
      if (lastSpace != -1 && lastSpace > start) {
        end = lastSpace;
      }
      
      chunks.add(cleanText.substring(start, end).trim());
      start = end + 1; // Skip the space
    }
    return chunks;
  }

  Future<List<String>> retrieveRelevantContext(String query, {int limit = 5}) async {
    final queryEmbedding = await _aiService.getEmbeddings(query);
    final allChunks = await _repository.getAllChunks(); // Note: Inefficient for large scale, fix later

    final scoredChunks = allChunks.map((chunk) {
      if (chunk.embedding == null) return MapEntry(chunk, -1.0);
      try {
        final score = _vectorStore.cosineSimilarity(queryEmbedding, chunk.embedding!);
        return MapEntry(chunk, score);
      } catch (e) {
        return MapEntry(chunk, -1.0);
      }
    }).toList();

    scoredChunks.sort((a, b) => b.value.compareTo(a.value));

    return scoredChunks
        .take(limit)
        .where((entry) => entry.value > 0.65) // Sim Threshold
        .map((entry) => entry.key.content)
        .toList();
  }
}
