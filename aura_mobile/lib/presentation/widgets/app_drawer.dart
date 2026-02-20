import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/user_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_history_provider.dart'; // New Import
import 'package:aura_mobile/core/services/voice_assistant_service.dart';
import 'package:aura_mobile/presentation/pages/model_selector_screen.dart';
import 'package:aura_mobile/presentation/pages/voice_assistant_settings_page.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:aura_mobile/core/providers/repository_providers.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userProvider);
    final chatState = ref.watch(chatProvider);
    
    // Mock History (replace with real history later)

    return Drawer(
      backgroundColor: const Color(0xFF1a1a20), // Dark Obsidian
      child: SafeArea( // Ensure content is not hidden by status bar
        child: Column(
          children: [
            // 1. User Profile Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFc69c3a), // Gold
                    child: Text(
                      userState.value?.substring(0, 1).toUpperCase() ?? "U",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userState.value ?? "User",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // 2. Main Actions
            ListTile(
              leading: const Icon(Icons.add, color: Colors.white70),
              title: Text("New Chat", style: GoogleFonts.outfit(color: Colors.white)),
              onTap: () {
                // TODO: Clear chat
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.white70),
              title: Text("Generated Images", style: GoogleFonts.outfit(color: Colors.white)),
              onTap: () {
                // TODO: Navigate to gallery
                Navigator.pop(context);
              },
            ),

            const Divider(color: Colors.white10),

            // 3. Chat History (Real)
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final historyAsync = ref.watch(chatHistoryProvider);

                  return historyAsync.when(
                    data: (sessions) {
                      if (sessions.isEmpty) {
                        return Center(
                           child: Padding(
                             padding: const EdgeInsets.all(20.0),
                             child: Text(
                              "No recent chats",
                              style: GoogleFonts.outfit(color: Colors.white30, fontSize: 14),
                             ),
                           ),
                        );
                      }
                      return ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text("Recent", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                          ),
                          ...sessions.map((session) => ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            title: Text(
                              session.title,
                              style: GoogleFonts.outfit(color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _formatDate(session.lastModified),
                              style: GoogleFonts.outfit(color: Colors.white30, fontSize: 10),
                            ),
                            onTap: () {
                              ref.read(chatProvider.notifier).loadSession(session);
                              Navigator.pop(context);
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white30),
                              onPressed: () async {
                                 // Confirm delete or just delete
                                 final repo = ref.read(chatHistoryRepositoryProvider);
                                 await repo.deleteSession(session.id);
                                 ref.invalidate(chatHistoryProvider);
                              },
                            ),
                          )),
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color:  Color(0xFFc69c3a), strokeWidth: 2)),
                    error: (err, stack) => Center(child: Text("Error loading history", style: GoogleFonts.outfit(color: Colors.red))),
                  );
                },
              ),
            ),

            const Divider(color: Colors.white10),

            // 4. Voice Assistant Toggle
            StatefulBuilder(
              builder: (context, setState) {
                return SwitchListTile(
                  secondary: const Icon(Icons.record_voice_over, color: Color(0xFFc69c3a)),
                  title: Text("Voice Assistant", style: GoogleFonts.outfit(color: Colors.white)),
                  subtitle: Text(
                      VoiceAssistantService.isRunning ? "Active" : "Inactive — tap to enable",
                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                  value: VoiceAssistantService.isRunning,
                  activeColor: const Color(0xFFc69c3a),
                  onChanged: (bool value) async {
                    if (value) {
                      await VoiceAssistantService.startAssistant();
                    } else {
                      await VoiceAssistantService.stopAssistant();
                    }
                    setState(() {});
                  },
                );
              }
            ),

            const Divider(color: Colors.white10),

            // 5. Footer (Model Selector & Settings)
            ListTile(
              leading: const Icon(Icons.psychology, color: Color(0xFFc69c3a)), // Gold Icon
              title: Text("Switch Model", style: GoogleFonts.outfit(color: const Color(0xFFc69c3a))),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFc69c3a)),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ModelSelectorScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white70),
              title: Text("Settings", style: GoogleFonts.outfit(color: Colors.white)),
              subtitle: Text("Permissions & Gestures",
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VoiceAssistantSettingsPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return DateFormat('h:mm a').format(date);
    } else if (difference.inDays < 7) {
      return DateFormat('E').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
  }
}
