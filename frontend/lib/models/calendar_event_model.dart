import 'package:flutter/foundation.dart';
class CalendarEventModel {
  final String id;
  final String title;
  final DateTime start;   // Always local device time
  final DateTime end;     // Always local device time
  final String? location;
  final String? description;
  final bool isAllDay;
  final String calendarId;

  CalendarEventModel({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location,
    this.description,
    this.isAllDay = false,
    required this.calendarId,
  });

  int get durationMinutes => end.difference(start).inMinutes;

  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  bool get isToday {
    final now = DateTime.now();
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }

  String get timeString {
  if (isAllDay) return 'All day';
  String pad(int n) => n.toString().padLeft(2, '0');
  // start and end are plain local DateTimes at this point —
  // .hour/.minute are local wall-clock values, no conversion needed
  final s = '${pad(start.hour)}:${pad(start.minute)}'
      ' – ${pad(end.hour)}:${pad(end.minute)}';
  debugPrint(
    'CalendarEventModel: timeString for "$title" '
    'start.hour=${start.hour} start.minute=${start.minute} → $s'
  );
  return s;
}

  String get dateString {
    // Human-readable local date: "Aug 14"
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[start.month]} ${start.day}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        // CRITICAL: use local ISO format without UTC conversion
        // DateTime.toIso8601String() on a local DateTime includes
        // no Z suffix and preserves local time correctly.
        // If start is UTC-aware, toLocal() first.
        'start': _toLocalIso(start),
        'end': _toLocalIso(end),
        'location': location,
        'description': description,
        'is_all_day': isAllDay,
        'calendar_id': calendarId,
        'time_string': timeString,
        'date_string': dateString,
        'is_now': isNow,
        'duration_minutes': durationMinutes,
        // Include explicit date fields so backend can verify
        'date_year': start.year,
        'date_month': start.month,
        'date_day': start.day,
      };

  /// Convert to local ISO8601 without Z suffix.
  /// This preserves local wall-clock time.
  String _toLocalIso(DateTime dt) {
    // Ensure we have local time
    final local = dt.isUtc ? dt.toLocal() : dt;
    return local.toIso8601String();
  }

  factory CalendarEventModel.fromJson(Map<String, dynamic> json) {
    // Parse as local time — no UTC conversion
    DateTime parseLocal(String iso) {
      final dt = DateTime.parse(iso);
      return dt.isUtc ? dt.toLocal() : dt;
    }

    return CalendarEventModel(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      start: parseLocal(json['start']),
      end: parseLocal(json['end']),
      location: json['location'],
      description: json['description'],
      isAllDay: json['is_all_day'] ?? false,
      calendarId: json['calendar_id'] ?? '',
    );
  }
}