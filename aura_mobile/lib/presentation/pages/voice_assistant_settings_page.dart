import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceAssistantSettingsPage extends StatefulWidget {
  const VoiceAssistantSettingsPage({super.key});

  @override
  State<VoiceAssistantSettingsPage> createState() =>
      _VoiceAssistantSettingsPageState();
}

class _VoiceAssistantSettingsPageState
    extends State<VoiceAssistantSettingsPage> with WidgetsBindingObserver {
  // Permission statuses — null = loading
  final Map<String, PermissionStatus?> _statuses = {
    'microphone': null,
    'contacts': null,
    'phone': null,
    'sms': null,
    'camera': null,
    'notification': null,
    'systemAlertWindow': null,
  };

  // Gesture mode: 'shake', 'power', or 'both'
  String _gestureMode = 'both';

  static const _gesturePrefKey = 'va_gesture_mode';
  static const MethodChannel _channel =
      MethodChannel('com.aura.ai/app_control');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Refresh statuses whenever the app resumes (user coming back from settings)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAll();
  }

  Future<void> _loadAll() async {
    await _refreshPermissions();
    await _loadGestureMode();
  }

  Future<void> _refreshPermissions() async {
    final mic = await Permission.microphone.status;
    final contacts = await Permission.contacts.status;
    final phone = await Permission.phone.status;
    final sms = await Permission.sms.status;
    final camera = await Permission.camera.status;
    final notif = await Permission.notification.status;
    final overlay = await Permission.systemAlertWindow.status;

    if (mounted) {
      setState(() {
        _statuses['microphone'] = mic;
        _statuses['contacts'] = contacts;
        _statuses['phone'] = phone;
        _statuses['sms'] = sms;
        _statuses['camera'] = camera;
        _statuses['notification'] = notif;
        _statuses['systemAlertWindow'] = overlay;
      });
    }
  }

  Future<void> _loadGestureMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_gesturePrefKey) ?? 'both';
    if (mounted) setState(() => _gestureMode = saved);
    _applyGestureMode(saved);
  }

  Future<void> _saveGestureMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gesturePrefKey, mode);
    setState(() => _gestureMode = mode);
    _applyGestureMode(mode);
  }

  void _applyGestureMode(String mode) {
    // Notify the native side which gestures to enable
    try {
      _channel.invokeMethod('setGestureMode', {'mode': mode});
    } catch (_) {}
  }

  /// Tap handler: ask permission, or open settings if permanently denied
  Future<void> _handlePermissionTap(Permission permission) async {
    final status = await permission.status;
    if (status.isPermanentlyDenied || status.isRestricted) {
      // Send user to app settings
      await openAppSettings();
    } else if (status.isDenied) {
      // For system alert window, use native intent
      if (permission == Permission.systemAlertWindow) {
        try {
          await _channel.invokeMethod('requestOverlayPermission');
        } catch (_) {
          await openAppSettings();
        }
      } else {
        await permission.request();
      }
    }
    await _refreshPermissions();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  static const _gold = Color(0xFFc69c3a);
  static const _bg = Color(0xFF0E0E14);
  static const _cardBg = Color(0xFF1A1A24);

  Widget _buildPermissionCard({
    required String label,
    required String description,
    required IconData icon,
    required String key,
    required Permission permission,
  }) {
    final status = _statuses[key];
    final bool? granted = status == null ? null : status.isGranted;
    final isPermanent = status?.isPermanentlyDenied ?? false;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (granted == null) {
      statusColor = Colors.white38;
      statusText = 'Checking…';
      statusIcon = Icons.hourglass_empty_rounded;
    } else if (granted) {
      statusColor = const Color(0xFF4CAF50);
      statusText = 'Granted';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = const Color(0xFFE53935);
      statusText = isPermanent ? 'Permanently Denied' : 'Denied';
      statusIcon = Icons.cancel_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted == true
              ? const Color(0xFF4CAF50).withOpacity(0.3)
              : granted == false
                  ? const Color(0xFFE53935).withOpacity(0.3)
                  : Colors.white12,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _gold, size: 22),
        ),
        title: Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              description,
              style: GoogleFonts.outfit(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Icon(statusIcon, color: statusColor, size: 14),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: GoogleFonts.outfit(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ],
        ),
        trailing: granted == true
            ? null
            : TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: _gold.withOpacity(0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                onPressed: () => _handlePermissionTap(permission),
                child: Text(
                  isPermanent ? 'Open Settings' : 'Allow',
                  style: GoogleFonts.outfit(
                    color: _gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildGestureOption({
    required String value,
    required String label,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _gestureMode == value;
    return GestureDetector(
      onTap: () => _saveGestureMode(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _gold.withOpacity(0.12) : _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _gold : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? _gold : Colors.white54,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: selected ? _gold : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _gold, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Voice Assistant Settings',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _gold),
            tooltip: 'Refresh permissions',
            onPressed: _refreshPermissions,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Permissions Section ──────────────────────────────────────────
          _sectionHeader('Required Permissions', Icons.security_rounded),
          const SizedBox(height: 12),

          _buildPermissionCard(
            key: 'microphone',
            label: 'Microphone',
            description: 'Needed to hear your voice commands',
            icon: Icons.mic_rounded,
            permission: Permission.microphone,
          ),
          _buildPermissionCard(
            key: 'contacts',
            label: 'Contacts',
            description: 'Required to find contacts when calling or messaging',
            icon: Icons.contacts_rounded,
            permission: Permission.contacts,
          ),
          _buildPermissionCard(
            key: 'phone',
            label: 'Phone (Make Calls)',
            description: 'Allows AURA to initiate calls directly',
            icon: Icons.phone_rounded,
            permission: Permission.phone,
          ),
          _buildPermissionCard(
            key: 'sms',
            label: 'SMS / Messages',
            description: 'Allows AURA to send messages on your behalf',
            icon: Icons.sms_rounded,
            permission: Permission.sms,
          ),
          _buildPermissionCard(
            key: 'camera',
            label: 'Camera',
            description: 'Used when you say "open camera"',
            icon: Icons.camera_alt_rounded,
            permission: Permission.camera,
          ),
          _buildPermissionCard(
            key: 'notification',
            label: 'Notifications',
            description: 'Required to show the persistent service notification',
            icon: Icons.notifications_rounded,
            permission: Permission.notification,
          ),
          _buildPermissionCard(
            key: 'systemAlertWindow',
            label: 'Display Over Other Apps',
            description:
                'Critical — allows the AURA overlay to appear above everything',
            icon: Icons.picture_in_picture_alt_rounded,
            permission: Permission.systemAlertWindow,
          ),

          const SizedBox(height: 24),

          // ── Gesture Section ──────────────────────────────────────────────
          _sectionHeader('Activation Gesture', Icons.touch_app_rounded),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Choose how to wake up AURA when the app is in the background',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
            ),
          ),

          _buildGestureOption(
            value: 'shake',
            label: 'Shake to Activate',
            subtitle: 'Shake your phone to trigger the assistant',
            icon: Icons.vibration_rounded,
          ),
          _buildGestureOption(
            value: 'power',
            label: 'Double Power Button',
            subtitle:
                'Press power button twice quickly (disable camera shortcut in OEM settings first)',
            icon: Icons.power_settings_new_rounded,
          ),
          _buildGestureOption(
            value: 'both',
            label: 'Both Gestures',
            subtitle: 'Shake or double power button — either works',
            icon: Icons.auto_awesome_rounded,
          ),

          const SizedBox(height: 16),
          _oneplusNote(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: _gold, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            color: _gold,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _oneplusNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'OnePlus tip: If double power button doesn\'t work, go to Settings → Buttons & Gestures → Quick Launch and disable the Camera shortcut.',
              style: GoogleFonts.outfit(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
