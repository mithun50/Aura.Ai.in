import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/services/background_service.dart';
import 'package:aura_mobile/presentation/pages/chat_screen.dart';
import 'package:aura_mobile/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/services/notification_service.dart';
import 'package:aura_mobile/core/services/app_usage_tracker.dart';
import 'package:aura_mobile/core/services/daily_summary_scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:aura_mobile/presentation/widgets/voice_assistant_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Requirement for flutter_foreground_task to receive data in the main isolate
  FlutterForegroundTask.initCommunicationPort();
  
  // Initialize non-critical services after rendering the UI to avoid hangs
  _initServicesAsync();
  
  // Check Onboarding Status
  final prefs = await SharedPreferences.getInstance();
  final isOnboarded = prefs.getBool('is_onboarded') ?? false;
  
  runApp(
    ProviderScope(
      child: AuraApp(initialRoute: isOnboarded ? '/chat' : '/onboarding'),
    ),
  );
}

/// Helper to initialize background services without blocking the main UI thread/splash screen
Future<void> _initServicesAsync() async {
  // Initialize Workmanager
  try {
    await Workmanager().initialize(
      callbackDispatcher, 
      isInDebugMode: false
    );
  } catch (e) {
    debugPrint("Workmanager initialization failed: $e");
  }
  
  // Initialize Local Notifications for Main Isolate
  try {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } catch (e) {
    debugPrint("Local Notifications failed: $e");
  }

  // Initialize RunAnywhere to sync downloads
  try {
    await RunAnywhere().initialize();
  } catch (e) {
    debugPrint("RunAnywhere initialization failed: $e");
  }

  // Initialize notification system
  try {
    final notificationService = NotificationService();
    await notificationService.requestPermissions();
    await notificationService.initialize();
  } catch (e) {
    debugPrint("NotificationService failed: $e");
  }
  
  // Initialize app usage tracking
  try {
    final appUsageTracker = AppUsageTracker();
    await appUsageTracker.trackAppOpen();
  } catch (e) {
    debugPrint("AppUsageTracker failed: $e");
  }
  
  // Initialize daily summary scheduler
  try {
    await DailySummaryScheduler.initialize();
  } catch (e) {
    debugPrint("DailySummaryScheduler failed: $e");
  }
}

class AuraApp extends StatelessWidget {
  final String initialRoute;
  const AuraApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent, // Changed to transparent for overlay
        primaryColor: const Color(0xFFc69c3a), // Gold
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFc69c3a),
          secondary: Color(0xFFe6cf8e),
          surface: Color(0xFF1a1a20),
          background: Colors.transparent,
        ),
        textTheme: GoogleFonts.outfitTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: const Color(0xFFEDEDED),
            displayColor: Colors.white,
          ),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: VoiceAssistantOverlay(
            child: child ?? const SizedBox(),
          ),
        );
      },
      initialRoute: initialRoute,
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/chat': (context) => const ChatScreen(),
      },
    );
  }
}
