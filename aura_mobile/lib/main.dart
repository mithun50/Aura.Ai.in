import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/presentation/pages/chat_screen.dart';
import 'package:aura_mobile/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/services/notification_service.dart';
import 'package:aura_mobile/core/services/app_usage_tracker.dart';
import 'package:aura_mobile/core/services/daily_summary_scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'dart:isolate';
import 'dart:ui';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FlutterDownloader
  await FlutterDownloader.initialize(
    debug: true, // debug: false to disable console log
    ignoreSsl: true // option: false to disable working with http links
  );

  // Initialize RunAnywhere to sync downloads
  try {
    await RunAnywhere().initialize();
  } catch (e) {
    print("RunAnywhere initialization failed: $e");
  }

  // Initialize notification system
  final notificationService = NotificationService();
  await notificationService.requestPermissions();
  await notificationService.initialize();
  
  // Initialize app usage tracking
  final appUsageTracker = AppUsageTracker();
  await appUsageTracker.trackAppOpen();
  
  // Initialize daily summary scheduler
  await DailySummaryScheduler.initialize();
  
  // Check Onboarding Status
  final prefs = await SharedPreferences.getInstance();
  final isOnboarded = prefs.getBool('is_onboarded') ?? false;
  
  runApp(
    ProviderScope(
      child: AuraApp(initialRoute: isOnboarded ? '/chat' : '/onboarding'),
    ),
  );
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
        scaffoldBackgroundColor: const Color(0xFF0a0a0c),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: const Color(0xFFEDEDED)),
        ),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/chat': (context) => const ChatScreen(),
      },
    );
  }
}
