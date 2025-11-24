import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import '../services/local_storage.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../utils/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  final LocalStorageService _localStorage = LocalStorageService();

  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 3));
    
    if (!mounted) return;

    // Check if user is logged in
    await _localStorage.init();
    final isLoggedIn = _localStorage.isLoggedIn();

    // Navigate to appropriate screen
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            isLoggedIn ? const HomeScreen() : const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0B0C10),
                    const Color(0xFF1F2937),
                    const Color(0xFF0B0C10),
                  ]
                : [
                    AppTheme.primaryBlue,
                    AppTheme.secondaryBlue,
                    AppTheme.primaryBlue,
                  ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo Container
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(35),
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 800.ms)
                  .scale(begin: const Offset(0.5, 0.5), duration: 800.ms, curve: Curves.easeOutBack),
              
              const SizedBox(height: 40),
              
              // App Name with Shimmer Effect
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Colors.white,
                    Color(0xFF00D4FF),
                    Colors.white,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ).createShader(bounds),
                child: Text(
                  'Smart Attendance',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(duration: 2000.ms, color: Colors.white.withOpacity(0.3))
                  .fadeIn(duration: 800.ms, delay: 300.ms),
              
              const SizedBox(height: 12),
              
              // Tagline
              Text(
                'BLE-Powered Attendance Tracking',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.8,
                    ),
              )
                  .animate()
                  .fadeIn(duration: 800.ms, delay: 600.ms)
                  .slideY(begin: 0.3, end: 0, duration: 800.ms),
              
              const SizedBox(height: 60),
              
              // Loading Indicator with Glow
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .fadeIn(duration: 800.ms, delay: 900.ms)
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1.0, 1.0),
                    duration: 1000.ms,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
