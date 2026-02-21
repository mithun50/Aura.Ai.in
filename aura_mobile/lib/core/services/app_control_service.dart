import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:permission_handler/permission_handler.dart';

final appControlServiceProvider = Provider((ref) => AppControlService());

class AppControlService {
  static const platform = MethodChannel('com.aura.ai/app_control');

  Future<void> openApp(String appName) async {
    try {
      await platform.invokeMethod('openApp', {'appName': appName});
    } on PlatformException catch (e) {
      debugPrint("Failed to open app '$appName': ${e.message}");
      throw "Could not open $appName. ${e.message}";
    }
  }

  Future<void> closeApp(String appName) async {
    try {
      await platform.invokeMethod('closeApp', {'appName': appName});
    } on PlatformException catch (e) {
      debugPrint("Failed to close app '$appName': ${e.message}");
      // Don't throw, just log, as closing apps is restricted
    }
  }

  Future<void> openSettings(String type) async {
    try {
      await platform.invokeMethod('openSettings', {'type': type});
    } on PlatformException catch (e) {
      debugPrint("Failed to open settings '$type': ${e.message}");
      throw "Could not open settings.";
    }
  }

  Future<void> openCamera() async {
    try {
      await platform.invokeMethod('openCamera');
    } on PlatformException catch (e) {
      debugPrint("Failed to open camera: ${e.message}");
      throw "Could not open camera.";
    }
  }

  Future<List<Contact>> resolveContacts(String name) async {
    if (await Permission.contacts.request().isGranted) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final query = name.toLowerCase();
      // Exact or fuzzy match
      return contacts.where((c) {
         final cName = c.displayName.toLowerCase();
         return cName.contains(query);
      }).toList();
    }
    return [];
  }

  Future<void> dialContact(String nameOrNumber) async {
    try {
      // 1. Check if input is a pure number (or resolved from Orchestrator)
      final cleanNumber = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      // 2. It's a number (or look-alike), try to call directly if permission exists
      if (RegExp(r'^[0-9+\- ]+$').hasMatch(nameOrNumber) && cleanNumber.length >= 3) {
         if (await Permission.phone.request().isGranted) {
            try {
               await platform.invokeMethod('callPhoneDirect', {'number': cleanNumber});
               return;
            } catch (e) {
               debugPrint("Direct call failed for number, falling back to dialer: $e");
            }
         }
         // Fallback or permission denied
         await _launchCall(cleanNumber);
         return;
      }

      // 2. It's a name, try to find in contacts
      if (await Permission.contacts.request().isGranted) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        
        // Fuzzy search
        final query = nameOrNumber.toLowerCase();
        final match = contacts.where((c) => c.displayName.toLowerCase().contains(query)).firstOrNull;

        if (match != null && match.phones.isNotEmpty) {
          final number = match.phones.first.number;
          debugPrint("Found contact: ${match.displayName} -> $number");
          
          // Try Direct Call first
          if (await Permission.phone.request().isGranted) {
            try {
               await platform.invokeMethod('callPhoneDirect', {'number': number});
               return;
            } catch (e) {
               debugPrint("Direct call failed, falling back to dialer: $e");
            }
          }
          
          await _launchCall(number);
        } else {
             // Fallback: Open dialer with search query or empty
             await _launchCall(nameOrNumber); 
        }
      } else {
        // No contact permission, check if it's a number and we can call directly
        final cleanNumber = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
        final isNumber = RegExp(r'^[0-9+\- ]+$').hasMatch(nameOrNumber) && cleanNumber.length >= 3;
        
        if (isNumber && await Permission.phone.request().isGranted) {
             try {
               await platform.invokeMethod('callPhoneDirect', {'number': cleanNumber});
               return;
            } catch (e) {
               debugPrint("Direct call failed, falling back to dialer: $e");
            }
        }
        
        // Just open dialer
        await _launchCall(nameOrNumber); 
      }
    } catch (e) {
      debugPrint("Failed to dial '$nameOrNumber': $e");
      // Last resort fallback
      await _launchCall(""); 
    }
  }

  Future<void> _launchCall(String number) async {
    final url = "tel:$number";
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url);
    } else {
      throw "Could not launch dialer for $number";
    }
  }



  Future<void> sendSMS(String nameOrNumber, String message) async {
     try {
      String number = nameOrNumber;
      
      // 1. Check if we need to resolve name to number
      // If it looks like a number, skip lookup
      final cleanNumber = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final isNumber = RegExp(r'^[0-9+\- ]+$').hasMatch(nameOrNumber) && cleanNumber.length >= 3;

      if (!isNumber && await Permission.contacts.request().isGranted) {
         final contacts = await FlutterContacts.getContacts(withProperties: true);
         final query = nameOrNumber.toLowerCase();
         final match = contacts.where((c) => c.displayName.toLowerCase().contains(query)).firstOrNull;
         if (match != null && match.phones.isNotEmpty) {
           number = match.phones.first.number;
         }
      }

      // 2. Try Direct SMS first
      if (await Permission.sms.request().isGranted) {
        try {
           await platform.invokeMethod('sendSMSDirect', {'number': number, 'message': message});
           return;
        } catch (e) {
           debugPrint("Direct SMS failed, falling back to app: $e");
        }
      }

      // 3. Fallback to opening SMS App
      final url = "sms:$number?body=${Uri.encodeComponent(message)}";
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        throw "Could not launch SMS app.";
      }

    } catch (e) {
      debugPrint("Failed to send SMS to '$nameOrNumber': $e");
      throw "Could not send SMS.";
    }
  }

  Future<void> playYouTube(String query) async {
    try {
      await platform.invokeMethod('playYouTube', {'query': query});
    } on PlatformException catch (e) {
      debugPrint("Failed to play YouTube '$query': ${e.message}");
      // Fallback: open YouTube search in browser
      final url = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        throw "Could not open YouTube for '$query'.";
      }
    }
  }

  Future<void> toggleTorch(bool state) async {
    try {
      await platform.invokeMethod('toggleTorch', {'state': state});
    } on PlatformException catch (e) {
      debugPrint("Failed to toggle torch: ${e.message}");
      throw "Could not toggle flashlight. ${e.message}";
    }
  }
}

