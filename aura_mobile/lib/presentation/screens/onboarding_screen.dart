import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/domain/services/model_recommendation_service.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  
  // State
  DeviceInfo? _deviceInfo;
  List<ModelInfo> _recommendations = [];
  String? _selectedModelId;

  Future<void> _analyzeDevice() async {
    // Artificial delay for UX "Scanning" effect
    await Future.delayed(const Duration(seconds: 2));

    final deviceService = ref.read(deviceServiceProvider);
    final recService = ref.read(modelRecommendationServiceProvider);

    try {
      final info = await deviceService.analyzeDevice();
      final recs = recService.getRecommendations(info);

      if (mounted) {
        setState(() {
          _deviceInfo = info;
          _recommendations = recs;
        });
        _pageController.nextPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.ease
        );
      }
    } catch (e) {
      debugPrint("Analysis failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c), // Obsidian
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildWelcomeStep(),
          _buildAnalysisStep(),
          _buildRecommendationStep(),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_moon, size: 80, color: Color(0xFFc69c3a)), // Premium Gold
          const SizedBox(height: 24),
          Text(
            "Welcome to AURA",
            style: GoogleFonts.outfit(
              color: Colors.white, 
              fontSize: 32, 
              fontWeight: FontWeight.bold
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Your private, offline AI assistant.\nLet's get to know you.",
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 48),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter your name",
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Colors.grey[900],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_nameController.text.isNotEmpty) {
                 _pageController.nextPage(
                   duration: const Duration(milliseconds: 300), 
                   curve: Curves.ease
                 );
                 _analyzeDevice();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFc69c3a), // Premium Gold
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text("Next", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFD4AF37)),
          const SizedBox(height: 24),
          Text(
            "Analyzing Device Hardware...",
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          if (_deviceInfo != null) ...[
            const SizedBox(height: 20),
            Text("RAM: ${_deviceInfo!.totalRamMB} MB", style: TextStyle(color: Colors.grey)),
            Text("Arch: ${_deviceInfo!.isArm64 ? 'Arm64' : 'Unknown'}", style: TextStyle(color: Colors.grey)),
          ]
        ],
      ),
    );
  }

  Widget _buildRecommendationStep() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Hello ${_nameController.text},",
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Based on your device capability,\nwe recommend these models:",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _recommendations.length,
                itemBuilder: (context, index) {
                  final model = _recommendations[index];
                  // First item is likely "Best" (or use logic)
                  String badge = "";
                  Color badgeColor = Colors.transparent;
                  
                  // Simple badge logic
                  if (model.id.contains('smollm')) {
                     badge = "🪶 Lightweight";
                     badgeColor = Colors.green;
                  } else if (model.id.contains('mistral') || model.id.contains('llama-3')) {
                     badge = "⭐ Best Performance";
                     badgeColor = const Color(0xFFD4AF37);
                  } else {
                     badge = "⚖ Balanced";
                     badgeColor = Colors.blue;
                  }

                  return Card(
                    color: Colors.grey[900],
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _selectedModelId == model.id ? const Color(0xFFD4AF37) : Colors.transparent,
                        width: 2
                      )
                    ),
                    child: InkWell(
                      onTap: () {
                         setState(() => _selectedModelId = model.id);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    badge,
                                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                Text(
                                  model.sizeFormatted,
                                  style: const TextStyle(color: Colors.grey),
                                )
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              model.name,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              model.description,
                              style: TextStyle(color: Colors.grey[400], fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            if (_selectedModelId == model.id)
                              Column(
                                children: [
                                  if (_isDownloading && _downloadTaskId != null)
                                    Column(
                                      children: [
                                        LinearProgressIndicator(
                                          value: _downloadProgress / 100,
                                          backgroundColor: Colors.grey[800],
                                          color: const Color(0xFFD4AF37),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "${_downloadProgress}% - $downloadStatusText",
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: _isDownloading ? null : () => _startDownload(model),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFD4AF37),
                                        foregroundColor: Colors.black,
                                        minimumSize: const Size(double.infinity, 40),
                                      ),
                                      child: const Text("Download & Start"),
                                    ),
                                ],
                              )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),
            Center(
              child: Text(
                "Debug: RAM ${_deviceInfo?.totalRamMB}MB / Avail ${_deviceInfo?.availableRamMB}MB", 
                style: TextStyle(color: Colors.grey[800], fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Download State
  bool _isDownloading = false;
  String? _downloadTaskId;
  int _downloadProgress = 0;
  String downloadStatusText = "Starting...";

  Future<void> _startDownload(ModelInfo model) async {
    // 1. Request Notification Permission (Android 13+)
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      status = await Permission.notification.request();
      if (!status.isGranted) {
         // Show warning but proceed (download might still work in background, just no notif)
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Warning: Notifications disabled. Download will run silently in background.")),
            );
         }
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      downloadStatusText = "Starting...";
    });

    try {
       // Get strict path
       final directory = await getApplicationDocumentsDirectory();

       if (!await directory.exists()) {
          await directory.create(recursive: true);
       }

       final filePath = "${directory.path}/${model.fileName}";
       
       // Start Download via RunAnywhere (which wraps Workmanager)
       // Debug Print
       print("DEBUG: Requesting download for ${model.url} to $filePath");
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Download Request Sent: ${model.name}")),
          );
       }

       final taskId = await RunAnywhere().downloadModel(model.url, filePath);
       
       if (taskId != null) {
          setState(() => _downloadTaskId = taskId);
          
          // Listen to updates
          RunAnywhere().downloadUpdates.listen((update) {
             print("DEBUG: UI Received Update: ${update.id} - ${update.status} - ${update.progress}");
             if (update.id == taskId) {
                if (mounted) {
                   setState(() {
                      _downloadProgress = update.progress;
                      if (update.status == DownloadTaskStatus.running) {
                         downloadStatusText = "Downloading... ${update.progress}%";
                      } else if (update.status == DownloadTaskStatus.complete) {
                         downloadStatusText = "Finalizing...";
                         _finalizeOnboarding(model, filePath);
                      } else if (update.status == DownloadTaskStatus.failed) {
                         downloadStatusText = "Failed. Retrying...";
                         _isDownloading = false;
                         ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Download Failed. Please check internet connection.")),
                         );
                      }
                   });
                }
             }
          });
       }
    } catch (e) {
       print("Download error: $e");
       if (mounted) {
         setState(() {
            _isDownloading = false;
            downloadStatusText = "Error: $e";
         });
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error starting download: $e")),
         );
       }
    }
  }

  Future<void> _finalizeOnboarding(ModelInfo model, String path) async {
     // Save prefs
     final prefs = await SharedPreferences.getInstance();
     await prefs.setString('user_name', _nameController.text);
     await prefs.setBool('is_onboarded', true);
     await prefs.setString('selected_model_id', model.id);
     await prefs.setString('selected_model_path', path);
     
     // Initialize Model
     try {
       await RunAnywhere().loadModel(path);
     } catch (e) {
       print("Auto-load failed: $e");
     }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/chat');
        }
  }
}
