class SmsExtractionModel {
  final String messageId;
  final String sender;
  final String type;
  final String? title;
  final String? description;
  final String? date;
  final String? time;
  final String? deadline;
  final String? dueDate;
  final num? amount;
  final String? transactionType;
  final double confidence;
  final String confidenceLabel;
  final String originalSnippet;

  SmsExtractionModel({
    required this.messageId,
    required this.sender,
    required this.type,
    this.title,
    this.description,
    this.date,
    this.time,
    this.deadline,
    this.dueDate,
    this.amount,
    this.transactionType,
    required this.confidence,
    required this.confidenceLabel,
    required this.originalSnippet,
  });

  factory SmsExtractionModel.fromJson(Map<String, dynamic> json) {
    return SmsExtractionModel(
      messageId: json['message_id'] ?? '',
      sender: json['sender'] ?? 'Unknown',
      type: json['type'] ?? 'OTHER',
      title: json['title'],
      description: json['description'],
      date: json['date'],
      time: json['time'],
      deadline: json['deadline'],
      dueDate: json['due_date'],
      amount: json['amount'],
      transactionType: json['transaction_type'],
      confidence:
          (json['confidence'] as num?)?.toDouble() ?? 0.0,
      confidenceLabel: json['confidence_label'] ?? 'low',
      originalSnippet: json['original_snippet'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'sender': sender,
        'type': type,
        'title': title,
        'description': description,
        'date': date,
        'time': time,
        'deadline': deadline,
        'due_date': dueDate,
        'amount': amount,
        'transaction_type': transactionType,
        'confidence': confidence,
        'confidence_label': confidenceLabel,
        'original_snippet': originalSnippet,
      };

  // ── Type classification ──────────────────────────────────────

  /// Types where "Create Task" makes sense.
  bool get isActionable => [
        'TASK', 'EVENT', 'MEETING', 'APPOINTMENT', 'REMINDER',
        'DEADLINE', 'BILL', 'PAYMENT', 'DELIVERY',
      ].contains(type);

  bool get isOtp => type == 'OTP';

  /// Types where "Add to Calendar" makes sense.
  /// Requires a resolvable date — checked via resolveStartDateTime().
  bool get isCalendarEligible {
    // Only these types are meaningfully calendar events
    if (![
      'EVENT', 'MEETING', 'APPOINTMENT', 'REMINDER', 'DEADLINE'
    ].contains(type)) {
      return false;
    }
    // Must have at least a date to put on a calendar
    if (date == null && deadline == null && dueDate == null) {
      return false;
    }
    // Must resolve to an actual DateTime
    return resolveStartDateTime() != null;
  }

  // ── Date/time resolution ─────────────────────────────────────

  /// Resolve the date field to a local DateTime.
  ///
  /// Handles relative dates: "tomorrow", "Monday", "next Friday"
  /// and month-day format: "20 September", "September 20"
  /// Returns null if resolution fails — never invents a date.
  DateTime? _resolveDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;

    final now = DateTime.now();
    final lower = dateStr.toLowerCase().trim();

    // Relative keywords
    if (lower.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    }
    if (lower.contains('tomorrow')) {
      final t = now.add(const Duration(days: 1));
      return DateTime(t.year, t.month, t.day);
    }
    if (lower.contains('day after tomorrow')) {
      final t = now.add(const Duration(days: 2));
      return DateTime(t.year, t.month, t.day);
    }
    if (lower.contains('next week')) {
      final t = now.add(const Duration(days: 7));
      return DateTime(t.year, t.month, t.day);
    }

    // Weekday names
    const weekdays = {
      'monday': 1, 'tuesday': 2, 'wednesday': 3,
      'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
    };
    for (final entry in weekdays.entries) {
      if (lower.contains(entry.key)) {
        int daysAhead = entry.value - now.weekday;
        if (daysAhead <= 0) daysAhead += 7;
        if (lower.contains('next')) daysAhead += 7;
        final t = now.add(Duration(days: daysAhead));
        return DateTime(t.year, t.month, t.day);
      }
    }

    // Month-day: "20 September", "September 20", "Sep 20"
    const months = {
      'jan': 1, 'january': 1,
      'feb': 2, 'february': 2,
      'mar': 3, 'march': 3,
      'apr': 4, 'april': 4,
      'may': 5,
      'jun': 6, 'june': 6,
      'jul': 7, 'july': 7,
      'aug': 8, 'august': 8,
      'sep': 9, 'september': 9,
      'oct': 10, 'october': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12,
    };

    for (final entry in months.entries) {
      if (lower.contains(entry.key)) {
        // Extract day number adjacent to month name
        final pattern = RegExp(r'(\d{1,2})');
        final match = pattern.firstMatch(lower);
        if (match != null) {
          final day = int.tryParse(match.group(1) ?? '');
          if (day != null && day >= 1 && day <= 31) {
            int year = now.year;
            final candidate = DateTime(year, entry.value, day);
            // If date is in the past, assume next year
            if (candidate.isBefore(
                now.subtract(const Duration(days: 1)))) {
              year++;
            }
            return DateTime(year, entry.value, day);
          }
        }
      }
    }

    // ISO format: "2026-08-25"
    try {
      final iso = DateTime.parse(dateStr);
      return DateTime(iso.year, iso.month, iso.day);
    } catch (_) {}

    return null; // Cannot resolve — never invent
  }

  /// Resolve the time field into hour and minute.
  /// Returns null if resolution fails.
  ({int hour, int minute})? _resolveTime(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;

    final lower = timeStr.toLowerCase().trim();

    // 12-hour with AM/PM: "5 PM", "5:30 PM", "11:59 PM"
    final ampm = RegExp(
        r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
        caseSensitive: false);
    final ampmMatch = ampm.firstMatch(lower);
    if (ampmMatch != null) {
      int h = int.parse(ampmMatch.group(1)!);
      final m = int.tryParse(ampmMatch.group(2) ?? '0') ?? 0;
      final period = ampmMatch.group(3)!.toLowerCase();
      if (period == 'pm' && h != 12) h += 12;
      if (period == 'am' && h == 12) h = 0;
      return (hour: h, minute: m);
    }

    // 24-hour: "17:00", "09:30"
    final h24 = RegExp(r'\b(\d{1,2}):(\d{2})\b');
    final h24Match = h24.firstMatch(lower);
    if (h24Match != null) {
      final h = int.tryParse(h24Match.group(1)!);
      final m = int.tryParse(h24Match.group(2)!);
      if (h != null && m != null && h < 24 && m < 60) {
        return (hour: h, minute: m);
      }
    }

    return null;
  }

  /// Resolve extraction date+time → event start DateTime.
  /// Returns null if no reliable date can be determined.
  /// Never invents a date or time.
  DateTime? resolveStartDateTime() {
    // Try date field first, then deadline/dueDate
    final dateStr = date ?? deadline ?? dueDate;
    final resolvedDate = _resolveDate(dateStr);
    if (resolvedDate == null) return null;

    final resolvedTime = _resolveTime(time);

    return DateTime(
      resolvedDate.year,
      resolvedDate.month,
      resolvedDate.day,
      resolvedTime?.hour ?? 9,    // default 9 AM if no time
      resolvedTime?.minute ?? 0,
    );
  }

  /// Resolve event end DateTime.
  /// Default duration: 1 hour after start.
  /// Returns null if start cannot be resolved.
  DateTime? resolveEndDateTime() {
    final start = resolveStartDateTime();
    if (start == null) return null;
    return start.add(const Duration(hours: 1));
  }

  // ── Display helpers ──────────────────────────────────────────

  String get typeLabel {
    switch (type) {
      case 'TASK':        return '📋 Task';
      case 'EVENT':       return '📅 Event';
      case 'MEETING':     return '🤝 Meeting';
      case 'APPOINTMENT': return '🏥 Appointment';
      case 'REMINDER':    return '🔔 Reminder';
      case 'DEADLINE':    return '⏰ Deadline';
      case 'BILL':        return '🧾 Bill';
      case 'PAYMENT':     return '💳 Payment';
      case 'TRANSACTION': return '💰 Transaction';
      case 'DELIVERY':    return '📦 Delivery';
      case 'OTP':         return '🔐 OTP';
      case 'INFORMATION': return 'ℹ️ Information';
      default:            return '📱 Message';
    }
  }

  bool get isActionableAndNotOtp =>
      isActionable && !isOtp;

  String? get dateTimeDisplay {
    final parts = <String>[];
    if (date != null) parts.add(date!);
    if (time != null) parts.add(time!);
    if (deadline != null && date == null) {
      parts.add('Deadline: $deadline');
    }
    if (dueDate != null && date == null && deadline == null) {
      parts.add('Due: $dueDate');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get amountDisplay {
    if (amount == null) return null;
    final prefix = transactionType == 'credit'
        ? '+ ₹'
        : transactionType == 'debit'
            ? '- ₹'
            : '₹';
    return '$prefix$amount';
  }
}