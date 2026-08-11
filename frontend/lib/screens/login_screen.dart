import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiService _api = ApiService();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String _error = '';

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _nameController.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    setState(() { _loading = true; _error = ''; });

    try {
      final user = await _api.registerUser(
        _emailController.text.trim(),
        _nameController.text.trim(),
      );

      if (user.containsKey('id')) {
        // Save user locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', user['id']);
        await prefs.setString('user_name', user['name']);
        await prefs.setString('user_email', user['email']);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                userId: user['id'],
                userName: user['name'],
              ),
            ),
          );
        }
      } else {
        setState(() {
          _error = user['detail'] ?? 'Something went wrong';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Cannot connect to server. Is backend running?';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Icon(Icons.auto_awesome,
                  color: Color(0xFF6C63FF), size: 48),
              const SizedBox(height: 16),
              const Text('UAILM',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold)),
              const Text('Unified AI Life Manager',
                  style: TextStyle(color: Colors.white54, fontSize: 15)),
              const SizedBox(height: 8),
              const Text('Your tasks. Your AI. Your device.',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              const Spacer(),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Your Name',
                  labelStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.person_outline,
                      color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.email_outlined,
                      color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_error,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Get Started',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}