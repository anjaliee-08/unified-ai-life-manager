import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';

class ExtractScreen extends StatefulWidget {
  final int userId;
  const ExtractScreen({super.key, required this.userId});

  @override
  State<ExtractScreen> createState() => _ExtractScreenState();
}

class _ExtractScreenState extends State<ExtractScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _tasks = [];
  bool _loading = false;
  bool _extracted = false;
  String _error = '';

  Future<void> _extract() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _extracted = false;
      _error = '';
    });

    try {
      final result = await _api.extractTasks(_controller.text);
      final tasks = result['tasks'] ?? [];
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
        _extracted = true;
      });
      if (tasks.isNotEmpty) {
        await NotificationService()
            .notifyTasksExtracted(tasks.length);
        for (final t in tasks) {
          if (t['priority'] == 'high') {
            await NotificationService()
                .notifyHighPriorityTask(t['description']);
            break;
          }
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not connect to AI. Is Ollama running?';
      });
    }
  }

  Future<void> _saveTask(Map<String, dynamic> task) async {
    await _api.createTask(
      widget.userId,
      task['description'],
      task['priority'] ?? 'medium',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Task saved ✓',
            style: AppTextStyles.bodyMedium
                .copyWith(color: Colors.white)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(AppRadius.md)),
        margin: const EdgeInsets.all(AppSpacing.md),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Extract Tasks'),
        backgroundColor: AppColors.bg,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Info card
          AppCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Paste any text — email, message, note. UAILM will find the tasks.',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Text input
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border:
                  Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: TextField(
              controller: _controller,
              maxLines: 6,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                hintText:
                    'e.g. "Submit ML report by tomorrow 5pm. Team meeting Friday at 2pm..."',
                hintStyle: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.all(AppSpacing.md),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Extract button
          AppButton(
            label: _loading ? 'Extracting...' : 'Extract with AI',
            icon: Icons.auto_awesome_rounded,
            loading: _loading,
            width: double.infinity,
            onTap: _extract,
          ),

          // Error state
          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: AppColors.error.withOpacity(0.08),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(_error,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.error)),
                  ),
                ],
              ),
            ),
          ],

          // Results
          if (_extracted) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title: _tasks.isEmpty
                  ? 'No tasks found'
                  : '${_tasks.length} task${_tasks.length > 1 ? 's' : ''} found',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_tasks.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Nothing found',
                subtitle:
                    'No actionable tasks were detected in this text.',
              )
            else
              ..._tasks.map((task) => _buildExtractedTask(task)),
          ],
        ],
      ),
    );
  }

  Widget _buildExtractedTask(Map<String, dynamic> task) {
    final priority = task['priority'] ?? 'medium';
    final color = AppTheme.priorityColor(priority);

    return Container(
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
              Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: AppTheme.priorityGradient(priority),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(task['description'] ?? '',
                                style: AppTextStyles.bodyLarge),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                AppChip(
                                    label: priority, color: color),
                                if (task['deadline'] != null) ...[
                                  const SizedBox(width: 6),
                                  AppChip(
                                    label: task['deadline'],
                                    color: AppColors.textSecondary,
                                    icon: Icons.calendar_today_rounded,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _saveTask(task),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 4),
                        ),
                        child: Text('Save',
                            style: AppTextStyles.labelLarge
                                .copyWith(
                                    color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}