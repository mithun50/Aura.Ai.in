import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final modelRecommendationServiceProvider = Provider((ref) => ModelRecommendationService());

class ModelRecommendationService {
  
  List<ModelInfo> getRecommendations(DeviceInfo device) {
    // aggressive recommendation tailored for low-end devices
    // device.totalRamMB is usually reliable for categorization.
    
    // 4GB RAM Devices (Usually show ~3500-3800 available effectively)
    // We want to show models that are < 3GB in size/RAM usage.
    
    int safeMaxRamUsage;
    
    if (device.totalRamMB <= 4096) {
       // 4GB Device -> Allow up to ~3GB models (risky but allows Phi-2/DeepSeek)
       safeMaxRamUsage = 3500; 
    } else if (device.totalRamMB <= 6144) {
       // 6GB Device -> Allow up to ~4.5GB
       safeMaxRamUsage = 5000;
    } else if (device.totalRamMB <= 8192) {
       // 8GB Device -> Allow up to ~6.5GB
       safeMaxRamUsage = 7000;
    } else {
       // 12GB+ -> Unlimited
       safeMaxRamUsage = 24000;
    }

    return modelCatalog.where((m) {
        // ALWAYS include SmolLM & TinyLlama & Qwen as base options
        if (m.id == 'smollm2-360m' || m.id == 'tinyllama-1.1b' || m.id == 'qwen2-500m') return true;
        
        // For others, check minRamMB against our "Safe Max"
        return m.minRamMB <= safeMaxRamUsage;
    }).toList();
  }
}
