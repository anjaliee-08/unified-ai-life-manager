import 'package:flutter/material.dart';
import '../models/email_task_candidate.dart';
import '../utils/app_theme.dart';

class EmailTaskCard extends StatelessWidget {
  final EmailTaskCandidate candidate;
  final VoidCallback onAdd;
  final VoidCallback onIgnore;
  final bool loading;

  const EmailTaskCard({
    super.key,
    required this.candidate,
    required this.onAdd,
    required this.onIgnore,
    this.loading = false,
  });

  Color get _priorityColor =>
      AppTheme.priorityColor(candidate.priority);

  Color get _confidenceColor {
    switch (candidate.confidenceLabel) {
      case 'high':
        return AppColors.success;
      case 'medium':
        return AppColors.medium;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.email_rounded,
                  color: AppColors.primary,
                  size: 14,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Task detected from email',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      candidate.emailSender,
                      style: AppTextStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Confidence badge
              AppChip(
                label: '${(candidate.confidence * 100).toInt()}%'
                    ' ${candidate.confidenceLabel}',
                color: _confidenceColor,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: AppSpacing.md),

          // Task description
          Text(
            candidate.task,
            style: AppTextStyles.titleMedium,
          ),

          const SizedBox(height: AppSpacing.sm),

          // Subject line
          Text(
            candidate.emailSubject,
            style: AppTextStyles.bodySmall
                .copyWith(fontStyle: FontStyle.italic),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: AppSpacing.sm),

          // Deadline + Priority chips
          Row(
            children: [
              if (candidate.deadline != null) ...[
                AppChip(
                  label: candidate.deadlineDisplay,
                  color: candidate.deadline!
                          .isBefore(DateTime.now()
                              .add(const Duration(hours: 24)))
                      ? AppColors.high
                      : AppColors.textSecondary,
                  icon: Icons.schedule_rounded,
                ),
                const SizedBox(width: AppSpacing.sm),
              ] else ...[
                const AppChip(
                  label: 'No deadline',
                  color: AppColors.textMuted,
                  icon: Icons.schedule_rounded,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              AppChip(
                label: candidate.priority,
                color: _priorityColor,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : AppButton(
                        label: 'Add Task',
                        icon: Icons.add_rounded,
                        onTap: onAdd,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Ignore',
                  outlined: true,
                  color: AppColors.textSecondary,
                  onTap: onIgnore,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}