import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

// Model Manager Provider
final modelManagerProvider = Provider((ref) => ModelManager());

// Model Selector State
class ModelSelectorState {
  final List<ModelInfo> availableModels;
  final Set<String> downloadedModelIds;
  final String? activeModelId;
  final Map<String, double> downloadProgress;
  final Map<String, String?> downloadErrors;
  final int totalStorageUsed;

  ModelSelectorState({
    required this.availableModels,
    this.downloadedModelIds = const {},
    this.activeModelId,
    this.downloadProgress = const {},
    this.downloadErrors = const {},
    this.totalStorageUsed = 0,
  });

  bool isDownloaded(String modelId) => downloadedModelIds.contains(modelId);
  bool isActive(String modelId) => activeModelId == modelId;
  bool isDownloading(String modelId) => downloadProgress.containsKey(modelId);
  double getProgress(String modelId) => downloadProgress[modelId] ?? 0.0;
  String? getError(String modelId) => downloadErrors[modelId];

  ModelSelectorState copyWith({
    List<ModelInfo>? availableModels,
    Set<String>? downloadedModelIds,
    String? activeModelId,
    Map<String, double>? downloadProgress,
    Map<String, String?>? downloadErrors,
    int? totalStorageUsed,
  }) {
    return ModelSelectorState(
      availableModels: availableModels ?? this.availableModels,
      downloadedModelIds: downloadedModelIds ?? this.downloadedModelIds,
      activeModelId: activeModelId ?? this.activeModelId,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadErrors: downloadErrors ?? this.downloadErrors,
      totalStorageUsed: totalStorageUsed ?? this.totalStorageUsed,
    );
  }
}

// Model Selector Notifier
class ModelSelectorNotifier extends StateNotifier<ModelSelectorState> {
  final Ref _ref;

  StreamSubscription? _downloadSubscription;
  final Map<String, String> _taskIdToModelId = {};

  ModelSelectorNotifier(this._ref)
      : super(ModelSelectorState(availableModels: modelCatalog)) {
    _loadState();
    _listenToDownloads();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }

  void _listenToDownloads() {
     final runAnywhere = _ref.read(runAnywhereProvider);
     _downloadSubscription = runAnywhere.downloadUpdates.listen((update) {
         final modelId = _taskIdToModelId[update.id];
         if (modelId != null) {
             if (update.status == DownloadTaskStatus.running) {
                 final progress = update.progress / 100;
                 final newProgress = Map<String, double>.from(state.downloadProgress);
                 newProgress[modelId] = progress;
                 state = state.copyWith(downloadProgress: newProgress);
             } else if (update.status == DownloadTaskStatus.complete) {
                 final newProgress = Map<String, double>.from(state.downloadProgress);
                 newProgress.remove(modelId);
                 
                 final newDownloaded = Set<String>.from(state.downloadedModelIds);
                 newDownloaded.add(modelId);
                 
                 // Update storage used (we need to await async method? StateNotifier allows async but here we are in sync listener)
                 // We can trigger async update
                 _updateStorageUsed();

                 state = state.copyWith(
                   downloadProgress: newProgress,
                   downloadedModelIds: newDownloaded,
                 );

                 if (state.activeModelId == null) {
                   selectModel(modelId);
                 }
                 _taskIdToModelId.remove(update.id);
             } else if (update.status == DownloadTaskStatus.failed) {
                 final newProgress = Map<String, double>.from(state.downloadProgress);
                 newProgress.remove(modelId);

                 final newErrors = Map<String, String?>.from(state.downloadErrors);
                 newErrors[modelId] = "Download failed";

                 state = state.copyWith(
                   downloadProgress: newProgress,
                   downloadErrors: newErrors,
                 );
                 _taskIdToModelId.remove(update.id);
             }
         }
     });
  }

  Future<void> _updateStorageUsed() async {
     final modelManager = _ref.read(modelManagerProvider);
     final totalStorage = await modelManager.getTotalStorageUsed();
     state = state.copyWith(totalStorageUsed: totalStorage);
  }

