import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final deviceServiceProvider = Provider((ref) => DeviceService());

class DeviceInfo {
  final int totalRamMB;
  final int availableRamMB;
  final int totalStorageMB;
  final int availableStorageMB;
  final String androidVersion;
  final bool isArm64;

  DeviceInfo({
    required this.totalRamMB,
    required this.availableRamMB,
    required this.totalStorageMB,
    required this.availableStorageMB,
    required this.androidVersion,
    required this.isArm64,
  });

  @override
  String toString() {
    return 'RAM: ${availableRamMB}/${totalRamMB} MB, Storage: ${availableStorageMB}/${totalStorageMB} MB, Android: $androidVersion, Arm64: $isArm64';
  }
}

class DeviceService {
  static const platform = MethodChannel('com.aura.ai/memory');

  Future<DeviceInfo> analyzeDevice() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    int totalRam = 0;
    int availableRam = 0;
    int totalStorage = 0;
    int availableStorage = 0;
    String androidVersion = 'Unknown';
    bool isArm64 = false;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      androidVersion = androidInfo.version.release;
      isArm64 = androidInfo.supportedAbis.contains('arm64-v8a');
      
      // Native Memory Check
      try {
        final int totalMemBytes = await platform.invokeMethod('getTotalMemory');
        totalRam = (totalMemBytes / (1024 * 1024)).round();
        
        final int availMemBytes = await platform.invokeMethod('getAvailableMemory');
        availableRam = (availMemBytes / (1024 * 1024)).round();
      } catch (e) {
        print("Error getting native memory info: $e");
      }
    }

    // Storage info
    try {
      final freeSpace = await DiskSpace.getFreeDiskSpaceForPath('/');
      final totalSpace = await DiskSpace.getTotalDiskSpace;
      availableStorage = freeSpace?.round() ?? 0;
      totalStorage = totalSpace?.round() ?? 0;
    } catch (e) {
      print("Error getting storage info: $e");
    }

    return DeviceInfo(
      totalRamMB: totalRam,
      availableRamMB: availableRam,
      totalStorageMB: totalStorage,
      availableStorageMB: availableStorage,
      androidVersion: androidVersion,
      isArm64: isArm64,
    );
  }
}
