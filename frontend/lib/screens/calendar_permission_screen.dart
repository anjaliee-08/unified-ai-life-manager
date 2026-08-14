import 'package:flutter/material.dart';
import '../services/calendar_service.dart';
import '../utils/app_theme.dart';

class CalendarPermissionScreen extends StatefulWidget {
  final VoidCallback onGranted;
  final VoidCallback onSkipped;

  const CalendarPermissionScreen({
    super.key,
    required this.onGranted,
    required this.onSkipped,
  });

  @override
  State<CalendarPermissionScreen> createState() =>
      _CalendarPermissionScreenState();
}

class _CalendarPermissionScreenState
    extends State<CalendarPermissionScreen> {
  bool _requesting = false;
  String? _error;

  Future<void> _requestPermission() async {
    setState(() {
      _requesting = true;
      _error = null;
    });

    final granted = await CalendarService().requestPermission();

    if (!mounted) return;
    setState(() => _requesting = false);

    if (granted) {
      widget.onGranted();
    } else {
      setState(() => _error =
          'Calendar access was denied. You can enable it later in Settings → Apps → UAILM → Permissions.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(Icons.calendar_month_rounded,
                    color: AppColors.accent, size: 32),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Calendar Access',
                  style: AppTextStyles.displayMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Allow UAILM to read your calendar so I can answer questions like:',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              ...[
                '"What do I have today?"',
                '"Any meetings tomorrow?"',
                '"What\'s on my schedule this week?"',
              ].map((q) => Padding(
                    padding: const EdgeInsets.only(
                        bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            color: AppColors.primary, size: 14),
                        const SizedBox(width: AppSpacing.sm),
                        Text(q,
                            style: AppTextStyles.bodyLarge
                                .copyWith(
                                    color: AppColors.primary)),
                      ],
                    ),
                  )),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: AppColors.surfaceLight,
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded,
                        color: AppColors.accent, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your calendar data stays private — it\'s only used to answer your questions.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  color: AppColors.error.withValues(alpha: 0.08),
                  child: Text(_error!,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.error)),
                ),
              ],
              const Spacer(),
              AppButton(
                label: 'Allow Calendar Access',
                icon: Icons.calendar_month_rounded,
                loading: _requesting,
                width: double.infinity,
                onTap: _requestPermission,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Skip for now',
                outlined: true,
                width: double.infinity,
                onTap: widget.onSkipped,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}