class EmailTaskCandidate {
  final bool isActionable;
  final String task;
  final String? deadlineText;
  final DateTime? deadline;
  final String priority;
  final double confidence;
  final String confidenceLabel;
  final String reason;
  final String emailId;
  final String emailSubject;
  final String emailSender;

  EmailTaskCandidate({
    required this.isActionable,
    required this.task,
    this.deadlineText,
    this.deadline,
    required this.priority,
    required this.confidence,
    required this.confidenceLabel,
    required this.reason,
    required this.emailId,
    required this.emailSubject,
    required this.emailSender,
  });

  factory EmailTaskCandidate.fromJson(Map<String, dynamic> json) {
    DateTime? deadline;
    if (json['deadline'] != null) {
      try {
        deadline = DateTime.parse(json['deadline']);
      } catch (_) {
        deadline = null;
      }
    }
    return EmailTaskCandidate(
      isActionable: json['is_actionable'] ?? false,
      task: json['task'] ?? '',
      deadlineText: json['deadline_text'],
      deadline: deadline,
      priority: json['priority'] ?? 'medium',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      confidenceLabel: json['confidence_label'] ?? 'low',
      reason: json['reason'] ?? '',
      emailId: json['email_id'] ?? '',
      emailSubject: json['email_subject'] ?? '',
      emailSender: json['email_sender'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'is_actionable': isActionable,
        'task': task,
        'deadline_text': deadlineText,
        'deadline': deadline?.toIso8601String(),
        'priority': priority,
        'confidence': confidence,
        'confidence_label': confidenceLabel,
        'reason': reason,
        'email_id': emailId,
        'email_subject': emailSubject,
        'email_sender': emailSender,
        'source': 'email',
      };

  String get deadlineDisplay {
    if (deadline == null) return 'No deadline';
    final now = DateTime.now();
    final diff = deadline!.difference(now);

    if (diff.inHours < 0) return 'Overdue';
    if (diff.inHours < 24) {
      return 'Today ${_formatTime(deadline!)}';
    }
    if (diff.inHours < 48) {
      return 'Tomorrow ${_formatTime(deadline!)}';
    }
    final days = diff.inDays;
    return 'In $days days · ${_formatTime(deadline!)}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }
}