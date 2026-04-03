import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:semantic_memory_frontend/main.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _isVideoInitialized = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _playVideo();
  }

  void _playVideo() {
    _controller = VideoPlayerController.asset('lib/assets/splash.mp4')
      ..initialize().then((_) {
        // Ensure the video plays and doesn't loop
        _controller.setLooping(false);
        setState(() {
          _isVideoInitialized = true;
        });
        _controller.play();

        // Listen for completion
        _controller.addListener(_checkVideoCompletion);
        
        // Failsafe in case listener doesn't trigger perfectly at the end
        Future.delayed(_controller.value.duration + const Duration(milliseconds: 200), () {
          if (mounted) _navigateToHome();
        });
      }).catchError((e) {
        debugPrint("Error loading video splash: $e");
        _navigateToHome(); // Fallback if video fails
      });
  }

  void _checkVideoCompletion() {
    if (_controller.value.isInitialized) {
      if (_controller.value.position >= _controller.value.duration) {
        _navigateToHome();
      }
    }
  }

  void _navigateToHome() {
    if (_navigated) return;
    _navigated = true;
    _controller.removeListener(_checkVideoCompletion);
    
    // Check if mounted to avoid trying to push after unmount
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_checkVideoCompletion);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: Center(
        child: _isVideoInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const SizedBox(),
      ),
    );
  }
}
