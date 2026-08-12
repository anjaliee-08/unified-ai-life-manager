import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome,
                  color: Color(0xFF6C63FF), size: 64),
              SizedBox(height: 20),
              Text(
                'UAILM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Unified AI Life Manager',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Powered by Local AI',
                style: TextStyle(
                  color: Color(0xFF6C63FF),
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 48),
              CircularProgressIndicator(
                color: Color(0xFF6C63FF),
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}