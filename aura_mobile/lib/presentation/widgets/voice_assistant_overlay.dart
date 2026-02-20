import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VoiceAssistantOverlay extends StatefulWidget {
  final Widget child;

  const VoiceAssistantOverlay({super.key, required this.child});

  @override
  State<VoiceAssistantOverlay> createState() => _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends State<VoiceAssistantOverlay> with SingleTickerProviderStateMixin {
  static const EventChannel _stateChannel = EventChannel('com.aura.ai/assistant_state');
  
  String _assistantState = "IDLE"; // IDLE, LISTENING, PROCESSING
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _stateChannel.receiveBroadcastStream().listen((event) {
      if (mounted) {
        setState(() {
          _assistantState = event.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isActive = _assistantState != "IDLE";
    
    return Material(
      type: MaterialType.transparency,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            widget.child,
            
            // Fading blurred background
            IgnorePointer(
              ignoring: !isActive,
              child: AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
              ),
            ),

            // Sliding bottom panel (Siri / Google Assistant style)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack, // Bouncy spring effect
              left: 0,
              right: 0,
              bottom: isActive ? 0 : -450, // Slide out of view when idle
              height: 350,
              child: Container(
                padding: const EdgeInsets.only(top: 40, bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a1a20), // Dark surface
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFc69c3a).withOpacity(0.15),
                      blurRadius: 40,
                      spreadRadius: 5,
                      offset: const Offset(0, -10),
                    )
                  ],
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFc69c3a).withOpacity(0.3),
                      width: 1,
                    )
                  )
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _assistantState == "LISTENING" ? "Hi there, I'm listening..." : "Thinking about that...",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.0,
                        decoration: TextDecoration.none,
                        fontFamily: 'Outfit'
                      ),
                    ),
                    const Spacer(),
                    // Animated Orb
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        double scale = _assistantState == "LISTENING" 
                            ? 1.0 + (_pulseController.value * 0.15) 
                            : 1.0;
                            
                        double rotation = _assistantState == "PROCESSING" 
                            ? _pulseController.value * 2 * 3.14159
                            : 0.0;
  
                        return Transform.scale(
                          scale: scale,
                          child: Transform.rotate(
                            angle: rotation,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFc69c3a).withOpacity(0.9),
                                    const Color(0xFFc69c3a).withOpacity(0.3),
                                    const Color(0xFFc69c3a).withOpacity(0.0),
                                  ],
                                  stops: const [0.5, 0.8, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFc69c3a).withOpacity(0.4),
                                    blurRadius: 30 * scale,
                                    spreadRadius: 8 * scale,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.2),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  )
                                ]
                              ),
                              child: Center(
                                child: Icon(
                                  _assistantState == "LISTENING" ? Icons.mic : Icons.graphic_eq,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
