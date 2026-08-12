import 'settings_screen.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import 'chat_screen.dart';
import 'extract_screen.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  List<TaskModel> _tasks = [];
  bool _loading = true;
  bool _aiOnline = false;
  String _aiModel = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final tasks = await _api.getUserTasks(widget.userId);
      final aiStatus = await _api.getAiStatus();
      setState(() {
        _tasks = tasks
            .map((t) => TaskModel.fromJson(t))
            .where((t) => t.status == 'pending')
            .toList();
        _aiOnline = aiStatus['status'] == 'online';
        _aiModel = aiStatus['model'] ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

 Future<void> _markDone(int taskId, String description) async {
  await _api.updateTaskStatus(taskId, 'done');
  await NotificationService().showNotification(
    id: taskId,
    title: '✅ Task Completed!',
    body: description,
  );
  _loadData();
}

  Future<void> _deleteTask(int taskId) async {
    await _api.deleteTask(taskId);
    _loadData();
  }

   @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF12121F),
    body: SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildAiStatusBadge(),
          _buildStatsRow(),
          _buildQuickActions(context),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pending Tasks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(child: _buildTaskList()),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _showAddTaskDialog(context),
      backgroundColor: const Color(0xFF6C63FF),
      child: const Icon(Icons.add, color: Colors.white),
    ),
    bottomNavigationBar: _buildBottomNav(context),
  );
}

Widget _buildBottomNav(BuildContext context) {
  return Container(
    decoration: const BoxDecoration(
      color: Color(0xFF1E1E2E),
      border: Border(
        top: BorderSide(color: Colors.white10),
      ),
    ),
    child: BottomNavigationBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: const Color(0xFF6C63FF),
      unselectedItemColor: Colors.white38,
      currentIndex: 0,
      onTap: (index) {
        if (index == 1) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(userName: widget.userName,userId:widget.userId),
          ));
        }
        if (index == 2) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => SettingsScreen(
              userId: widget.userId,
              userName: widget.userName,
            ),
          ));
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_outline),
          activeIcon: Icon(Icons.chat_bubble),
          label: 'Chat',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    ),
  );
}
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hey, ${widget.userName} 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Here\'s your life summary',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildAiStatusBadge() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _aiOnline
            ? Colors.greenAccent.withValues(alpha: 0.1)
            : Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _aiOnline
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.redAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _aiOnline ? Colors.greenAccent : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _aiOnline ? 'AI Online · $_aiModel' : 'AI Offline · Run: ollama serve',
            style: TextStyle(
              color: _aiOnline ? Colors.greenAccent : Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final high = _tasks.where((t) => t.priority == 'high').length;
    final medium = _tasks.where((t) => t.priority == 'medium').length;
    final low = _tasks.where((t) => t.priority == 'low').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _statCard('Total', '${_tasks.length}', const Color(0xFF6C63FF)),
          const SizedBox(width: 10),
          _statCard('High', '$high', Colors.redAccent),
          const SizedBox(width: 10),
          _statCard('Medium', '$medium', Colors.orangeAccent),
          const SizedBox(width: 10),
          _statCard('Low', '$low', Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _actionButton(
              icon: Icons.auto_awesome,
              label: 'Extract Tasks',
              color: const Color(0xFF6C63FF),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExtractScreen(userId: widget.userId),
                  ),
                );
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _actionButton(
              icon: Icons.chat_bubble_outline,
              label: 'AI Chat',
              color: const Color(0xFF00BCD4),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(userName: widget.userName,userId: widget.userId),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
    }
    if (_tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('No pending tasks!',
                style: TextStyle(color: Colors.white38, fontSize: 15)),
            Text('Use Extract Tasks to find tasks from text',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: _tasks.length,
      itemBuilder: (_, i) => TaskCard(
        task: _tasks[i],
  onDone: () => _markDone(_tasks[i].id, _tasks[i].description),
  onDelete: () => _deleteTask(_tasks[i].id),
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    final controller = TextEditingController();
    String priority = 'medium';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Task',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Task description...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF12121F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setModalState) => Row(
                children: ['high', 'medium', 'low'].map((p) {
                  final selected = priority == p;
                  final color = p == 'high'
                      ? Colors.redAccent
                      : p == 'medium'
                          ? Colors.orangeAccent
                          : Colors.greenAccent;
                  return GestureDetector(
                    onTap: () => setModalState(() => priority = p),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? color : Colors.white24,
                        ),
                      ),
                      child: Text(p,
                          style: TextStyle(
                              color: selected ? color : Colors.white54)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (controller.text.isNotEmpty) {
                    await _api.createTask(
                        widget.userId, controller.text, priority);
                    if (context.mounted) Navigator.pop(context);
                    _loadData();
                  }
                },
                child: const Text('Add Task',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}