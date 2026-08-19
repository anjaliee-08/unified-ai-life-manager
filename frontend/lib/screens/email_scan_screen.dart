import 'package:flutter/material.dart';
import '../services/email_service.dart';
import '../services/api_service.dart';
import '../models/email_task_candidate.dart';
import '../widgets/email_task_card.dart';
import '../utils/app_theme.dart';

class EmailScanScreen extends StatefulWidget {
  final int userId;

  const EmailScanScreen({super.key, required this.userId});

  @override
  State<EmailScanScreen> createState() => _EmailScanScreenState();
}

class _EmailScanScreenState extends State<EmailScanScreen> {
  final EmailService _email = EmailService();
  final ApiService _api = ApiService();

  bool _scanning = false;
  bool _scanned = false;
  String _status = '';
  List<EmailTaskCandidate> _candidates = [];

  // Track which candidates are being saved or have been actioned
  final Set<String> _loadingIds = {};
  final Set<String> _ignoredIds = {};
  final Set<String> _addedIds = {};

  Future<void> _scanEmails() async {
    final connected = await _email.checkSignedIn();
    if (!connected) {
      if (mounted) {
        setState(() => _status =
            'Gmail not connected. Go to Settings → Gmail to connect.');
      }
      return;
    }

    setState(() {
      _scanning = true;
      _scanned = false;
      _candidates = [];
      _status = 'Fetching recent emails...';
    });

    try {
      // Fetch recent unread + important emails
      final unread = await _email.fetchUnreadEmails();
      final important = await _email.fetchImportantEmails();

      // Merge and deduplicate by email ID
      final seen = <String>{};
      final combined = [...unread, ...important]
          .where((e) => seen.add(e.id))
          .toList();

      if (combined.isEmpty) {
        setState(() {
          _scanning = false;
          _scanned = true;
          _status = 'No recent emails to analyze.';
        });
        return;
      }

      setState(() => _status =
          'Analyzing ${combined.length} emails with AI...');

      final emailJsons = _email.emailsToJson(combined);
      final result = await _api.analyzeEmailsForTasks(
        userId: widget.userId,
        emails: emailJsons,
      );

      final rawCandidates =
          (result['candidates'] as List?) ?? [];
      final skipped = result['skipped_duplicates'] ?? 0;

      final candidates = rawCandidates
          .map((c) => EmailTaskCandidate.fromJson(
              c as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanned = true;
        _candidates = candidates;
        _status = candidates.isEmpty
            ? 'No actionable tasks found in your recent emails'
                '${skipped > 0 ? ' ($skipped already added)' : ''}.'
            : '${candidates.length} task candidate'
                '${candidates.length > 1 ? 's' : ''} found'
                '${skipped > 0 ? ' · $skipped already added' : ''}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _status = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _addTask(EmailTaskCandidate candidate) async {
    setState(() => _loadingIds.add(candidate.emailId));

    try {
      final result = await _api.confirmEmailTask(
        userId: widget.userId,
        candidate: candidate.toJson(),
      );

      if (!mounted) return;

      if (result['status'] == 'created' ||
          result['status'] == 'duplicate') {
        setState(() {
          _addedIds.add(candidate.emailId);
          _loadingIds.remove(candidate.emailId);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            result['status'] == 'created'
                ? '✅ Task added: ${candidate.task}'
                : 'ℹ️ Task already exists',
          ),
          backgroundColor: result['status'] == 'created'
              ? AppColors.success
              : AppColors.textSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          margin: const EdgeInsets.all(AppSpacing.md),
          duration: const Duration(seconds: 2),
        ));
      } else {
        setState(() => _loadingIds.remove(candidate.emailId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              result['message'] ?? 'Could not add task'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.md),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingIds.remove(candidate.emailId));
    }
  }

  void _ignore(EmailTaskCandidate candidate) {
    setState(() => _ignoredIds.add(candidate.emailId));
  }

  List<EmailTaskCandidate> get _visibleCandidates =>
      _candidates
          .where((c) =>
              !_ignoredIds.contains(c.emailId) &&
              !_addedIds.contains(c.emailId))
          .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Email Task Scan'),
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
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'UAILM scans your recent emails and '
                    'suggests tasks. You confirm before anything '
                    'is added.',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Scan button
          AppButton(
            label: _scanning ? 'Scanning...' : 'Scan Emails for Tasks',
            icon: Icons.email_rounded,
            loading: _scanning,
            width: double.infinity,
            onTap: _scanning ? null : _scanEmails,
          ),

          // Status message
          if (_status.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: AppColors.surfaceLight,
              child: Text(_status,
                  style: AppTextStyles.bodyMedium),
            ),
          ],

          // Candidates
          if (_scanned && _visibleCandidates.isEmpty &&
              _candidates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            EmptyState(
              icon: Icons.check_circle_rounded,
              title: 'All done!',
              subtitle:
                  'You\'ve actioned all detected email tasks.',
            ),
          ],

          if (_visibleCandidates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title:
                  '${_visibleCandidates.length} Task'
                  '${_visibleCandidates.length > 1 ? 's' : ''} '
                  'Detected',
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._visibleCandidates.map(
              (c) => Padding(
                padding:
                    const EdgeInsets.only(bottom: AppSpacing.sm),
                child: EmailTaskCard(
                  candidate: c,
                  loading: _loadingIds.contains(c.emailId),
                  onAdd: () => _addTask(c),
                  onIgnore: () => _ignore(c),
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}