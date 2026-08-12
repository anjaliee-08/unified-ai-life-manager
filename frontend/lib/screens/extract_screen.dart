import '../services/notification_service.dart';  // ADD at top
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ExtractScreen extends StatefulWidget {
  final int userId;
  const ExtractScreen({super.key, required this.userId});

  @override
  State<ExtractScreen> createState() => _ExtractScreenState();
}

class _ExtractScreenState extends State<ExtractScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _extractedTasks = [];
  bool _loading = false;
  bool _extracted = false;

 Future<void> _extract() async {
  if (_controller.text.isEmpty) return;
  setState(() { _loading = true; _extracted = false; });

  try {
    final result = await _api.extractTasks(_controller.text);
    final tasks = result['tasks'] ?? [];
    
    setState(() {
      _extractedTasks = tasks;
      _loading = false;
      _extracted = true;
    });

    // Notify user how many tasks were found
    if (tasks.isNotEmpty) {
      await NotificationService().notifyTasksExtracted(tasks.length);
      
      // Extra notification for high priority tasks
      for (final task in tasks) {
        if (task['priority'] == 'high') {
          await NotificationService().notifyHighPriorityTask(
            task['description']
          );
          break; // Only notify for first high priority task
        }
      }
    }
  } catch (e) {
    setState(() => _loading = false);
  }
}

  Future<void> _saveTask(Map<String, dynamic> task) async {
    await _api.createTask(
      widget.userId,
      task['description'],
      task['priority'] ?? 'medium',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task saved!'),
          backgroundColor: Color(0xFF6C63FF),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Extract Tasks',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste any text — email, message, note',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. "Submit report by Friday 5pm, meeting Monday 10am..."',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _extract,
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(_loading ? 'Extracting...' : 'Extract with AI',
                    style: const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_extracted) ...[
              const SizedBox(height: 20),
              Text(
                _extractedTasks.isEmpty
                    ? 'No tasks found in this text'
                    : '${_extractedTasks.length} task(s) found',
                style: TextStyle(
                  color: _extractedTasks.isEmpty
                      ? Colors.white38
                      : Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _extractedTasks.length,
                  itemBuilder: (_, i) {
                    final task = _extractedTasks[i];
                    final priority = task['priority'] ?? 'medium';
                    final color = priority == 'high'
                        ? Colors.redAccent
                        : priority == 'medium'
                            ? Colors.orangeAccent
                            : Colors.greenAccent;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(14),
                       border: Border(
                         left: BorderSide(color: color, width: 3),
                                      ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task['description'] ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(priority,
                                          style: TextStyle(
                                              color: color, fontSize: 11)),
                                    ),
                                    if (task['deadline'] != null) ...[
                                      const SizedBox(width: 8),
                                      Text('📅 ${task['deadline']}',
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _saveTask(task),
                            child: const Text('Save',
                                style: TextStyle(color: Color(0xFF6C63FF))),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}