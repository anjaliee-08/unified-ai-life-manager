import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(const UAILMApp());
}

class UAILMApp extends StatelessWidget {
  const UAILMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAILM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12121F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
        ),
      ),
      home: const SplashRouter(),
    );
  }
}

// Checks if user already logged in
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final userName = prefs.getString('user_name') ?? '';

    if (mounted) {
      if (userId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              userId: userId,
              userName: userName,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF12121F),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
      ),
    );
  }
}