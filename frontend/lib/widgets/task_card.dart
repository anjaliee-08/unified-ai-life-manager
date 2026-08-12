import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../utils/app_theme.dart';

class TaskCard extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onDone;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onDone,
    required this.onDelete,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _priorityColor => AppTheme.priorityColor(widget.task.priority);

  IconData get _sourceIcon {
    switch (widget.task.source) {
      case 'email':
        return Icons.email_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.edit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _controller.reverse(),
        onTapUp: (_) => _controller.forward(),
        onTapCancel: () => _controller.forward(),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Priority stripe
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: AppTheme.priorityGradient(widget.task.priority),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          // Priority dot
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _priorityColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _priorityColor.withOpacity(0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Task info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.task.description,
                                  style: AppTextStyles.bodyLarge,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(_sourceIcon,
                                        size: 10,
                                        color: AppColors.textMuted),
                                    const SizedBox(width: 3),
                                    Text(widget.task.source,
                                        style: AppTextStyles.caption),
                                    const SizedBox(width: 8),
                                    AppChip(
                                      label: widget.task.priority,
                                      color: _priorityColor,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Actions
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ActionButton(
                                icon: Icons.check_rounded,
                                color: AppColors.success,
                                onTap: widget.onDone,
                              ),
                              const SizedBox(height: 4),
                              _ActionButton(
                                icon: Icons.delete_outline_rounded,
                                color: AppColors.error,
                                onTap: widget.onDelete,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}