import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/app_theme.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;
  String _error = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final user = await _api.registerUser(
        _emailController.text.trim(),
        _nameController.text.trim(),
      );

      if (user.containsKey('id')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', user['id']);
        await prefs.setString('user_name', user['name']);
        await prefs.setString('user_email', user['email']);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => DashboardScreen(
                userId: user['id'],
                userName: user['name'],
              ),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration:
                  const Duration(milliseconds: 300),
            ),
          );
        }
      } else {
        setState(() {
          _error = user['detail'] ?? 'Something went wrong';
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Cannot connect. Is the backend running?';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),
                  // Logo area
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius:
                          BorderRadius.circular(AppRadius.lg),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('UAILM',
                      style: AppTextStyles.displayLarge),
                  Text(
                    'Your private AI life manager',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _pill('Local AI'),
                      const SizedBox(width: AppSpacing.sm),
                      _pill('Private'),
                      const SizedBox(width: AppSpacing.sm),
                      _pill('Offline'),
                    ],
                  ),
                  const Spacer(flex: 2),

                  // Form
                  AppTextField(
                    controller: _nameController,
                    hint: 'Your name',
                    label: 'NAME',
                    prefixIcon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _emailController,
                    hint: 'your@email.com',
                    label: 'EMAIL',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 14),
                        const SizedBox(width: 6),
                        Text(_error,
                            style: AppTextStyles.bodySmall
                                .copyWith(
                                    color: AppColors.error)),
                      ],
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Get Started',
                    loading: _loading,
                    width: double.infinity,
                    onTap: _login,
                  ),
                  const Spacer(flex: 1),
                  Center(
                    child: Text(
                      'All data stays on your device',
                      style: AppTextStyles.caption,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.2),
            width: 0.5),
      ),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: AppColors.primary)),
    );
  }
}