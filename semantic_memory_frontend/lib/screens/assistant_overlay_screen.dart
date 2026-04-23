import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/voice_service.dart';
import '../main.dart';

class AssistantOverlayScreen extends StatefulWidget {
  const AssistantOverlayScreen({super.key});

  @override
  State<AssistantOverlayScreen> createState() => _AssistantOverlayScreenState();
}

class _AssistantOverlayScreenState extends State<AssistantOverlayScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isListening = false;
  String _statusText = "Tap mic to search";

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Optionally start listening right away
    // _startListening();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startListening() async {
    setState(() {
      _isListening = true;
      _statusText = "Listening...";
    });
    
    String? query = await VoiceService.listen();
    
    if (mounted) {
      setState(() {
        _isListening = false;
        if (query != null && query.isNotEmpty) {
          _statusText = "Searching for: $query";
          
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => HomeScreen(initialQuery: query),
                ),
              );
            }
          });
        } else {
          _statusText = "Didn't catch that.";
        }
      });
    }
  }

  void _closeOverlay() {
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Transparent Scaffold background
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Semi-transparent background that dismisses on tap
          GestureDetector(
            onTap: _closeOverlay,
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          // Backdrop blur
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(color: Colors.transparent),
          ),
          // The actual popup modal at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                  )
                ]
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.tertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: _startListening,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (_, child) => Transform.scale(
                          scale: _isListening ? _pulseAnimation.value : 1.0,
                          child: child,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.mic,
                            size: 48,
                            color: _isListening ? AppColors.primary : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _statusText,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: _closeOverlay,
                      child: Text(
                        "Close",
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
