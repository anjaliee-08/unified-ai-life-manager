import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../models/calendar_event_model.dart';

class CalendarService {
  static final CalendarService _instance = CalendarService._();
  factory CalendarService() => _instance;
  CalendarService._();

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  bool _hasPermission = false;
  bool _tzInitialized = false;

  bool get hasPermission => _hasPermission;

  // ── Timezone ────────────────────────────────────────────────────

  void _ensureTzInitialized() {
  if (_tzInitialized) return;
  tzdata.initializeTimeZones();
  _tzInitialized = true;
  debugPrint('CalendarService: tzdata initialized');
}

/// Safely convert a TZDateTime (or DateTime) from device_calendar
/// into a plain local DateTime preserving wall-clock time.
///
/// The critical insight: TZDateTime stores an internal UTC epoch.
/// When device_calendar gives us an IST event at 12:30,
/// the TZDateTime's UTC epoch is 07:00 UTC.
///
/// Calling .toLocal() on a TZDateTime calls dart:core's toLocal()
/// which reads the OS timezone offset — this SHOULD work but
/// requires tzdata to be initialized first.
///
/// To be safe we read the TZDateTime's own .hour/.minute/.second
/// fields which are already expressed in its assigned timezone,
/// then construct a plain DateTime from those values directly.
DateTime _toLocalDateTime(dynamic dt) {
  if (dt == null) {
    debugPrint('CalendarService: _toLocalDateTime got null');
    return DateTime.now();
  }

  _ensureTzInitialized();

  if (dt is tz.TZDateTime) {
    // dt.hour/minute/second are already in dt.location's timezone.
    // Construct a plain unzoned DateTime from those values.
    // This avoids any risk of double-conversion.
    final result = DateTime(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
    );
    debugPrint(
      'CalendarService: TZDateTime(${dt.location.name}) '
      '${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute} '
      '→ local $result'
    );
    return result;
  }

  if (dt is DateTime) {
    // Plain DateTime — convert to local if UTC-flagged
    if (dt.isUtc) {
      final local = dt.toLocal();
      debugPrint(
        'CalendarService: UTC DateTime $dt → local $local'
      );
      return local;
    }
    debugPrint('CalendarService: local DateTime $dt (no conversion)');
    return dt;
  }

  debugPrint('CalendarService: unknown type ${dt.runtimeType}');
  return DateTime.now();
}

