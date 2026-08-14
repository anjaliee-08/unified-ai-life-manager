import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/calendar_service.dart';
import '../utils/app_theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const SettingsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  bool _aiOnline = false;
  String _aiModel = '';
  bool _loading = true;
  bool _calendarEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _checkCalendarPermission();
  }

  Future<void> _loadStatus() async {
    final status = await _api.getAiStatus();
    if (!mounted) return;
    setState(() {
      _aiOnline = status['status'] == 'online';
      _aiModel = status['model'] ?? '';
      _loading = false;
    });
  }
  Future<void> _checkCalendarPermission() async {
  final granted = await CalendarService().checkPermission();
  if (mounted) setState(() => _calendarEnabled = granted);
}

Future<void> _requestCalendarPermission() async {
  final granted = await CalendarService().requestPermission();
  if (mounted) setState(() => _calendarEnabled = granted);
}

  Future<void> _logout() async {
    final confirmed = await _showConfirmDialog(
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      destructive: true,
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    }
  }

  Future<void> _clearTasks() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear All Tasks',
      message: 'This will permanently delete all your tasks.',
      confirmLabel: 'Delete All',
      destructive: true,
    );
    if (confirmed == true) {
      final tasks = await _api.getUserTasks(widget.userId);
     for (final t in tasks) {
  await _api.deleteTask(t['id']);
}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('All tasks deleted'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppRadius.md)),
            margin: const EdgeInsets.all(AppSpacing.md),
          ),
        );
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text(title, style: AppTextStyles.titleLarge),
        content: Text(message, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: AppTextStyles.labelLarge.copyWith(
                color: destructive
                    ? AppColors.error
                    : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child:
              Container(height: 0.5, color: AppColors.divider),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // Profile
                _section('Profile', [
                  _infoRow(
                    icon: Icons.person_rounded,
                    label: 'Name',
                    value: widget.userName,
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),

                // AI Engine
                _section('AI Engine', [
                  _aiStatusRow(),
                  const SizedBox(height: AppSpacing.sm),
                  _infoRow(
                    icon: Icons.memory_rounded,
                    label: 'Model',
                    value: _aiModel.isEmpty
                        ? 'Not loaded'
                        : _aiModel,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _infoRow(
                    icon: Icons.shield_rounded,
                    label: 'Privacy',
                    value: 'Local AI · No cloud inference',
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                const SizedBox(height: AppSpacing.md),
_section('Integrations', [
  GestureDetector(
    onTap: _calendarEnabled ? null : _requestCalendarPermission,
    child: AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.calendar_month_rounded,
                color: AppColors.accent, size: 16),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calendar',
                    style: AppTextStyles.bodyLarge),
                Text(
                  _calendarEnabled
                      ? 'Connected · UAILM can read your calendar'
                      : 'Tap to enable calendar access',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _calendarEnabled
                        ? AppColors.accent
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            _calendarEnabled
                ? Icons.check_circle_rounded
                : Icons.arrow_forward_ios_rounded,
            color: _calendarEnabled
                ? AppColors.accent
                : AppColors.textMuted,
            size: 16,
          ),
        ],
      ),
    ),
  ),
]),
                // About
                _section('About', [
                  _infoRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Version',
                    value: '1.0.0',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _infoRow(
                    icon: Icons.code_rounded,
                    label: 'Stack',
                    value: 'Flutter · FastAPI · Ollama',
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),

                // Data
                _section('Data', [
                  _actionRow(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Clear All Tasks',
                    subtitle: 'Permanently delete all tasks',
                    color: AppColors.warning,
                    onTap: _clearTasks,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _actionRow(
                    icon: Icons.logout_rounded,
                    label: 'Logout',
                    subtitle: 'Sign out of your account',
                    color: AppColors.error,
                    onTap: _logout,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),

                // Footer
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.textMuted, size: 20),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Built by Anjali',
                          style: AppTextStyles.bodySmall),
                      Text(
                          'All AI runs locally on your device',
                          style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _aiStatusRow() {
    final color =
        _aiOnline ? AppColors.accent : AppColors.error;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Status',
                    style: AppTextStyles.bodySmall
                        .copyWith(
                            color: AppColors.textSecondary)),
                Text(
                  _aiOnline
                      ? 'Online'
                      : 'Offline — Run: ollama serve',
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: color),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _loading = true);
              _loadStatus();
            },
            child: const Icon(Icons.refresh_rounded,
                color: AppColors.textMuted, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary)),
                Text(value, style: AppTextStyles.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        color: color.withOpacity(0.06),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius:
                    BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: color)),
                  Text(subtitle,
                      style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: color.withOpacity(0.5), size: 18),
          ],
        ),
      ),
    );
  }
}