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
  final Set<String> _dismissedIds = {};

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
      _status = 'Fetching recent messages...';
    });

    try {
      // Fetch recent messages — exclude pure OTP spam by
      // fetching recent 20 (service already caps at 50)
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
                '${extractions.length > 1 ? 's' : ''}'
                ' analyzed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _status = 'Error: ${e.toString()}';
      });
    }
  }

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
                    color:
                        AppColors.primary.withValues(alpha: 0.12),
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
                    'useful information. Nothing is saved automatically.',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Scan button
          AppButton(
            label: _scanning
                ? 'Analyzing...'
                : 'Scan Messages',
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

          // Empty state after scan
          if (_scanned &&
              _visible.isEmpty &&
              _extractions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const EmptyState(
              icon: Icons.check_circle_rounded,
              title: 'All reviewed',
              subtitle: 'You\'ve dismissed all detections.',
            ),
          ],

          // Results
          if (_visible.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title: '${_visible.length} Detection'
                  '${_visible.length > 1 ? 's' : ''}',
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._visible.map(
              (e) => Padding(
                padding:
                    const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SmsExtractionCard(
                  extraction: e,
                  onDismiss: () => setState(
                      () => _dismissedIds.add(e.messageId)),
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