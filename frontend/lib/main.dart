import '../utils/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/notification_service.dart';   // ADD THIS

void main() async {
  WidgetsFlutterBinding.ensureInitialized();    // ADD THIS
  await NotificationService().initialize();      // ADD THIS
  runApp(const UAILMApp());
}

class UAILMApp extends StatelessWidget {
  const UAILMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAILM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashRouter(),
    );
  }
}

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome,
                color: Color(0xFF6C63FF), size: 56),
            SizedBox(height: 16),
            Text('UAILM',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            CircularProgressIndicator(
                color: Color(0xFF6C63FF)),
          ],
        ),
      ),
    );
  }
}