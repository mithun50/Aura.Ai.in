import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:fllama/fllama.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:aura_mobile/core/services/foreground_service_handler.dart';

/// Status of a download task
enum DownloadTaskStatus {
  undefined,
  enqueued,
  running,
  complete,
  failed,
  canceled,
  paused;

  static DownloadTaskStatus fromInt(int value) {
    if (value >= 0 && value < DownloadTaskStatus.values.length) {
      return DownloadTaskStatus.values[value];
    }
    return DownloadTaskStatus.undefined;
  }
}

class DownloadUpdate {
  final String id;
  final DownloadTaskStatus status;
  final int progress;
  DownloadUpdate(this.id, this.status, this.progress);
}

class RunAnywhere {
  static final RunAnywhere _instance = RunAnywhere._internal();

  factory RunAnywhere() => _instance;

  RunAnywhere._internal();

  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  double? _contextId;
  String? _currentModelPath;

  /// Whether a model is currently loaded and ready for inference.
  bool get isModelLoaded => _contextId != null;

  final _downloadStreamController =
      StreamController<DownloadUpdate>.broadcast();
  Stream<DownloadUpdate> get downloadUpdates =>
      _downloadStreamController.stream;

  /// Initialize the engine — must be called once at app startup
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      if (kDebugMode) print('RunAnywhere: Initializing...');

