import 'package:workmanager/workmanager.dart';
import 'package:aura_mobile/core/services/notification_service.dart';
import 'package:aura_mobile/data/datasources/database_helper.dart';
import 'package:aura_mobile/data/repositories/memory_repository_impl.dart';

/// Background task handler logic for daily summary
Future<void> checkAndScheduleDailySummary() async {
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Get tomorrow's events
  final repository = MemoryRepositoryImpl(DatabaseHelper());
  final allMemories = await repository.getMemories();
  
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final tomorrowEvents = allMemories.where((memory) {
    if (memory.eventDate == null) return false;
    final eventDate = memory.eventDate!;
    return eventDate.year == tomorrow.year &&
           eventDate.month == tomorrow.month &&
           eventDate.day == tomorrow.day;
  }).toList();

  // Schedule daily summary if there are events tomorrow
  if (tomorrowEvents.isNotEmpty) {
    await notificationService.scheduleDailySummary(tomorrowEvents.length);
  }
}

class DailySummaryScheduler {
  /// Initialize daily summary background task
  static Future<void> initialize() async {
    // Workmanager is initialized in main.dart with a central callbackDispatcher

    // Schedule daily task at 8 PM
    await Workmanager().registerPeriodicTask(
      'dailySummaryTask',
      'dailySummaryTask',
      frequency: const Duration(hours: 24),
      initialDelay: _getDelayUntil8PM(),
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
    );
  }

  /// Calculate delay until 8 PM today or tomorrow
  static Duration _getDelayUntil8PM() {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 20, 0); // 8 PM today
    
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1)); // 8 PM tomorrow
    }
    
    return target.difference(now);
  }

  /// Cancel daily summary task
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName('dailySummaryTask');
  }
}
