import 'package:flutter/material.dart';
import '../services/message_service.dart';
import '../services/api_service.dart';
import '../services/calendar_service.dart';
import '../models/sms_extraction_model.dart';
import '../models/calendar_event_model.dart';
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
  final CalendarService _calendar = CalendarService();

  bool _scanning = false;
  bool _scanned = false;
  String _status = '';
  List<SmsExtractionModel> _extractions = [];

  // Per-message state tracking (keyed by messageId)
  final Set<String> _dismissedIds = {};
  // Phase 5B — task
  final Set<String> _taskLoadingIds = {};
  final Set<String> _taskCreatedIds = {};
  // Phase 5C — calendar
  final Set<String> _calLoadingIds = {};
  final Set<String> _calAddedIds = {};

  // ── Scan ─────────────────────────────────────────────────────

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
      _taskLoadingIds.clear();
      _taskCreatedIds.clear();
      _calLoadingIds.clear();
      _calAddedIds.clear();
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

  // ── Phase 5B: Create Task ─────────────────────────────────────

  Future<void> _createTask(SmsExtractionModel extraction) async {
    final id = extraction.messageId;
    if (_taskLoadingIds.contains(id) ||
        _taskCreatedIds.contains(id)) return;

    final confirmed = await _showConfirmTaskDialog(extraction);
    if (confirmed != true) return;

    setState(() => _taskLoadingIds.add(id));

    try {
      final result = await _api.confirmSmsTask(
        userId: widget.userId,
        extraction: extraction.toJson(),
      );

      if (!mounted) return;
      final status = result['status'] ?? 'error';

      if (status == 'created' || status == 'duplicate') {
        setState(() {
          _taskLoadingIds.remove(id);
          _taskCreatedIds.add(id);
        });
        _showSnackBar(
          status == 'created'
              ? '✅ Task created: ${extraction.title ?? 'SMS task'}'
              : 'ℹ️ Task already exists for this message.',
          status == 'created'
              ? AppColors.success
              : AppColors.textSecondary,
        );
      } else {
        setState(() => _taskLoadingIds.remove(id));
        _showSnackBar(
          result['message'] ?? 'Could not create task.',
          AppColors.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _taskLoadingIds.remove(id));
      _showSnackBar('Error: ${e.toString()}', AppColors.error);
    }
  }

  // ── Phase 5C: Add to Calendar ─────────────────────────────────

  Future<void> _addToCalendar(SmsExtractionModel extraction) async {
  final id = extraction.messageId;
  if (_calLoadingIds.contains(id) || _calAddedIds.contains(id)) {
    return;
  }

  // Resolve date+time — returns null if cannot be determined
  final start = extraction.resolveStartDateTime();
  final end = extraction.resolveEndDateTime();

  if (start == null || end == null) {
    _showSnackBar(
      'Could not determine the event date/time from this message. '
      'Please add it to your calendar manually.',
      AppColors.warning,
    );
    return;
  }

  // ── Debug: log what we resolved ──────────────────────────────
  debugPrint(
    'SmsScanScreen: resolved start=$start '
    'isUtc=${start.isUtc} '
    'end=$end',
  );

  // ── Conflict detection ────────────────────────────────────────
  // Fetch existing events on the target date using the
  // existing CalendarService — no new infrastructure needed.
  final bool hasCalPermission = await _calendar.checkPermission();
  if (!hasCalPermission) {
    final granted = await _calendar.requestPermission();
    if (!granted) {
      _showSnackBar(
        'Calendar permission not granted. '
        'Enable it in Settings.',
        AppColors.error,
      );
      return;
    }
  }

  List<CalendarEventModel> existingEvents = [];
  try {
    existingEvents = await _calendar.getEventsForDate(start);
    debugPrint(
      'SmsScanScreen: found ${existingEvents.length} '
      'existing events on ${start.year}-${start.month}-${start.day}',
    );
  } catch (e) {
    debugPrint('SmsScanScreen: could not fetch existing events: $e');
    // Non-fatal — proceed without conflict check
  }

  // Find overlapping events using strict interval logic:
  //   requestedStart < existingEnd AND requestedEnd > existingStart
  // Touching boundaries (e.g. 5-6 PM and 6-7 PM) are NOT conflicts.
  final conflicts = existingEvents.where((ev) {
    return start.isBefore(ev.end) && end.isAfter(ev.start);
  }).toList();

  debugPrint(
    'SmsScanScreen: ${conflicts.length} conflict(s) found',
  );

  // ── Ask user how to proceed ───────────────────────────────────
  bool addAnyway = false;

  if (conflicts.isNotEmpty) {
    // Show conflict dialog — user must explicitly choose
    final choice = await _showConflictDialog(
      extraction: extraction,
      start: start,
      end: end,
      conflicts: conflicts,
    );

    if (choice == null || choice == 'cancel') {
      // User cancelled — do NOT create event
      debugPrint('SmsScanScreen: user cancelled after conflict');
      return;
    }
    addAnyway = choice == 'add_anyway';
    if (!addAnyway) return;
  } else {
    // No conflict — show normal confirmation dialog
    final confirmed = await _showCalendarConfirmDialog(
      extraction: extraction,
      start: start,
      end: end,
    );
    if (confirmed != true) return;
  }

  // ── Create the event ──────────────────────────────────────────
  setState(() => _calLoadingIds.add(id));

  try {
    final result = await _calendar.createEvent(
      title: extraction.title ??
          extraction.description ??
          'Event from SMS',
      start: start,
      end: end,
      description:
          'Added by UAILM from SMS sent by '
          '${extraction.sender}.\n\n'
          '${extraction.originalSnippet}',
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _calLoadingIds.remove(id);
        _calAddedIds.add(id);
      });
      _showSnackBar(
        '📅 Added to Calendar: '
        '${extraction.title ?? 'Event'}',
        AppColors.accent,
      );
    } else {
      setState(() => _calLoadingIds.remove(id));
      _showSnackBar(
        'Calendar error: ${result.error ?? 'Unknown error'}',
        AppColors.error,
      );
    }
  } catch (e) {
    if (!mounted) return;
    setState(() => _calLoadingIds.remove(id));
    _showSnackBar(
      'Could not add to calendar: ${e.toString()}',
      AppColors.error,
    );
  }
}


  // ── Dialogs ───────────────────────────────────────────────────

  Future<bool?> _showConfirmTaskDialog(
      SmsExtractionModel extraction) {
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
            Text(
              extraction.title ??
                  extraction.description ??
                  'SMS task',
              style: AppTextStyles.bodyLarge,
            ),
            if (extraction.dateTimeDisplay != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                const Icon(Icons.schedule_rounded,
                    color: AppColors.primary, size: 14),
                const SizedBox(width: 4),
                Text(extraction.dateTimeDisplay!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.primary)),
              ]),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text('From: ${extraction.sender}',
                style: AppTextStyles.caption),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.textSecondary)),
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


