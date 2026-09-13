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

  // Whether this type is worth showing prominently
  bool get isActionable {
    return [
      'TASK', 'EVENT', 'MEETING', 'APPOINTMENT',
      'REMINDER', 'DEADLINE', 'BILL', 'PAYMENT', 'DELIVERY',
    ].contains(type);
  }

  String? get dateTimeDisplay {
    final parts = <String>[];
    if (date != null) parts.add(date!);
    if (time != null) parts.add(time!);
    if (deadline != null) parts.add('Deadline: $deadline');
    if (dueDate != null) parts.add('Due: $dueDate');
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

  // OTP: never display the snippet (privacy)
  bool get isOtp => type == 'OTP';
}