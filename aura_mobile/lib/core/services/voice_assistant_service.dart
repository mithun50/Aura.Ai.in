import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceAssistantService {
  static const MethodChannel _channel = MethodChannel('com.aura.ai/app_control');
  static bool _isRunning = false;

  static bool get isRunning => _isRunning;

  static Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.contacts,
      Permission.phone,
      Permission.sms,
      Permission.camera,
      Permission.notification,
    ].request();

    // Explicitly request System Alert Window (Display over other apps) via Native Intent
    if (await Permission.systemAlertWindow.isDenied || await Permission.systemAlertWindow.isRestricted) {
       try {
         await _channel.invokeMethod('requestOverlayPermission');
         // We can't await the result perfectly without complex activity results, but opening it is enough.
       } catch (e) {
         debugPrint("Failed to invoke requestOverlayPermission: $e");
       }
    }
    
    // We won't strictly enforce allGranted = false immediately for overlay because the user might just be turning it on in settings.
    if (!await Permission.systemAlertWindow.isGranted) {
       debugPrint("System Alert Window permission not granted for Voice Assistant.");
    }

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      debugPrint("Not all basic permissions granted for Voice Assistant.");
    }
    return allGranted;
  }

  static Future<void> startAssistant() async {
    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      debugPrint("Cannot start assistant without permissions.");
      return;
    }

    try {
      final String result = await _channel.invokeMethod('startAssistant');
      debugPrint(result);
      _isRunning = true;
    } on PlatformException catch (e) {
      debugPrint("Failed to start assistant: '${e.message}'.");
    }
  }

  static Future<void> stopAssistant() async {
    try {
      final String result = await _channel.invokeMethod('stopAssistant');
      debugPrint(result);
      _isRunning = false;
    } on PlatformException catch (e) {
      debugPrint("Failed to stop assistant: '${e.message}'.");
    }
  }
}