  Future<void> _loadState() async {
    final modelManager = _ref.read(modelManagerProvider);
    final runAnywhere = _ref.read(runAnywhereProvider);
    final prefs = await SharedPreferences.getInstance();

    // Ensure RunAnywhere is initialized so we can check tasks
    await runAnywhere.initialize();

    final downloadedIds = <String>{};
    final downloadProgress = <String, double>{};
    final downloadErrors = <String, String?>{};

    for (final model in modelCatalog) {
       // 1. Check for active download task
       final taskId = await runAnywhere.getTaskIdForUrl(model.url);
       if (taskId != null) {
           print('Found active task $taskId for model ${model.id}');
           _taskIdToModelId[taskId] = model.id;
           downloadProgress[model.id] = 0.0; // Will be updated by stream
           // We could potentially get exact progress from task if we exposed it, but stream will catch up
           continue; 
       }

       // 2. If no active task, check if downloaded AND intact
       if (await modelManager.isModelDownloaded(model.id)) {
           downloadedIds.add(model.id);
       } else {
           // 3. If not downloaded (or corrupted), cleanup
           // verifyAndCleanupModel returns true if valid, false if deleted/missing
           // We already checked isModelDownloaded, so we know it's not valid.
           // Run cleanup to delete partial files if they exist and aren't being downloaded.
           await modelManager.verifyAndCleanupModel(model.id);
       }
    }

    // Get active model candidate
    String? activeModelIdCandidate = prefs.getString('active_model_id');
    if (activeModelIdCandidate != null && !downloadedIds.contains(activeModelIdCandidate)) {
        activeModelIdCandidate = null;
        await prefs.remove('active_model_id');
    }

    // Get total storage
    final totalStorage = await modelManager.getTotalStorageUsed();

    // Set initial state WITHOUT active model to prevent UI mismatch
    state = state.copyWith(
      downloadedModelIds: downloadedIds,
      activeModelId: null, // Wait for load
      downloadProgress: downloadProgress,
      downloadErrors: downloadErrors, 
      totalStorageUsed: totalStorage,
    );

    // If we have a candidate, try to load it
    if (activeModelIdCandidate != null) {
       print('Initialization: Loading active model $activeModelIdCandidate');
       try {
         final modelPath = await modelManager.getModelPath(activeModelIdCandidate);
         final llmService = _ref.read(llmServiceProvider);
         
         // Helper to show loading state if needed? 
         // For now, UI will just show "No model selected" until this finishes.
         
         await llmService.loadModel(modelPath);
         
         // Success! Now update state.
         state = state.copyWith(activeModelId: activeModelIdCandidate);
         print('Initialization: Model $activeModelIdCandidate loaded and active.');
         
       } catch (e) {
         print('Initialization Error: Failed to load active model: $e');
         
         // Notify user of failure via error map?
         final newErrors = Map<String, String?>.from(state.downloadErrors);
         newErrors[activeModelIdCandidate] = "Failed to load on startup: $e";
         state = state.copyWith(downloadErrors: newErrors);
       }
    }
  }

  Future<void> downloadModel(String modelId) async {
    final model = modelCatalog.firstWhere((m) => m.id == modelId);
    final modelManager = _ref.read(modelManagerProvider);
    final runAnywhere = _ref.read(runAnywhereProvider);

    // Clear any previous errors
    final newErrors = Map<String, String?>.from(state.downloadErrors);
    newErrors.remove(modelId);
    state = state.copyWith(downloadErrors: newErrors);

    try {
      final modelPath = await modelManager.getModelPath(modelId);

      final taskId = await runAnywhere.downloadModel(
        model.url,
        modelPath,
      );

      if (taskId != null) {
          _taskIdToModelId[taskId] = modelId;
          // Set initial progress
          final newProgress = Map<String, double>.from(state.downloadProgress);
          newProgress[modelId] = 0.0;
          state = state.copyWith(downloadProgress: newProgress);
      }
    } catch (e) {
      final newProgress = Map<String, double>.from(state.downloadProgress);
      newProgress.remove(modelId);

      final newErrors = Map<String, String?>.from(state.downloadErrors);
      newErrors[modelId] = e.toString();

      state = state.copyWith(
        downloadProgress: newProgress,
        downloadErrors: newErrors,
      );
    }
  }

  Future<void> deleteModel(String modelId) async {
    final modelManager = _ref.read(modelManagerProvider);

    try {
      await modelManager.deleteModel(modelId);

      final newDownloaded = Set<String>.from(state.downloadedModelIds);
      newDownloaded.remove(modelId);

      final totalStorage = await modelManager.getTotalStorageUsed();

      // If deleting active model, clear active model
      String? newActiveModelId = state.activeModelId;
      if (state.activeModelId == modelId) {
        newActiveModelId = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_model_id');
      }

      state = state.copyWith(
        downloadedModelIds: newDownloaded,
        activeModelId: newActiveModelId,
        totalStorageUsed: totalStorage,
      );
    } catch (e) {
      print('Error deleting model: $e');
    }
  }

  Future<void> selectModel(String modelId) async {
    if (!state.isDownloaded(modelId)) {
      print('Cannot select model that is not downloaded');
      return;
    }

    try {
      final modelManager = _ref.read(modelManagerProvider);
      final llmService = _ref.read(llmServiceProvider);
      final modelPath = await modelManager.getModelPath(modelId);

      // Load the model
      await llmService.loadModel(modelPath);

      // Save as active model
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_model_id', modelId);

      state = state.copyWith(activeModelId: modelId);
    } catch (e) {
      print('Error selecting model: $e');
    }
  }

  Future<void> refreshModels() async {
    await _loadState();
  }
}

// Provider
final modelSelectorProvider =
    StateNotifierProvider<ModelSelectorNotifier, ModelSelectorState>((ref) {
  return ModelSelectorNotifier(ref);
});
