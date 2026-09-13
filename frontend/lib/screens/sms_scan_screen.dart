import 'package:flutter/material.dart';
import '../services/message_service.dart';
import '../services/api_service.dart';
import '../models/sms_extraction_model.dart';
import '../widgets/sms_extraction_card.dart';
import '../utils/app_theme.dart';

class SmsScanScreen extends StatefulWidget {
  final int userId;

  const SmsScanScreen({super.key, required this.userId});

  @override
  State<SmsScanScreen> createState() => _SmsScanScreenState();
}

class _SmsScanScreenState extends State<SmsScanScreen> {
  final MessageService _sms = MessageService();
  final ApiService _api = ApiService();

  bool _scanning = false;
  bool _scanned = false;
  String _status = '';
  List<SmsExtractionModel> _extractions = [];

  // Track UI state per message_id
  final Set<String> _dismissedIds = {};
  final Set<String> _loadingIds = {};   // currently creating task
  final Set<String> _createdIds = {};   // task successfully created

  Future<void> _scan() async {
    final hasPermission = await _sms.checkPermission();
    if (!hasPermission) {
      final granted = await _sms.requestPermission();
      if (!granted) {
        setState(() => _status =
            'SMS permission not granted. '
            'Enable it in Settings → Messages.');
        return;
      }
    }

    setState(() {
      _scanning = true;
      _scanned = false;
      _extractions = [];
      _dismissedIds.clear();
      _loadingIds.clear();
      _createdIds.clear();
      _status = 'Fetching recent messages...';
    });

    try {
      final messages = await _sms.fetchRecent(count: 20);

      if (messages.isEmpty) {
        setState(() {
          _scanning = false;
          _scanned = true;
          _status = 'No messages found.';
        });
        return;
      }

      setState(() => _status =
          'Analyzing ${messages.length} messages with AI...');

      final msgJsons = _sms.messagesToJson(messages);
      final result = await _api.analyzeSmsMessages(
        userId: widget.userId,
        messages: msgJsons,
      );

      final rawExtractions = (result['extractions'] as List?) ?? [];
      final extractions = rawExtractions
          .map((e) => SmsExtractionModel.fromJson(
              e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanned = true;
        _extractions = extractions;
        _status = extractions.isEmpty
            ? 'No useful information detected in recent messages.'
            : '${extractions.length} message'
                '${extractions.length > 1 ? 's' : ''} analyzed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _status = 'Error: ${e.toString()}';
      });
    }
  }

  // ── Phase 5B: Task creation ───────────────────────────────────

  Future<void> _createTask(SmsExtractionModel extraction) async {
    final id = extraction.messageId;

    // Already loading or created — ignore repeat taps
    if (_loadingIds.contains(id) || _createdIds.contains(id)) {
      return;
    }

    // Show confirmation dialog before creating
    final confirmed = await _showConfirmDialog(extraction);
    if (confirmed != true) return;

    // Set loading state — disables button
    setState(() => _loadingIds.add(id));

    try {
      final result = await _api.confirmSmsTask(
        userId: widget.userId,
        extraction: extraction.toJson(),
      );

      if (!mounted) return;

      final status = result['status'] ?? 'error';

      if (status == 'created') {
        setState(() {
          _loadingIds.remove(id);
          _createdIds.add(id);
        });
        _showSnackBar(
          '✅ Task created: ${extraction.title ?? extraction.description ?? "SMS task"}',
          AppColors.success,
        );
      } else if (status == 'duplicate') {
        setState(() {
          _loadingIds.remove(id);
          _createdIds.add(id); // treat duplicate as already done
        });
        _showSnackBar(
          'ℹ️ Task already exists for this message.',
          AppColors.textSecondary,
        );
      } else {
        setState(() => _loadingIds.remove(id));
        _showSnackBar(
          result['message'] ?? 'Could not create task. Please try again.',
          AppColors.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingIds.remove(id));
      _showSnackBar(
        'Error: ${e.toString()}',
        AppColors.error,
      );
    }
  }

  Future<bool?> _showConfirmDialog(
      SmsExtractionModel extraction) {
    final title = extraction.title ??
        extraction.description ??
        'SMS task';
    final dateTime = extraction.dateTimeDisplay;
    final amount = extraction.amountDisplay;

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: const Text('Create Task?',
            style: AppTextStyles.titleLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.bodyLarge),
            if (dateTime != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppColors.primary, size: 14),
                  const SizedBox(width: 4),
                  Text(dateTime,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.primary)),
                ],
              ),
            ],
            if (amount != null) ...[
              const SizedBox(height: 4),
              Text(amount, style: AppTextStyles.bodySmall),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              'From: ${extraction.sender}',
              style: AppTextStyles.caption,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Create Task',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: AppTextStyles.bodyMedium
              .copyWith(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      margin: const EdgeInsets.all(AppSpacing.md),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Visible extractions ───────────────────────────────────────

  List<SmsExtractionModel> get _visible => _extractions
      .where((e) => !_dismissedIds.contains(e.messageId))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Message Intelligence'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child:
              Container(height: 0.5, color: AppColors.divider),
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
                    color: AppColors.primary
                        .withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'UAILM reads your messages and identifies '
                    'useful information. Create tasks only after '
                    'your confirmation.',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Scan button
          AppButton(
            label: _scanning ? 'Analyzing...' : 'Scan Messages',
            icon: Icons.message_rounded,
            loading: _scanning,
            width: double.infinity,
            onTap: _scanning ? null : _scan,
          ),

          // Status
          if (_status.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: AppColors.surfaceLight,
              child: Text(_status,
                  style: AppTextStyles.bodyMedium),
            ),
          ],

          // Empty state after all dismissed
          if (_scanned &&
              _visible.isEmpty &&
              _extractions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const EmptyState(
              icon: Icons.check_circle_rounded,
              title: 'All reviewed',
              subtitle: 'You\'ve actioned all detected messages.',
            ),
          ],

          // Results
          if (_visible.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title:
                  '${_visible.length} Detection'
                  '${_visible.length > 1 ? 's' : ''}',
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._visible.map((e) => Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppSpacing.sm),
                  child: SmsExtractionCard(
                    extraction: e,
                    // Phase 5B: pass task creation callback
                    // only for actionable non-OTP types
                    onCreateTask: (e.isActionable && !e.isOtp)
                        ? () => _createTask(e)
                        : null,
                    taskLoading:
                        _loadingIds.contains(e.messageId),
                    taskCreated:
                        _createdIds.contains(e.messageId),
                    onDismiss: () => setState(
                        () => _dismissedIds.add(e.messageId)),
                  ),
                )),
          ],

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}