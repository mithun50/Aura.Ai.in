class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String url;
  final int sizeBytes;
  final String ramRequirement;
  final String speed;
  final String fileName;
  final int minRamMB;

  ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.sizeBytes,
    required this.ramRequirement,
    required this.speed,
    required this.fileName,
    required this.minRamMB,
  });

  String get sizeFormatted {
    final sizeMB = sizeBytes / (1024 * 1024);
    if (sizeMB < 1024) {
      return '${sizeMB.toStringAsFixed(0)} MB';
    }
    final sizeGB = sizeMB / 1024;
    return '${sizeGB.toStringAsFixed(1)} GB';
  }
}

// Model Catalog
final List<ModelInfo> modelCatalog = [
  ModelInfo(
    id: 'smollm2-360m',
    name: 'SmolLM2 360M',
    description: 'Ultra-fast, minimal RAM usage. Best for quick responses.',
    url: 'https://hf-mirror.com/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf?download=true',
    fileName: 'smollm2-360m.gguf',
    sizeBytes: 209715200, // 200MB
    ramRequirement: '1GB',
    minRamMB: 1024,
    speed: 'Very Fast',
  ),
  ModelInfo(
    id: 'qwen2-500m',
    name: 'Qwen2 500M',
    description: 'Balanced speed and quality. Good for general chat.',
    url: 'https://hf-mirror.com/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_k_m.gguf?download=true',
    fileName: 'qwen2-500m.gguf',
    sizeBytes: 314572800, // 300MB
    ramRequirement: '1.5GB',
    minRamMB: 1536,
    speed: 'Fast',
  ),
  ModelInfo(
    id: 'tinyllama-1.1b',
    name: 'TinyLlama 1.1B',
    description: 'Compact yet capable. Great for longer conversations.',
    url: 'https://hf-mirror.com/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf?download=true',
    fileName: 'tinyllama-1.1b.gguf',
    sizeBytes: 669515776, // 638MB
    ramRequirement: '2GB',
    minRamMB: 2048,
    speed: 'Medium',
  ),
  ModelInfo(
    id: 'phi-2-1.3b',
    name: 'Phi-2 1.3B',
    description: 'High quality reasoning. Best for complex tasks.',
    url: 'https://hf-mirror.com/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf?download=true',
    fileName: 'phi-2-1.3b.gguf',
    sizeBytes: 1782579200, // ~1.7GB (Corrected size for Q4_K_M)
    ramRequirement: '4GB',
    minRamMB: 3072, // Can run on 4GB devices with optimization
    speed: 'Medium',
  ),
  ModelInfo(
    id: 'deepseek-r1-distill-qwen-1.5b',
    name: 'DeepSeek R1 Distill 1.5B',
    description: 'State-of-the-art reasoning model distilled from DeepSeek R1.',
    url: 'https://hf-mirror.com/Second-State/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf?download=true',
    fileName: 'deepseek-r1-distill-qwen-1.5b.gguf',
    sizeBytes: 943718400, // ~900MB
    ramRequirement: '3GB',
    minRamMB: 3072,
    speed: 'Fast',
  ),
  ModelInfo(
    id: 'llama-3.2-3b',
    name: 'Llama 3.2 3B',
    description: 'Advanced reasoning and coding capabilities.',
    url: 'https://hf-mirror.com/hugging-quants/Llama-3.2-3B-Instruct-Q4_K_M-GGUF/resolve/main/llama-3.2-3b-instruct-q4_k_m.gguf',
    fileName: 'llama-3.2-3b.gguf',
    sizeBytes: 2000000000, 
    ramRequirement: '4GB', 
    minRamMB: 4096, 
    speed: 'Medium',
  ),
  ModelInfo(
    id: 'mistral-7b',
    name: 'Mistral 7B',
    description: 'Desktop-class performance. Unmatched knowledge.',
    url: 'https://hf-mirror.com/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf',
    fileName: 'mistral-7b.gguf',
    sizeBytes: 4300000000, 
    ramRequirement: '8GB',
    minRamMB: 8192,
    speed: 'Slow',
  ),
];