    // FIX #1: Initialize FlutterForegroundTask BEFORE any service calls.
    // Without this, startService() silently fails on Android.
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'download_channel',
        channelName: 'Model Downloads',
        channelDescription: 'AI model download progress',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // FIX #4: Safe type casting when receiving data from the foreground task.
    // The platform channel may deliver values as dynamic types.
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is List && data.length >= 3) {
        try {
          final String id = data[0].toString();
          final int status = data[1] is int
              ? data[1] as int
              : int.tryParse(data[1].toString()) ?? 0;
          final int progress = data[2] is int
              ? data[2] as int
              : int.tryParse(data[2].toString()) ?? 0;
          _downloadStreamController.add(
            DownloadUpdate(id, DownloadTaskStatus.fromInt(status), progress),
          );
        } catch (e) {
          if (kDebugMode) print('RunAnywhere: Failed to parse task data: $e');
        }
      }
    });

    // Initialize Token Listener Globally
    Fllama.instance()?.onTokenStream?.listen((data) {
      if (kDebugMode) print('RunAnywhere: Stream Data: $data');
      if (data is! Map) return;

      if (data['function'] == 'completion') {
        final result = data['result'];
        if (result is Map && result.containsKey('token')) {
          final token = result['token']?.toString();
          if (_activeChatController != null &&
              !_activeChatController!.isClosed &&
              token != null) {
            _activeChatController!.add(token);
          }
        }
      } else if (data['function'] == 'loadProgress') {
        if (kDebugMode) print('RunAnywhere: Load Progress: ${data['result']}');
      }
    });

    _isInitialized = true;
    _initCompleter?.complete();
    } catch (e) {
      _initCompleter?.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  StreamController<String>? _activeChatController;

  /// Download model from URL to local path using a Foreground Service.
  /// Returns the taskId (URL) on success, null on failure.
  Future<String?> downloadModel(String url, String destinationPath) async {
    if (!_isInitialized) await initialize();

    // Ensure directory exists
    final file = File(destinationPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    try {
      if (kDebugMode) {
        print('RunAnywhere: Starting Foreground Download: $url');
      }

      final String fileName = file.uri.pathSegments.last;

      // FIX #3: Removed canDrawOverlays check — it opens a system settings
      // screen and blocks the download. SYSTEM_ALERT_WINDOW is NOT needed
      // for a foreground download service.

      // Request battery optimization exemption so Android doesn't kill us
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // Stop any existing service before starting a new download
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync], // Android 14 fix
        notificationTitle: 'Preparing Download',
        notificationText: fileName,
        callback: startCallback,
      );

      // Send download parameters to the service handler
      FlutterForegroundTask.sendDataToTask({
        'url': url,
        'savePath': destinationPath,
        'fileName': fileName,
      });

      return url;
    } catch (e) {
      print('RunAnywhere: Download Dispatch Failed: $e');
      return null;
    }
  }

  /// Cancel a specific download task
  Future<void> cancelDownload(String taskId) async {
    await FlutterForegroundTask.stopService();
  }

  /// Get existing task ID for a URL
  Future<String?> getTaskIdForUrl(String url) async {
    // Return null by default. The background service will announce itself
    // to the UI via the stream when it starts sending progress.
    return null;
  }

  /// Load a model from the given path
  Future<void> loadModel(String modelPath) async {
    if (!_isInitialized) await initialize();

    if (_currentModelPath == modelPath && _contextId != null) {
      if (kDebugMode) print('RunAnywhere: Model already loaded: $modelPath');
      return;
    }

    if (_contextId != null) {
      if (kDebugMode) print('RunAnywhere: Unloading previous model');
      Fllama.instance()?.releaseContext(_contextId!);
      _contextId = null;
    }

    if (kDebugMode) print('RunAnywhere: Loading model from $modelPath');

    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        throw Exception('Model file not found at $modelPath');
      }

      final result = await Fllama.instance()?.initContext(
        modelPath,
        emitLoadProgress: true,
      );

      if (result != null && result.containsKey('contextId')) {
        final id = result['contextId'];
        if (id is double) {
          _contextId = id;
        } else if (id is int) {
          _contextId = id.toDouble();
        } else {
          _contextId = double.tryParse(id.toString());
        }

        if (_contextId != null) {
          _currentModelPath = modelPath;
          if (kDebugMode) {
            print('RunAnywhere: Model loaded. ID: $_contextId');
          }
        } else {
          throw Exception('Failed to parse contextId from $id');
        }
      } else {
        throw Exception(
          'Failed to load model context: Result was null or missing contextId',
        );
      }
    } catch (e) {
      print('RunAnywhere: Load Model Failed: $e');
      rethrow;
    }
  }

  /// Chat with the model (streaming)
  Stream<String> chat({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 512,
  }) {
    if (!_isInitialized) throw Exception('RunAnywhere not initialized');
    if (_contextId == null) throw Exception('No model loaded');

    if (_activeChatController != null && !_activeChatController!.isClosed) {
      _activeChatController!.close();
    }

    // ChatML format
    final StringBuffer promptBuffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      promptBuffer.write('<|im_start|>system\n$systemPrompt\n<|im_end|>\n');
    }
    promptBuffer.write('<|im_start|>user\n$prompt\n<|im_end|>\n');
    promptBuffer.write('<|im_start|>assistant\n');
    final fullPrompt = promptBuffer.toString();

    if (kDebugMode) print('RunAnywhere: Sending Prompt: $fullPrompt');

    _activeChatController = StreamController<String>();
    final controller = _activeChatController!;

    _runInference(controller, fullPrompt, maxTokens);

    return controller.stream;
  }

  Future<void> _runInference(
    StreamController<String> controller,
    String fullPrompt,
    int maxTokens,
  ) async {
    try {
      await Fllama.instance()?.completion(
        _contextId!,
        prompt: fullPrompt,
        stop: ['<|im_end|>', '<|im_start|>', 'User:', 'System:'],
        temperature: 0.7,
        topP: 0.9,
        nPredict: maxTokens,
        emitRealtimeCompletion: true,
      );
    } catch (e) {
      print('Error during inference: $e');
      if (!controller.isClosed) {
        controller.add(' [Error: $e]');
      }
    } finally {
      if (kDebugMode) print('\nRunAnywhere: Generation Complete');
      if (!controller.isClosed) {
        await controller.close();
      }
      if (_activeChatController == controller) {
        _activeChatController = null;
      }
    }
  }

  /// Generate embeddings for a given text
  Future<List<double>> getEmbeddings(String text) async {
    if (!_isInitialized) throw Exception('RunAnywhere not initialized');
    return [];
  }

  void dispose() {
    if (_contextId != null) {
      Fllama.instance()?.releaseContext(_contextId!);
      _contextId = null;
    }
    _downloadStreamController.close();
  }
}
