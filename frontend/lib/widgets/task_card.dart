import 'package:flutter/material.dart';
import '../models/task_model.dart';

class TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onDone;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onDone,
    required this.onDelete,
  });

  Color _priorityColor() {
    switch (task.priority) {
      case 'high':
        return Colors.red.shade400;
      case 'medium':
        return Colors.orange.shade400;
      default:
        return Colors.green.shade400;
    }
  }

  IconData _sourceIcon() {
    switch (task.source) {
      case 'email':
        return Icons.email_outlined;
      case 'message':
        return Icons.message_outlined;
      default:
        return Icons.edit_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
       border: Border(
       left: BorderSide(
        color: _priorityColor(),
        width: 4,
        ),
       ),
      ),
      child: Row(
        children: [
          // Priority dot
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _priorityColor(),
              shape: BoxShape.circle,
            ),
          ),

          // Task info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(_sourceIcon(), size: 12, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      task.source,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _priorityColor().withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task.priority,
                        style: TextStyle(
                          color: _priorityColor(),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          IconButton(
            icon: const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 22),
            onPressed: onDone,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 22),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}