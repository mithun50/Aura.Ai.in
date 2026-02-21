import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  double _progress = 0.0;
  bool _isDownloading = false;
  String? _error;
  String? _statusMessage;
  String? _taskId;
  // Small lightweight model for mobile
  final String _modelUrl = "https://hf-mirror.com/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true";
  final String _modelFileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf";
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _checkExistingDownloads();
  }

  Future<void> _checkExistingDownloads() async {
    final runAnywhere = ref.read(runAnywhereProvider);
    
    // Check if there is an active task for our model URL
    // In new engine, Task ID = URL
    final taskId = await runAnywhere.getTaskIdForUrl(_modelUrl);
    
    if (taskId != null) {
       // If we found a "task", it means we think it might be running. 
       // But getTaskIdForUrl just returns the URL in current stub.
       // We should rely on the stream updates or file existence for "complete".
       
       // Check if file exists to see if complete
       final docsDir = await getApplicationDocumentsDirectory();
       final file = File('${docsDir.path}/$_modelFileName');
       if (await file.exists()) {
           // We might want to verify size or checksum, but for now assume if it exists it handles it?
           // Or simpler: if it's running via Workmanager, we will get stream updates.
           // If it's done, we might not get updates if app was killed.
           // Let's assume we wait for user to click download if not sure, OR
           // check if we have a way to query Workmanager status?
           // For now, let's just check file existence as "Complete" if it's large enough?
           // Actually, let's just let the UI be "Ready to Download" unless we catch a running stream.
           
           // If we wanted to auto-resume UI from a running task, we'd need Workmanager info.
           // Since we don't have that easily, we'll listen to the stream.
           // If a task is actually running, the worker will send updates to the port.
           // So logging in will catch it.
       }
       
       // Force listen just in case
        _taskId = taskId;
        _listenToDownload(taskId);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listenToDownload(String taskId) {
      final runAnywhere = ref.read(runAnywhereProvider);
      _subscription?.cancel();
      _subscription = runAnywhere.downloadUpdates.listen((update) {
          if (update.id == taskId) {
              if (mounted) {
                  setState(() {
                      _progress = update.progress / 100;
                      if (update.status == DownloadTaskStatus.running) {
                        _statusMessage = "Downloading: ${update.progress}%";
                      } else if (update.status == DownloadTaskStatus.enqueued) {
                        _statusMessage = "Queued for download...";
                        _progress = 0;
                      } else if (update.status == DownloadTaskStatus.paused) {
                        _statusMessage = "Download paused";
                      }
                  });
                  
                  if (update.status == DownloadTaskStatus.complete) {
                      _onDownloadComplete();
                  } else if (update.status == DownloadTaskStatus.failed) {
                      setState(() {
                        _error = "Download failed. Please try again.";
                        _isDownloading = false;
                        _statusMessage = null;
                      });
                  }
              }
          }
      });
  }

  Future<void> _onDownloadComplete() async {
      setState(() {
        _statusMessage = "Initializing AI Engine...";
      });

      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final modelPath = '${docsDir.path}/$_modelFileName';

        // After download, initialize the chat with this model
        final llmService = ref.read(llmServiceProvider);
        await llmService.loadModel(modelPath);
        
        // Navigate to Chat Screen
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/chat');
        }
      } catch (e) {
         setState(() {
            _error = "Initialization failed: $e";
            _isDownloading = false;
         });
      }
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _error = null;
      _statusMessage = "Initializing download...";
    });

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final modelPath = '${docsDir.path}/$_modelFileName';
      
      // Ensure directory exists
      final modelDir = Directory(docsDir.path);
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      
      // Check if file exists and delete it to force fresh download if requested 
      // (or let downloader resume. here we will rely on downloader, but maybe we should warn?)
      // For now, we trust flow. But let's verify path.
      final file = File(modelPath);
      if (await file.exists()) {
         // Optionally check size? 
         // For now, let's just proceed. FlutterDownloader handles resumption.
      }

      // Use RunAnywhere to handle download logic including deduplication
      final runAnywhere = ref.read(runAnywhereProvider);
      
      final taskId = await runAnywhere.downloadModel(
        _modelUrl,
        modelPath,
      );

      if (taskId != null) {
         _taskId = taskId;
         _listenToDownload(taskId);
      } else {
         throw Exception("Failed to start download (taskId is null)");
      }

    } catch (e, stack) {
      print('Download Error: $e');
      print('Stack Trace: $stack');
      if (mounted) {
        setState(() {
          _error = "Download failed: $e";
          _isDownloading = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download_for_offline, size: 80, color: Color(0xFFe6cf8e)),
              const SizedBox(height: 24),
              Text(
                'Setup AI Brain',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'To run offline, AURA needs to download a small AI model (~250MB). This happens only once.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              if (_isDownloading) ...[
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: const Color(0xFF1a1a20),
                  color: const Color(0xFFc69c3a),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage ?? 'Preparing...',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () async {
                    if (_taskId != null) {
                       final runAnywhere = ref.read(runAnywhereProvider);
                       await runAnywhere.cancelDownload(_taskId!);
                    }
                    setState(() {
                      _isDownloading = false;
                      _statusMessage = null;
                      _progress = 0;
                    });
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white54, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You can close the app. Download continues in background.',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                 if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ElevatedButton(
                  onPressed: _startDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFc69c3a),
                    foregroundColor: const Color(0xFF0a0a0c),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Download Model',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
