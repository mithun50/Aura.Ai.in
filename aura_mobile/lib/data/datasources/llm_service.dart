import 'package:aura_mobile/ai/run_anywhere_service.dart';

abstract class LLMService {
  Future<void> initialize();
  Future<void> loadModel(String modelPath);
  Stream<String> chat(String prompt, {String? systemPrompt, int maxTokens});
  bool get isModelLoaded;
}

class LLMServiceImpl implements LLMService {
  final RunAnywhere _runAnywhere;

  LLMServiceImpl(this._runAnywhere);

  @override
  Future<void> initialize() async {
    await _runAnywhere.initialize();
  }

  @override
  Future<void> loadModel(String modelPath) async {
    await _runAnywhere.loadModel(modelPath);
  }

  @override
  bool get isModelLoaded => _runAnywhere.isModelLoaded;

  @override
  Stream<String> chat(String prompt, {String? systemPrompt, int maxTokens = 512}) {
    return _runAnywhere.chat(
      prompt: prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    );
  }
}
