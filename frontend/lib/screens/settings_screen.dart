import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _api.getAiStatus();
    setState(() {
      _aiOnline = status['status'] == 'online';
      _aiModel = status['model'] ?? '';
      _loading = false;
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Logout',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Are you sure you want to logout?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _clearAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Clear All Tasks',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will delete all your tasks permanently.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final tasks = await _api.getUserTasks(widget.userId);
      for (final task in tasks) {
        await _api.deleteTask(task['id']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All tasks deleted'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Settings',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [

                // Profile section
                _sectionHeader('Profile'),
                _infoTile(
                  icon: Icons.person_outline,
                  title: 'Name',
                  value: widget.userName,
                ),
                const SizedBox(height: 20),

                // AI section
                _sectionHeader('AI Engine'),
                _statusTile(),
                const SizedBox(height: 8),
                _infoTile(
                  icon: Icons.memory,
                  title: 'Model',
                  value: _aiModel.isEmpty ? 'Not loaded' : _aiModel,
                ),
                const SizedBox(height: 8),
                _infoTile(
                  icon: Icons.lock_outline,
                  title: 'Privacy',
                  value: '100% Local — No cloud, no tracking',
                ),
                const SizedBox(height: 20),

                // About section
                _sectionHeader('About'),
                _infoTile(
                  icon: Icons.info_outline,
                  title: 'Version',
                  value: '1.0.0',
                ),
                _infoTile(
                  icon: Icons.code,
                  title: 'Stack',
                  value: 'Flutter + FastAPI + Ollama',
                ),
                const SizedBox(height: 20),

                // Danger zone
                _sectionHeader('Data'),
                _actionTile(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Clear All Tasks',
                  subtitle: 'Permanently delete all tasks',
                  color: Colors.orangeAccent,
                  onTap: _clearAllTasks,
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of your account',
                  color: Colors.redAccent,
                  onTap: _logout,
                ),
                const SizedBox(height: 40),

                // Footer
                const Center(
                  child: Text(
                    'Built with ❤️ by Anjali\nAll AI runs locally on your device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF6C63FF),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _statusTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 10,
              color: _aiOnline ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Status',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                Text(
                  _aiOnline ? 'Online' : 'Offline — Run: ollama serve',
                  style: TextStyle(
                    color: _aiOnline ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh, color: Colors.white38, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}