class EmailModel {
  final String id;
  final String threadId;
  final String sender;
  final String senderEmail;
  final String subject;
  final String snippet;
  final DateTime receivedAt;
  final bool isUnread;
  final List<String> labels;

  EmailModel({
    required this.id,
    required this.threadId,
    required this.sender,
    required this.senderEmail,
    required this.subject,
    required this.snippet,
    required this.receivedAt,
    required this.isUnread,
    required this.labels,
  });

  bool get isToday {
    final now = DateTime.now();
    return receivedAt.year == now.year &&
        receivedAt.month == now.month &&
        receivedAt.day == now.day;
  }

  bool get isImportant =>
      labels.contains('IMPORTANT') || labels.contains('STARRED');

  String get timeString {
    final now = DateTime.now();
    final diff = now.difference(receivedAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${receivedAt.day}/${receivedAt.month}/${receivedAt.year}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'thread_id': threadId,
        'sender': sender,
        'sender_email': senderEmail,
        'subject': subject.isEmpty ? '(no subject)' : subject,
        'snippet': snippet,
        'received_at': receivedAt.toIso8601String(),
        'is_unread': isUnread,
        'is_important': isImportant,
        'is_today': isToday,
        'time_string': timeString,
        'labels': labels,
      };

  factory EmailModel.fromGmailMessage(Map<String, dynamic> msg) {
    final headers = <String, String>{};
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};
    final headerList =
        payload['headers'] as List<dynamic>? ?? [];

    for (final h in headerList) {
      final name = (h['name'] as String? ?? '').toLowerCase();
      final value = h['value'] as String? ?? '';
      headers[name] = value;
    }

    // Parse sender "Name <email@gmail.com>" or "email@gmail.com"
    final fromRaw = headers['from'] ?? '';
    String senderName = fromRaw;
    String senderEmail = fromRaw;
    final emailMatch =
        RegExp(r'^(.*?)\s*<([^>]+)>').firstMatch(fromRaw);
    if (emailMatch != null) {
      senderName = emailMatch.group(1)?.trim() ?? fromRaw;
      senderEmail = emailMatch.group(2)?.trim() ?? fromRaw;
    } else if (fromRaw.contains('@')) {
      senderName = fromRaw.split('@').first;
      senderEmail = fromRaw;
    }

    // Parse date from internalDate (milliseconds since epoch)
    DateTime received = DateTime.now();
    final internalDate = msg['internalDate'];
    if (internalDate != null) {
      final ms = int.tryParse(internalDate.toString());
      if (ms != null) {
        received =
            DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      }
    }

    final labelIds =
        (msg['labelIds'] as List<dynamic>? ?? [])
            .map((l) => l.toString())
            .toList();

    return EmailModel(
      id: msg['id']?.toString() ?? '',
      threadId: msg['threadId']?.toString() ?? '',
      sender: senderName,
      senderEmail: senderEmail,
      subject: headers['subject'] ?? '',
      snippet: msg['snippet']?.toString() ?? '',
      receivedAt: received,
      isUnread: labelIds.contains('UNREAD'),
      labels: labelIds,
    );
  }
}