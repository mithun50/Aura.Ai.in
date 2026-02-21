import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/widgets/app_drawer.dart';
import 'package:aura_mobile/presentation/widgets/greeting_widget.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/widgets/code_element_builder.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showCommandMenu = false;
  bool _isWebSearchMode = false;


  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // 1. Update text field in real-time as user speaks
    ref.listen(chatProvider.select((s) => s.partialVoiceText), (prev, next) {
      if (next.isNotEmpty) {
        _controller.text = next;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });

    // 2. Clear text field explicitly when listening stops
    ref.listen(chatProvider.select((s) => s.isListening), (prev, next) {
      if (prev == true && next == false) {
        _controller.clear();
      }
    });
    final modelState = ref.watch(modelSelectorProvider);
    final isModelLoading = chatState.isModelLoading || modelState.activeModelId == null;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c), // Obsidian - Keep opaque for normal app use
      drawer: const AppDrawer(), // Sidebar Implementation
      extendBodyBehindAppBar: true, // Transparent AppBar effect
      appBar: AppBar(
        title: Consumer(
          builder: (context, ref, child) {
            final modelState = ref.watch(modelSelectorProvider);
            final chatState = ref.watch(chatProvider);
            
            // Unified loading/readiness state
            final isAppInitializing = modelState.activeModelId == null || chatState.isModelLoading;

            if (isAppInitializing) {
                 return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1a1a20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      "Loading...",
                      style: GoogleFonts.outfit(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                 );
            }

            final activeModel = modelState.availableModels.firstWhere(
              (m) => m.id == modelState.activeModelId,
              orElse: () => modelState.availableModels.first,
            );
            
            return GestureDetector(
              onTap: () {
                 Scaffold.of(context).openDrawer(); 
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a1a20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  activeModel.name,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0a0a0c).withOpacity(0.7), // Semi-transparent Obsidian
        elevation: 0,
        leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
                backgroundColor: const Color(0xFF1a1a20),
                child: Builder(
                  builder: (context) {
                    return IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white70, size: 20),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                    );
                  }
                ),
            ),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
            Padding(
                padding: const EdgeInsets.only(right: 8.0),
                 child: CircleAvatar(
                    backgroundColor: const Color(0xFF1a1a20),
                    child: IconButton(
                        icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                        tooltip: "New Chat",
                        onPressed: () {
                          // Clear chat history
                          ref.read(chatProvider.notifier).clearChat();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("New chat started"), duration: Duration(seconds: 1)),
                          );
                        },
                    ),
                ),
            ),
             Padding(
                padding: const EdgeInsets.only(right: 16.0),
                 child: CircleAvatar(
                    backgroundColor: const Color(0xFF1a1a20),
                    child: IconButton(
                        icon: const Icon(Icons.more_horiz, color: Colors.white70, size: 20),
                         tooltip: "Options",
                        onPressed: () {
                           ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Settings coming soon!"), duration: Duration(seconds: 1)),
                          );
                        },
                    ),
                ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                 // 1. Chat Content or Welcome Message
                 Positioned.fill(
                   child: chatState.messages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 60), // Offset for transparent AppBar
                              SizedBox(width: double.infinity, child: GreetingWidget()), // Dynamic Greeting
                            ],
                          ),
                        ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 100, 16, 80), // Top padding for AppBar
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, index) {
                          final msg = chatState.messages[index];
                          final isUser = msg['role'] == 'user';
                          final content = msg['content'] ?? '';
                          
                          // Parse Options
                          String displayContent = content;
                          List<Map<String, String>> options = [];
                          
                          final optionsRegex = RegExp(r'\[\[OPTIONS:(.*?)\]\]');
                          final match = optionsRegex.firstMatch(content);
                          if (match != null) {
                            displayContent = content.substring(0, match.start).trim();
                            final optionsStr = match.group(1) ?? "";
                            options = optionsStr.split(',').map((e) {
                              final parts = e.split('|');
                              return {
                                'label': parts[0].trim(),
                                'value': parts.length > 1 ? parts[1].trim() : parts[0].trim()
                              };
                            }).toList();
                          }

                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8), 
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                                  decoration: BoxDecoration(
                                    color: isUser ? const Color(0xFF2a2a30) : Colors.transparent, 
                                    borderRadius: BorderRadius.circular(20).copyWith(
                                      bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                                      bottomLeft: !isUser ? Radius.zero : const Radius.circular(20),
                                    ),
                                    border: isUser 
                                        ? Border.all(color: const Color(0xFFc69c3a).withOpacity(0.3)) 
                                        : null, 
                                  ),
                                  child: MarkdownBody(
                                    data: displayContent,
                                    builders: {
                                      'code': CodeElementBuilder(context),
                                    },
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(
                                        color: isUser ? Colors.white : Colors.white.withOpacity(0.9),
                                        fontSize: 16,
                                        height: 1.5,
                                        fontFamily: GoogleFonts.outfit().fontFamily,
                                      ),
                                      strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      a: const TextStyle(color: Color(0xFFc69c3a), decoration: TextDecoration.underline),
                                      code: const TextStyle(
                                          color: Color(0xFFe6cf8e), 
                                          backgroundColor: Color(0xFF1a1a20), 
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                      ),
                                    ),
                                    onTapLink: (text, href, title) async {
                                      if (href != null) {
                                        final Uri url = Uri.parse(href);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Could not launch $href')),
                                          );
                                        }
                                      }
                                    },
                                    selectable: true,
                                  ),
                                ),
                                if (options.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: options.map((opt) {
                                        return ActionChip(
                                          label: Text(opt['label']!, style: GoogleFonts.outfit(color: Colors.white)),
                                          backgroundColor: const Color(0xFF2a2a30),
                                          side: const BorderSide(color: Color(0xFFc69c3a)),
                                          onPressed: () {
                                            _sendMessage(opt['value']!);
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                 ),

                 // 2. Command Menu (Floating Popup)
                 if (_showCommandMenu)
                  Positioned(
                    bottom: 8,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a20), // Dark background
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFc69c3a), width: 1), // Gold border
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.public, color: Color(0xFFc69c3a)),
                              title: Text('Web Search', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text('Search the internet for real-time info', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                              onTap: () {
                                setState(() {
                                  _isWebSearchMode = true;
                                  _showCommandMenu = false;
                                  _controller.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (chatState.isThinking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                children: [
                   const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFc69c3a))),
                   const SizedBox(width: 12),
                   Text("Thinking...", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          
          // Input Area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF0a0a0c),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1a1a20),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        if (_isWebSearchMode)
                           IconButton(
                              icon: const Icon(Icons.public_off, color: Color(0xFFc69c3a), size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _isWebSearchMode = false;
                                });
                              },
                          )
                        else
                          const Icon(Icons.add, color: Colors.white54),
                        
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            enabled: !isModelLoading,
                            style: GoogleFonts.outfit(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: isModelLoading 
                                  ? 'Model loading...' 
                                  : (_isWebSearchMode ? 'Search the web...' : 'Ask Aura...'),
                              hintStyle: GoogleFonts.outfit(color: Colors.white30),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            onChanged: (value) {
                               final shouldShow = value.trim().startsWith('/') || value.trim().startsWith('@');
                               if (_showCommandMenu != shouldShow) {
                                  setState(() {
                                    _showCommandMenu = shouldShow;
                                  });
                               }
                            },
                            onSubmitted: (value) => _sendMessage(value),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            chatState.isListening ? Icons.mic_off : Icons.mic, 
                            color: chatState.isModelLoading ? Colors.white10 : Colors.white54
                          ),
                          onPressed: isModelLoading ? null : () {
                            if (chatState.isListening) {
                              ref.read(chatProvider.notifier).stopListening();
                            } else {
                              ref.read(chatProvider.notifier).startListening();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: isModelLoading ? null : () => _sendMessage(_controller.text),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isModelLoading 
                            ? [const Color(0xFF2a2a30), const Color(0xFF1a1a20)]
                            : [const Color(0xFFe6cf8e), const Color(0xFFc69c3a)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_upward, 
                      color: isModelLoading ? Colors.white10 : Colors.black
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String text) {
     if (text.trim().isNotEmpty) {
      final messageToSend = _isWebSearchMode ? "[SEARCH] $text" : text;
      ref.read(chatProvider.notifier).sendMessage(messageToSend);
      _controller.clear();
      setState(() {
        _isWebSearchMode = false;
         // Toggle menu off
      });
    }
  }

}
