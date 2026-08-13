import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import '../utils/app_theme.dart';
import '../services/notification_service.dart';
import 'chat_screen.dart';
import 'extract_screen.dart';
import 'settings_screen.dart';

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
  Map<String, dynamic> _workload = {};
  List<dynamic> _focusRecs = [];
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
  if (!mounted) return;
  setState(() => _loading = true);
  try {
    final results = await Future.wait([
      _api.getUserTasks(widget.userId),
      _api.getAiStatus(),
      _api.getWorkloadAnalysis(widget.userId),      // ADD
      _api.getFocusRecommendations(widget.userId),  // ADD
    ]);
    final tasks = results[0] as List<dynamic>;
    final aiStatus = results[1] as Map<String, dynamic>;
    final workload = results[2] as Map<String, dynamic>;
    final focus = results[3] as Map<String, dynamic>;

    if (!mounted) return;
    setState(() {
      _tasks = tasks
          .map((t) => TaskModel.fromJson(t))
          .where((t) => t.status == 'pending')
          .toList();
      _aiOnline = aiStatus['status'] == 'online';
      _aiModel = aiStatus['model'] ?? '';
      _workload = workload;
      _focusRecs = (focus['recommendations'] as List?) ?? [];
      _loading = false;
    });
  } catch (_) {
    if (mounted) setState(() => _loading = false);
  }
}
  Future<void> _markDone(int taskId, String description) async {
    await _api.updateTaskStatus(taskId, 'done');
    await NotificationService().showNotification(
      id: taskId,
      title: '✅ Task Completed',
      body: description,
    );
    _loadData();
  }

  Future<void> _deleteTask(int taskId) async {
    await _api.deleteTask(taskId);
    _loadData();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _currentNavIndex == 0
          ? FloatingActionButton(
              onPressed: () => _showAddTaskSheet(context),
              backgroundColor: AppColors.primary,
              elevation: 0,
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 24),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_currentNavIndex) {
      case 1:
        return ChatScreen(
            userName: widget.userName, userId: widget.userId);
      case 2:
        return SettingsScreen(
            userId: widget.userId, userName: widget.userName);
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildAiCard()),
            SliverToBoxAdapter(child: _buildStatsRow()),
            SliverToBoxAdapter(child: _buildQuickActions()),
            SliverToBoxAdapter(child: _buildTasksHeader()),
            SliverToBoxAdapter(child: _buildWorkloadBanner()),
            SliverToBoxAdapter(child: _buildFocusCard()),
            _loading ? _buildSkeletonList() : _buildTaskList(),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting 👋',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.userName,
                  style: AppTextStyles.displayMedium,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: AppColors.divider, width: 0.5),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: AppColors.textSecondary, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UAILM AI',
                      style: AppTextStyles.titleMedium),
                  Text(
                    _tasks.isEmpty
                        ? 'No pending tasks · All clear!'
                        : '${_tasks.length} task${_tasks.length > 1 ? 's' : ''} need your attention',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
            AiStatusBadge(isOnline: _aiOnline, model: _aiModel),
          ],
        ),
      ),
    );
  }
  Widget _buildWorkloadBanner() {
  if (_workload.isEmpty) return const SizedBox.shrink();
  final level = _workload['level'] ?? 'normal';
  if (level == 'normal') return const SizedBox.shrink();

  final color = level == 'high' ? AppColors.high : AppColors.medium;
  final warnings = (_workload['warnings'] as List?) ?? [];
  if (warnings.isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
    child: AppCard(
      color: color.withValues(alpha: 0.07),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  level == 'high' ? 'High Workload' : 'Heads Up',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  warnings.first.toString(),
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
Widget _buildFocusCard() {
  if (_focusRecs.isEmpty) return const SizedBox.shrink();
  final top = _focusRecs.first as Map<String, dynamic>;
  final risk = (top['delay_risk'] as Map?) ?? {};
  final riskLevel = risk['risk'] ?? 'unknown';
  final riskColor = riskLevel == 'high'
      ? AppColors.high
      : riskLevel == 'medium'
          ? AppColors.medium
          : AppColors.low;
  final reasons = (top['reasons'] as List?) ?? [];

  return Padding(
    padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              Text('UAILM Recommends',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (riskLevel != 'unknown')
                AppChip(
                  label: '$riskLevel risk',
                  color: riskColor,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            top['description'] ?? '',
            style: AppTextStyles.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reasons.take(2).join(' · '),
              style: AppTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}
  Widget _buildStatsRow() {
    final high = _tasks.where((t) => t.priority == 'high').length;
    final medium = _tasks.where((t) => t.priority == 'medium').length;
    final low = _tasks.where((t) => t.priority == 'low').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Row(
        children: [
          _StatChip(label: 'Total', value: '${_tasks.length}',
              color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          _StatChip(label: 'High', value: '$high',
              color: AppColors.high),
          const SizedBox(width: AppSpacing.sm),
          _StatChip(label: 'Medium', value: '$medium',
              color: AppColors.medium),
          const SizedBox(width: AppSpacing.sm),
          _StatChip(label: 'Low', value: '$low',
              color: AppColors.low),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.auto_awesome_rounded,
              label: 'Extract Tasks',
              color: AppColors.primary,
              onTap: () async {
                await Navigator.push(
                  context,
                  _fadeRoute(
                      ExtractScreen(userId: widget.userId)),
                );
                _loadData();
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _QuickAction(
              icon: Icons.chat_bubble_rounded,
              label: 'Ask UAILM',
              color: AppColors.accent,
              onTap: () => setState(() => _currentNavIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
      child: SectionHeader(
        title: 'Pending Tasks',
        action: _tasks.isNotEmpty ? 'See all' : null,
      ),
    );
  }

  Widget _buildSkeletonList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) => Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoader(height: 14),
                const SizedBox(height: 8),
                SkeletonLoader(
                    width: MediaQuery.of(context).size.width * 0.4,
                    height: 10),
              ],
            ),
          ),
        ),
        childCount: 3,
      ),
    );
  }

  Widget _buildTaskList() {
    if (_tasks.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.task_alt_rounded,
          title: 'All clear! ✨',
          subtitle: 'No pending tasks.\nUse Extract Tasks to find tasks from text.',
          actionLabel: 'Extract Tasks',
          onAction: () async {
            await Navigator.push(
              context,
              _fadeRoute(ExtractScreen(userId: widget.userId)),
            );
            _loadData();
          },
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md),
          child: TaskCard(
            task: _tasks[i],
            onDone: () =>
                _markDone(_tasks[i].id, _tasks[i].description),
            onDelete: () => _deleteTask(_tasks[i].id),
          ),
        ),
        childCount: _tasks.length,
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (i) => setState(() => _currentNavIndex = i),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: AppTextStyles.caption
            .copyWith(color: AppColors.primary),
        unselectedLabelStyle: AppTextStyles.caption,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _showAddTaskSheet(BuildContext context) {
    final controller = TextEditingController();
    String priority = 'medium';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Add Task', style: AppTextStyles.titleLarge),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller,
              hint: 'What needs to be done?',
            ),
            const SizedBox(height: AppSpacing.md),
            StatefulBuilder(
              builder: (ctx, setModal) => Row(
                children: ['high', 'medium', 'low'].map((p) {
                  final selected = priority == p;
                  final color = AppTheme.priorityColor(p);
                  return GestureDetector(
                    onTap: () => setModal(() => priority = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: selected ? color : AppColors.divider,
                          width: selected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Text(
                        p[0].toUpperCase() + p.substring(1),
                        style: AppTextStyles.labelLarge.copyWith(
                          color: selected
                              ? color
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Add Task',
              width: double.infinity,
              onTap: () async {
                if (controller.text.isNotEmpty) {
                  await _api.createTask(
                      widget.userId, controller.text, priority);
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

// Helper widgets
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: color.withOpacity(0.15), width: 0.5),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTextStyles.titleLarge
                    .copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: 14, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border:
              Border.all(color: color.withOpacity(0.2), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: AppTextStyles.labelLarge
                    .copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

// Page transition helper
Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 200),
  );
}