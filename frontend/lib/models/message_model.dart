class MessageModel {
  final String id;
  final String sender;
  final String address; // phone number or contact name
  final String body;
  final String snippet; // truncated body for AI context
  final DateTime timestamp;
  final bool isRead;
  final bool isIncoming; // true = received, false = sent

  MessageModel({
    required this.id,
    required this.sender,
    required this.address,
    required this.body,
    required this.snippet,
    required this.timestamp,
    required this.isRead,
    required this.isIncoming,
  });

  bool get isToday {
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  String get timeString {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = timestamp.hour.toString().padLeft(2, '0');
      final m = timestamp.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'address': address,
        'snippet': snippet, // never send full body to backend
        'timestamp': timestamp.toIso8601String(),
        'is_read': isRead,
        'is_incoming': isIncoming,
        'is_today': isToday,
        'time_string': timeString,
      };
}