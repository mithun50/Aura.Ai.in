import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:aura_mobile/core/services/daily_summary_scheduler.dart';
import 'package:path_provider/path_provider.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Native: Background Task Started: $task");
    await _logToFile("Native: Background Task Started: $task");
    
    if (task == 'dailySummaryTask') {
      await checkAndScheduleDailySummary();
      return Future.value(true);
    }

    if (task == 'download_model_task') {
      if (inputData == null) return Future.value(false);
      
      final String url = inputData['url'];
      final String savePath = inputData['savePath'];
      final String fileName = inputData['fileName'];
      final int notificationId = inputData['notificationId'] ?? 1001;

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      final dio = Dio(BaseOptions(
        connectTimeout: Duration(minutes: 1),
        receiveTimeout: Duration(minutes: 60), // Allow long downloads
        sendTimeout: Duration(minutes: 1),
      ));
      
      try {
        // Create the notification channel (critical for Android 8+)
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'download_channel',
          'Model Downloads',
          description: 'Progress of AI model downloads',
          importance: Importance.low, // Low importance to prevent sound/vibration on every update
        );

        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        await dio.download(
          url,
          savePath,
          onReceiveProgress: (received, total) {
             if (total != -1) {
               int progress = ((received / total) * 100).toInt();
               
               if (progress % 5 == 0) { // Update every 5%
                 _showProgressNotification(flutterLocalNotificationsPlugin, notificationId, fileName, progress, false);
                 _logToFile("Download Progress: $progress% for $fileName");
                 
                 // Try to communicate back to main isolate if app is open
                 final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
                 send?.send([url, 2, progress]); // 2 = Running
               }
             }
          },
          deleteOnError: true,
        );

        // Success
        await _logToFile("Download Success: $fileName");
        _showProgressNotification(flutterLocalNotificationsPlugin, notificationId, fileName, 100, true);
        final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
        send?.send([url, 3, 100]); // 3 = Complete
        
        return Future.value(true);

      } catch (e) {
        print("Native: Download Failed: $e");
        await _logToFile("Native: Download Failed: $e");
        _showProgressNotification(flutterLocalNotificationsPlugin, notificationId, "Download Failed", 0, false, isError: true);
        final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
        send?.send([url, 4, 0]); // 4 = Failed
        
        return Future.value(false);
      }
    }

    return Future.value(true);
  });
}

Future<void> _showProgressNotification(
    FlutterLocalNotificationsPlugin plugin, 
    int id, 
    String title, 
    int progress, 
    bool isComplete,
    {bool isError = false}) async {
  
  String contentText = isError ? 'Download failed.' : (isComplete ? 'Download complete.' : 'Downloading... $progress%');
  
  await plugin.show(
    id,
    'Model: $title',
    contentText,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'download_channel',
        'Model Downloads',
        channelDescription: 'Progress of AI model downloads',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        showProgress: !isComplete && !isError,
        maxProgress: 100,
        progress: progress,
        ongoing: !isComplete && !isError,
        autoCancel: false,
      ),
    ),
);
}

Future<void> _logToFile(String message) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/background_download.log');
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString('$timestamp: $message\n', mode: FileMode.append);
  } catch (e) {
    print("Failed to write log: $e");
  }
}
