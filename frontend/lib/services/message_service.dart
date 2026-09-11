import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as contacts;
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/message_model.dart';

class MessageService {
  static final MessageService _instance = MessageService._();
  factory MessageService() => _instance;
  MessageService._();

  final SmsQuery _query = SmsQuery();
  bool _hasPermission = false;

  // Contact cache: normalized 10-digit number → display name
  // Loaded once per fetch session, cleared on next fetch.
  Map<String, String>? _contactCache;

  bool get hasPermission => _hasPermission;

  // ── SMS Permission ─────────────────────────────────────────────

  Future<bool> checkPermission() async {
    try {
      final status = await Permission.sms.status;
      _hasPermission = status.isGranted;
      return _hasPermission;
    } catch (e) {
      debugPrint('MessageService: checkPermission error: $e');
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final status = await Permission.sms.request();
      _hasPermission = status.isGranted;
      debugPrint('MessageService: SMS permission → ${status.name}');
      return _hasPermission;
    } catch (e) {
      debugPrint('MessageService: requestPermission error: $e');
      _hasPermission = false;
      return false;
    }
  }

  // ── Contact Cache ──────────────────────────────────────────────

  /// Normalize a phone number to its last 10 digits.
  ///
  /// Examples (India):
  ///   +918840590272  → 8840590272
  ///   +91 88405 90272 → 8840590272
  ///   08840590272   → 8840590272
  ///   8840590272    → 8840590272
  ///
  /// For non-Indian numbers with more or fewer digits,
  /// we still take the last 10 digits as the canonical key.
  /// This avoids false mismatches from country-code differences.
  String _normalize(String phone) {
    // Remove everything except digits
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return phone;
    // Take last 10 digits as canonical form
    return digits.length >= 10
        ? digits.substring(digits.length - 10)
        : digits;
  }

  /// Load all device contacts into a phone→name map.
  /// Requests READ_CONTACTS permission if not already granted.
  /// Returns an empty map gracefully on denial — SMS still works.
  /// Result is cached for the duration of the current fetch.
  Future<Map<String, String>> _getContactCache() async {
    if (_contactCache != null) return _contactCache!;

    final cache = <String, String>{};

    try {
      final status = await contacts.FlutterContacts.permissions.request(
        contacts.PermissionType.read,
      );

      if (status != contacts.PermissionStatus.granted) {
        debugPrint(
          'MessageService: contacts permission ${status.name} — '
          'sender names will show as phone numbers',
        );
        _contactCache = cache;
        return cache;
      }

      final contactList = await contacts.FlutterContacts.getAll(
        properties: {contacts.ContactProperty.phone},
      );

      for (final contact in contactList) {
        final name = (contact.displayName ?? '').trim();
        if (name.isEmpty) continue;

        for (final phone in contact.phones) {
          final raw = phone.number.trim();
          if (raw.isEmpty) continue;
          final key = _normalize(raw);
          if (key.isNotEmpty) {
            cache.putIfAbsent(key, () => name);
          }
        }
      }

      debugPrint(
        'MessageService: contact cache built — '
        '${cache.length} phone entries from '
        '${contactList.length} contacts',
      );
    } catch (e) {
      debugPrint('MessageService: _getContactCache error: $e');
    }

    _contactCache = cache;
    return cache;
  }

  /// Look up contact display name for a raw phone number.
  /// Returns null if no match found.
  String? _lookupContact(
    String rawPhone,
    Map<String, String> cache,
  ) {
    if (cache.isEmpty) return null;
    final key = _normalize(rawPhone);
    return cache[key];
  }

  // ── SMS Conversion ─────────────────────────────────────────────