  // ── Permissions ─────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    try {
      final result = await _plugin.requestPermissions();
      _hasPermission = result.isSuccess && (result.data ?? false);
      return _hasPermission;
    } catch (e) {
      debugPrint('Calendar permission error: $e');
      _hasPermission = false;
      return false;
    }
  }

  Future<bool> checkPermission() async {
    try {
      final result = await _plugin.hasPermissions();
      _hasPermission = result.isSuccess && (result.data ?? false);
      return _hasPermission;
    } catch (e) {
      return false;
    }
  }

  // ── Core Event Fetcher ──────────────────────────────────────────

  /// Fetch events from ALL device calendars between [start] and [end].
  /// Both [start] and [end] must be LOCAL time (device timezone).
  /// Returns events sorted by start time.
  Future<List<CalendarEventModel>> _getEvents(
  DateTime start,
  DateTime end,
) async {
  if (!_hasPermission) {
    final granted = await requestPermission();
    if (!granted) return [];
  }

  // Always initialize tzdata before any TZDateTime operations
  _ensureTzInitialized();

  debugPrint(
    'CalendarService: _getEvents '
    '${start.year}-${start.month}-${start.day} '
    '→ ${end.year}-${end.month}-${end.day}'
  );

  try {
    final calendarsResult = await _plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess ||
        calendarsResult.data == null) {
      debugPrint('CalendarService: retrieveCalendars failed');
      return [];
    }

    debugPrint(
      'CalendarService: found '
      '${calendarsResult.data!.length} calendars'
    );

    final List<CalendarEventModel> events = [];

    for (final calendar in calendarsResult.data!) {
      if (calendar.id == null) continue;

      debugPrint(
        'CalendarService: reading calendar '
        '"${calendar.name}" id=${calendar.id}'
      );

      final result = await _plugin.retrieveEvents(
        calendar.id!,
        RetrieveEventsParams(startDate: start, endDate: end),
      );

      if (!result.isSuccess || result.data == null) {
        debugPrint(
          'CalendarService: retrieveEvents failed '
          'for calendar ${calendar.id}'
        );
        continue;
      }

      debugPrint(
        'CalendarService: got ${result.data!.length} '
        'raw events from "${calendar.name}"'
      );

      for (final event in result.data!) {
        if (event.eventId == null) continue;
        final title = (event.title ?? '').trim();
        if (title.isEmpty) continue;

        // Log raw values from plugin BEFORE conversion
        debugPrint(
          'CalendarService: raw event "$title" '
          'start=${event.start} (type=${event.start?.runtimeType}) '
          'end=${event.end} allDay=${event.allDay}'
        );

        final localStart = _toLocalDateTime(event.start);
        final localEnd = _toLocalDateTime(event.end);

        debugPrint(
          'CalendarService: converted "$title" '
          '→ ${localStart.year}-${localStart.month}-${localStart.day} '
          '${localStart.hour}:${localStart.minute.toString().padLeft(2,"0")}'
          '–${localEnd.hour}:${localEnd.minute.toString().padLeft(2,"0")}'
        );

        events.add(CalendarEventModel(
          id: event.eventId!,
          title: title,
          start: localStart,
          end: localEnd,
          location: event.location?.trim().isEmpty == true
              ? null
              : event.location,
          description:
              event.description?.trim().isEmpty == true
                  ? null
                  : event.description,
          isAllDay: event.allDay ?? false,
          calendarId: calendar.id!,
        ));
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));

    debugPrint(
      'CalendarService: returning ${events.length} events total'
    );

    return events;
  } catch (e, stack) {
    debugPrint('CalendarService: _getEvents error: $e');
    debugPrint('$stack');
    return [];
  }
}
  // ── Public Query Methods ────────────────────────────────────────

  /// Events strictly on today's date (local device date).
  Future<List<CalendarEventModel>> getTodayEvents() async {
    final now = DateTime.now();
    return getEventsForDate(now);
  }

  /// Events strictly on tomorrow's date.
  Future<List<CalendarEventModel>> getTomorrowEvents() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return getEventsForDate(tomorrow);
  }

  /// Events strictly on [date] (year/month/day match in local time).
  Future<List<CalendarEventModel>> getEventsForDate(DateTime date) async {
    // Build start and end of that calendar day in local time
    final dayStart = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final all = await _getEvents(dayStart, dayEnd);

    // Extra safety: filter by actual local date to eliminate
    // any timezone-shifted events that leaked through
    return all.where((e) {
      if (e.isAllDay) {
        // All-day events: match by date of start
        return e.start.year == date.year &&
            e.start.month == date.month &&
            e.start.day == date.day;
      }
      // Timed events: event starts on this date OR spans into it
      final eventDate = e.start;
      return eventDate.year == date.year &&
          eventDate.month == date.month &&
          eventDate.day == date.day;
    }).toList();
  }

  /// Events over the next [days] days starting from now.
  Future<List<CalendarEventModel>> getUpcomingEvents({
      int days = 7}) async {
    final now = DateTime.now();
    final end = DateTime(
        now.year, now.month, now.day + days, 23, 59, 59);
    return _getEvents(now, end);
  }

  /// Events for a specific date parsed from a string like "August 17"
  /// or "2026-08-17". Returns null if parsing fails.
  Future<List<CalendarEventModel>?> getEventsForDateString(
      String dateStr) async {
    final parsed = _parseDateFromString(dateStr);
    if (parsed == null) return null;
    return getEventsForDate(parsed);
  }

  /// Parse common date references from natural language.
  DateTime? _parseDateFromString(String input) {
    final lower = input.toLowerCase().trim();
    final now = DateTime.now();

    // Relative
    if (lower == 'today') return now;
    if (lower == 'tomorrow') {
      return now.add(const Duration(days: 1));
    }

    // ISO format: 2026-08-17
    final isoRegex = RegExp(r'(\d{4})-(\d{2})-(\d{2})');
    final isoMatch = isoRegex.firstMatch(input);
    if (isoMatch != null) {
      return DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    // "Month Day" format: "August 17", "Aug 17"
    final months = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9, 'sept': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };

    for (final entry in months.entries) {
      final pattern = RegExp(
        r'(' + entry.key + r')[a-z]*\s+(\d{1,2})',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(lower);
      if (match != null) {
        final day = int.tryParse(match.group(2) ?? '');
        if (day != null) {
          // Use current year, or next year if date already passed
          int year = now.year;
          final candidate = DateTime(year, entry.value, day);
          if (candidate.isBefore(
              DateTime(now.year, now.month, now.day))) {
            year = now.year + 1;
          }
          return DateTime(year, entry.value, day);
        }
      }
    }

    return null;
  }

  // ── Calendar Write Operations ───────────────────────────────────
Future<CalendarCreateResult> createEvent({
  required String title,
  required DateTime start,
  required DateTime end,
  String? location,
  String? description,
}) async {
  if (!_hasPermission) {
    final granted = await requestPermission();
    if (!granted) {
      return CalendarCreateResult(
        success: false,
        error: 'Calendar permission denied',
      );
    }
  }

  try {
    _ensureTzInitialized();

    final calendarsResult = await _plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess ||
        calendarsResult.data == null) {
      return CalendarCreateResult(
          success: false, error: 'No calendars found');
    }

    final allCalendars = calendarsResult.data!;

    // ── Debug: log every discovered calendar ──────────────────
    debugPrint('CalendarService: discovered '
        '${allCalendars.length} calendars:');
    for (int i = 0; i < allCalendars.length; i++) {
      final c = allCalendars[i];
      debugPrint(
        '  [${i + 1}] name="${c.name}" '
        'id=${c.id} '
        'accountName=${c.accountName} '
        'accountType=${c.accountType} '
        'isDefault=${c.isDefault} '
        'isReadOnly=${c.isReadOnly}',
      );
    }

    // ── Calendar selection ─────────────────────────────────────
    final writableCalendars = allCalendars
        .where((c) => !(c.isReadOnly ?? true) && c.id != null)
        .toList();

    if (writableCalendars.isEmpty) {
      return CalendarCreateResult(
          success: false, error: 'No writable calendar found');
    }

    // Priority 1: writable Google calendar marked as default
    Calendar? selected = writableCalendars.firstWhere(
      (c) =>
          (c.accountType ?? '').toLowerCase() == 'com.google' &&
          (c.isDefault ?? false),
      orElse: () => Calendar(),
    );
    // Priority 2: any writable Google calendar
    if (selected.id == null) {
      selected = writableCalendars.firstWhere(
        (c) =>
            (c.accountType ?? '').toLowerCase() == 'com.google',
        orElse: () => Calendar(),
      );
    }
    // Priority 3: first writable calendar
    if (selected.id == null) {
      selected = writableCalendars.first;
    }

    debugPrint(
      'CalendarService: selected calendar '
      '"${selected.name}" '
      'id=${selected.id} '
      'accountName=${selected.accountName} '
      'isDefault=${selected.isDefault}',
    );

    // ── BUG FIX: Correct TZDateTime construction ───────────────
    //
    // WRONG (previous code):
    //   tz.TZDateTime(tz.local, year, month, day, hour, minute)
    //   tz.local is UTC after tzdata.initializeTimeZones() alone,
    //   so this creates 17:00 UTC = 22:30 IST = wrong time.
    //
    // CORRECT:
    //   start is a plain local DateTime (isUtc=false, hour=17).
    //   start.toUtc() correctly converts using device timezone.
    //   TZDateTime.fromMillisecondsSinceEpoch(UTC, epoch)
    //   stores the right UTC epoch that device_calendar then
    //   displays as the correct local time.
    //
    // No timezone is hardcoded. The device's own dart:core
    // toUtc() conversion is used.

    debugPrint(
      'CalendarService: start=$start '
      'isUtc=${start.isUtc} '
      'iso=${start.toIso8601String()} '
      'utcMs=${start.toUtc().millisecondsSinceEpoch}',
    );
    debugPrint(
      'CalendarService: end=$end '
      'isUtc=${end.isUtc} '
      'iso=${end.toIso8601String()}',
    );

    final startTZ = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      start.toUtc().millisecondsSinceEpoch,
    );
    final endTZ = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      end.toUtc().millisecondsSinceEpoch,
    );

    debugPrint(
      'CalendarService: startTZ=$startTZ '
      'endTZ=$endTZ',
    );

    final event = Event(
      selected.id,
      title: title,
      start: startTZ,
      end: endTZ,
      location: location,
      description: description,
    );

    final result = await _plugin.createOrUpdateEvent(event);

    if (result != null && result.isSuccess) {
      debugPrint(
        'CalendarService: event created '
        'eventId=${result.data} '
        'calendarId=${selected.id}',
      );
      return CalendarCreateResult(
        success: true,
        eventId: result.data,
        calendarId: selected.id,
      );
    }

    return CalendarCreateResult(
      success: false,
      error: result?.errors.join(', ') ?? 'Unknown error',
    );
  } catch (e, stack) {
    debugPrint('CalendarService: createEvent error: $e\n$stack');
    return CalendarCreateResult(
        success: false, error: e.toString());
  }
}



  Future<bool> deleteEvent(
      String eventId, String calendarId) async {
    if (!_hasPermission) return false;
    try {
      final result = await _plugin.deleteEvent(calendarId, eventId);
      return result.isSuccess && (result.data ?? false);
    } catch (e) {
      debugPrint('Calendar delete error: $e');
      return false;
    }
  }

  // ── Serialization ───────────────────────────────────────────────

  List<Map<String, dynamic>> eventsToJson(
      List<CalendarEventModel> events) {
    return events.map((e) => e.toJson()).toList();
  }
}

class CalendarCreateResult {
  final bool success;
  final String? eventId;
  final String? calendarId;
  final String? error;

  CalendarCreateResult({
    required this.success,
    this.eventId,
    this.calendarId,
    this.error,
  });
}