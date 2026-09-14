import 'package:flutter/material.dart';
import '../models/sms_extraction_model.dart';
import '../utils/app_theme.dart';

class SmsExtractionCard extends StatelessWidget {
  final SmsExtractionModel extraction;
  final VoidCallback onDismiss;

  // Phase 5B — task creation
  final VoidCallback? onCreateTask;
  final bool taskLoading;
  final bool taskCreated;

  // Phase 5C — calendar event creation
  final VoidCallback? onAddToCalendar;
  final bool calendarLoading;
  final bool calendarAdded;

  const SmsExtractionCard({
    super.key,
    required this.extraction,
    required this.onDismiss,
    // Phase 5B
    this.onCreateTask,
    this.taskLoading = false,
    this.taskCreated = false,
    // Phase 5C
    this.onAddToCalendar,
    this.calendarLoading = false,
    this.calendarAdded = false,
  });

  Color get _typeColor {
    switch (extraction.type) {
      case 'TASK':
      case 'DEADLINE':
        return AppColors.high;
      case 'EVENT':
      case 'MEETING':
      case 'APPOINTMENT':
        return AppColors.primary;
      case 'REMINDER':
        return AppColors.medium;
      case 'BILL':
      case 'PAYMENT':
        return AppColors.warning;
      case 'TRANSACTION':
        return AppColors.accent;
      case 'DELIVERY':
        return Colors.teal;
      case 'OTP':
        return AppColors.textSecondary;
      default:
        return AppColors.textMuted;
    }
  }

  Color get _confidenceColor {
    switch (extraction.confidenceLabel) {
      case 'high':   return AppColors.success;
      case 'medium': return AppColors.medium;
      default:       return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showTaskButton =
        extraction.isActionableAndNotOtp && onCreateTask != null;
    final bool showCalendarButton =
        extraction.isCalendarEligible && onAddToCalendar != null;
    final bool showAnyButton = showTaskButton || showCalendarButton;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                      color: _typeColor.withValues(alpha: 0.3),
                      width: 0.5),
                ),
                child: Text(
                  extraction.typeLabel,
                  style: TextStyle(
                    color: _typeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              AppChip(
                label:
                    '${(extraction.confidence * 100).toInt()}%'
                    ' ${extraction.confidenceLabel}',
                color: _confidenceColor,
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!taskCreated || !calendarAdded)
                GestureDetector(
                  onTap: onDismiss,
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 16),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Sender ────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.message_rounded,
                  color: AppColors.textMuted, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'From: ${extraction.sender}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: AppSpacing.sm),

          // ── Content ───────────────────────────────────────────
          if (extraction.isOtp) ...[
            Text('One-time password detected',
                style: AppTextStyles.titleMedium),
            const SizedBox(height: 4),
            Text('OTP content is not displayed for security.',
                style: AppTextStyles.bodySmall),
          ] else ...[
            if (extraction.title != null)
              Text(extraction.title!,
                  style: AppTextStyles.titleMedium),
            if (extraction.description != null) ...[
              const SizedBox(height: 4),
              Text(extraction.description!,
                  style: AppTextStyles.bodyMedium),
            ],
            if (extraction.dateTimeDisplay != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppColors.primary, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    extraction.dateTimeDisplay!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ],
            if (extraction.amountDisplay != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    extraction.transactionType == 'credit'
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: extraction.transactionType == 'credit'
                        ? AppColors.success
                        : AppColors.error,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    extraction.amountDisplay!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: extraction.transactionType == 'credit'
                          ? AppColors.success
                          : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            if (extraction.originalSnippet.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  extraction.originalSnippet.length > 120
                      ? '${extraction.originalSnippet.substring(0, 120)}...'
                      : extraction.originalSnippet,
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ],

          // ── Action buttons ─────────────────────────────────────
          if (showAnyButton) ...[
            const SizedBox(height: AppSpacing.md),

            // Phase 5B: Create Task button
            if (showTaskButton) ...[
              if (taskCreated)
                _StatusRow(
                  icon: Icons.check_circle_rounded,
                  label: 'Task created ✓',
                  color: AppColors.success,
                )
              else
                AppButton(
                  label: taskLoading ? 'Creating...' : 'Create Task',
                  icon: taskLoading ? null : Icons.add_task_rounded,
                  loading: taskLoading,
                  width: double.infinity,
                  onTap: taskLoading ? null : onCreateTask,
                ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // Phase 5C: Add to Calendar button
            if (showCalendarButton) ...[
              if (calendarAdded)
                _StatusRow(
                  icon: Icons.event_available_rounded,
                  label: 'Added to Calendar ✓',
                  color: AppColors.accent,
                )
              else
                AppButton(
                  label: calendarLoading
                      ? 'Adding...'
                      : 'Add to Calendar',
                  icon: calendarLoading
                      ? null
                      : Icons.calendar_month_rounded,
                  loading: calendarLoading,
                  // Use outlined style to visually separate
                  // from the task button
                  outlined: showTaskButton && !taskCreated,
                  color: AppColors.accent,
                  width: double.infinity,
                  onTap: calendarLoading ? null : onAddToCalendar,
                ),
            ],

            // Dismiss when neither button applies or all done
            if (!showTaskButton && !showCalendarButton) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Dismiss',
                outlined: true,
                color: AppColors.textSecondary,
                width: double.infinity,
                onTap: onDismiss,
              ),
            ],
          ] else ...[
            // Non-actionable types
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ℹ️ Informational — no action taken',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label,
            style: AppTextStyles.labelLarge
                .copyWith(color: color)),
      ],
    );
  }
}