  /// Convert a raw SmsMessage into a MessageModel.
  ///
  /// Sender resolution priority:
  ///   1. Contact name from device contacts (via cache lookup)
  ///   2. sms.sender from flutter_sms_inbox (sometimes resolved)
  ///   3. Raw phone number (sms.address) as final fallback
  ///
  /// IMPORTANT: contact name is resolved from the PHONE NUMBER only.
  /// Message body/snippet is NEVER used to determine sender identity.
  MessageModel _convert(
    SmsMessage sms,
    Map<String, String> contactCache,
  ) {
    final body = sms.body ?? '';

    // Truncate to 200 chars — never log or send full body
    final snippet =
        body.length > 200 ? '${body.substring(0, 200)}...' : body;

    final ts = sms.date != null
        ? DateTime.fromMillisecondsSinceEpoch(
            sms.date!.millisecondsSinceEpoch,
          ).toLocal()
        : DateTime.now();

    final rawAddress = sms.address ?? '';
    final rawSender = sms.sender ?? '';

    // Step 1: Try contact lookup by phone number
    String resolvedName = '';
    if (rawAddress.isNotEmpty) {
      resolvedName = _lookupContact(rawAddress, contactCache) ?? '';
      if (resolvedName.isNotEmpty) {
        debugPrint(
          'MessageService: resolved $rawAddress → $resolvedName',
        );
      }
    }

    // Step 2: If contact lookup failed, check sms.sender
    // (flutter_sms_inbox sometimes resolves this on some devices)
    if (resolvedName.isEmpty &&
        rawSender.isNotEmpty &&
        rawSender != rawAddress) {
      resolvedName = rawSender.trim();
      debugPrint(
        'MessageService: using sms.sender for $rawAddress '
        '→ $resolvedName',
      );
    }

    // Step 3: Fall back to raw phone number
    if (resolvedName.isEmpty) {
      resolvedName =
          rawAddress.isNotEmpty ? rawAddress : 'Unknown';
      debugPrint(
        'MessageService: no contact found for $rawAddress '
        '— using number as sender',
      );
    }

    return MessageModel(
      id: sms.id?.toString() ?? '',
      sender: resolvedName,   // display name or phone number
      address: rawAddress,    // always the original phone number
      body: body,
      snippet: snippet,
      timestamp: ts,
      isRead: sms.isRead ?? true,
      isIncoming: sms.kind == SmsMessageKind.received,
    );
  }

  // ── Core Fetcher ───────────────────────────────────────────────

  /// Fetch raw SMS from device inbox and convert with contact resolution.
  /// Contact cache is built once per call and reused for all messages.
  Future<List<MessageModel>> _fetch({int count = 30}) async {
    if (!_hasPermission) {
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('MessageService: no SMS permission');
        return [];
      }
    }

    try {
      final raw = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: count.clamp(1, 100),
      );

      debugPrint(
          'MessageService: ${raw.length} raw messages fetched');

      // Build contact cache ONCE for this entire fetch
      // Invalidate previous cache so we get fresh contacts
      _contactCache = null;
      final cache = await _getContactCache();

      return raw.map((sms) => _convert(sms, cache)).toList();
    } catch (e) {
      debugPrint('MessageService: _fetch error: $e');
      return [];
    }
  }

  // ── Public Query Methods (signatures unchanged) ────────────────

  Future<List<MessageModel>> fetchRecent({int count = 20}) =>
      _fetch(count: count);

  Future<List<MessageModel>> fetchToday() async {
    final all = await _fetch(count: 100);
    return all.where((m) => m.isToday).toList();
  }

  Future<List<MessageModel>> fetchUnread() async {
    final all = await _fetch(count: 100);
    return all.where((m) => !m.isRead).toList();
  }

  /// Search messages by sender name or phone number.
  ///
  /// After contact resolution, m.sender contains the display name
  /// ("Aditya Yadav"), so "aditya" now matches correctly.
  ///
  /// IMPORTANT: only matches against sender name and phone number.
  /// Never matches against message body to avoid false positives
  /// (e.g., a bank SMS mentioning "ADITYA YADAV" in the body).
  Future<List<MessageModel>> fetchFromSender(String sender) async {
    if (sender.trim().isEmpty) return fetchRecent();

    final all = await _fetch(count: 100);
    final senderLower = sender.toLowerCase().trim();

    final matched = all.where((m) {
      // Match resolved contact name
      final nameMatch =
          m.sender.toLowerCase().contains(senderLower);
      // Match raw phone number (if user typed a number)
      final addressMatch =
          m.address.toLowerCase().contains(senderLower);
      // NOTE: m.body / m.snippet deliberately excluded here
      return nameMatch || addressMatch;
    }).toList();

    debugPrint(
      'MessageService: fetchFromSender("$sender") '
      '→ ${matched.length} of ${all.length} messages',
    );
    return matched;
  }

  /// Search messages where snippet contains keyword.
  /// This searches MESSAGE CONTENT — separate from sender lookup.
  Future<List<MessageModel>> fetchByKeyword(
      String keyword) async {
    if (keyword.trim().isEmpty) return fetchRecent();

    final all = await _fetch(count: 100);
    final kw = keyword.toLowerCase().trim();

    return all.where((m) {
      // Keyword search searches sender name AND content
      return m.sender.toLowerCase().contains(kw) ||
          m.snippet.toLowerCase().contains(kw);
    }).toList();
  }

  // ── Serialization ──────────────────────────────────────────────

  List<Map<String, dynamic>> messagesToJson(
          List<MessageModel> messages) =>
      messages.map((m) => m.toJson()).toList();
}