/// Normal confirmation — shown when no conflict detected.
Future<bool?> _showCalendarConfirmDialog({
  required SmsExtractionModel extraction,
  required DateTime start,
  required DateTime end,
}) {
  final title = extraction.title ??
      extraction.description ?? 'Event';
  final dateLabel =
      '${start.day}/${start.month}/${start.year}';
  final timeLabel =
      '${_pad(start.hour)}:${_pad(start.minute)} – '
      '${_pad(end.hour)}:${_pad(end.minute)}';

  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: const Text('Add to Calendar?',
          style: AppTextStyles.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.bodyLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            const Icon(Icons.calendar_month_rounded,
                color: AppColors.accent, size: 14),
            const SizedBox(width: 4),
            Text(dateLabel,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.accent)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.schedule_rounded,
                color: AppColors.accent, size: 14),
            const SizedBox(width: 4),
            Text(timeLabel,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.accent)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text('From: ${extraction.sender}',
              style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Text('Duration: 1 hour',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted)),
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
          child: Text('Add to Calendar',
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.accent)),
        ),
      ],
    ),
  );
}

/// Conflict dialog — shown when overlap detected.
/// Returns: 'cancel' | 'add_anyway' | null (dismissed)
Future<String?> _showConflictDialog({
  required SmsExtractionModel extraction,
  required DateTime start,
  required DateTime end,
  required List<CalendarEventModel> conflicts,
}) {
  final title = extraction.title ??
      extraction.description ?? 'Event';
  final timeLabel =
      '${_pad(start.hour)}:${_pad(start.minute)} – '
      '${_pad(end.hour)}:${_pad(end.minute)}';

  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: const Text('Schedule Conflict',
          style: AppTextStyles.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Requested event
          Row(children: [
            const Icon(Icons.event_rounded,
                color: AppColors.primary, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$title · $timeLabel',
                style: AppTextStyles.bodyLarge,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          // Conflicting events
          Text('⚠️ Conflicts with:',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.warning)),
          const SizedBox(height: AppSpacing.sm),
          ...conflicts.map((ev) => Padding(
                padding: const EdgeInsets.only(
                    bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.warning, size: 13),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${ev.title}\n${ev.timeString}',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'What would you like to do?',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, 'cancel'),
          child: Text('Cancel',
              style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, 'add_anyway'),
          child: Text('Add Anyway',
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.warning)),
        ),
      ],
    ),
  );
}

/// Zero-pad a number to 2 digits.
String _pad(int n) => n.toString().padLeft(2, '0');
  // ── Helpers ───────────────────────────────────────────────────

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

  List<SmsExtractionModel> get _visible => _extractions
      .where((e) => !_dismissedIds.contains(e.messageId))
      .toList();

  // ── Build ─────────────────────────────────────────────────────

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
                  child: const Icon(Icons.psychology_rounded,
                      color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'UAILM reads your messages and identifies '
                    'useful information. Create tasks or calendar '
                    'events only after your confirmation.',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          AppButton(
            label: _scanning ? 'Analyzing...' : 'Scan Messages',
            icon: Icons.message_rounded,
            loading: _scanning,
            width: double.infinity,
            onTap: _scanning ? null : _scan,
          ),

          if (_status.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: AppColors.surfaceLight,
              child: Text(_status,
                  style: AppTextStyles.bodyMedium),
            ),
          ],

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

          if (_visible.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title: '${_visible.length} Detection'
                  '${_visible.length > 1 ? 's' : ''}',
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._visible.map((e) => Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppSpacing.sm),
                  child: SmsExtractionCard(
                    extraction: e,
                    // Phase 5B
                    onCreateTask: e.isActionableAndNotOtp
                        ? () => _createTask(e)
                        : null,
                    taskLoading:
                        _taskLoadingIds.contains(e.messageId),
                    taskCreated:
                        _taskCreatedIds.contains(e.messageId),
                    // Phase 5C
                    onAddToCalendar: e.isCalendarEligible
                        ? () => _addToCalendar(e)
                        : null,
                    calendarLoading:
                        _calLoadingIds.contains(e.messageId),
                    calendarAdded:
                        _calAddedIds.contains(e.messageId),
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