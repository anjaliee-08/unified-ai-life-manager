import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_theme.dart';
import '../services/calendar_service.dart';
import '../models/calendar_event_model.dart';
import '../services/email_service.dart';
import '../models/email_model.dart';
import '../services/message_service.dart';
import '../models/message_model.dart';
class ChatMessage {
  final String text;
  final bool isUser;
  final bool isConfirmation;
  final Map<String, dynamic>? pendingAction;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isConfirmation = false,
    this.pendingAction,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

class ChatScreen extends StatefulWidget {
  final String userName;
  final int userId;

  const ChatScreen({
    super.key,
    required this.userName,
    required this.userId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  final CalendarService _calendar = CalendarService();
  bool _calendarEnabled = false;
  final EmailService _email = EmailService();
  bool _emailConnected = false;
  final MessageService _sms = MessageService();
  bool _messagesEnabled = false;
  // Pending destructive action waiting for confirmation
  Map<String, dynamic>? _pendingAction;


  @override
void initState() {
  super.initState();
  _addWelcome();
  _initCalendar();
  _initEmail();
  _initMessages();
}

Future<void> _initCalendar() async {
  final granted = await _calendar.checkPermission();
  if (mounted) setState(() => _calendarEnabled = granted);
}
Future<void> _initEmail() async {
  final ok = await _email.checkSignedIn();
  if (mounted) setState(() => _emailConnected = ok);
}
Future<void> _initMessages() async {
  // Re-check permission each time screen initializes
  // to catch cases where user granted it in Settings
  final ok = await _sms.checkPermission();
  if (mounted) {
    setState(() => _messagesEnabled = ok);
    debugPrint('ChatScreen: _messagesEnabled = $ok');
  }
}
  /// Extract a person's name from a message-related query.
  ///
  /// Handles:
  ///   "did Aditya message me?" → "Aditya"
  ///   "any messages from Rahul?" → "Rahul"
  ///   "has Priya texted me?" → "Priya"
  ///   "did I get a message from Aditya Yadav?" → "Aditya Yadav"
  ///   "show me Aditya's messages" → "Aditya"
  String? _extractSenderFromQuery(String query) {
    final q = query.trim();

    // Pattern 1: "from <Name>" — most explicit
    final fromPattern = RegExp(
      r'\bfrom\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)',
      caseSensitive: true,
    );
    final fromMatch = fromPattern.firstMatch(q);
    if (fromMatch != null) {
      return fromMatch.group(1)?.trim();
    }

    // Pattern 2: "<Name> message/text/sms"
    // "Aditya message me" / "Aditya texted"
    final nameBeforeVerbPattern = RegExp(
      r'\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s+'
      r'(?:message|text|sms|messaged|texted|send|sent)',
      caseSensitive: true,
    );
    final nameBeforeMatch =
        nameBeforeVerbPattern.firstMatch(q);
    if (nameBeforeMatch != null) {
      final candidate = nameBeforeMatch.group(1)?.trim();
      // Exclude common non-name words
      if (candidate != null && !_isStopWord(candidate)) {
        return candidate;
      }
    }

    // Pattern 3: "did <Name> message/text"
    // "did Aditya message me?"
    final didPattern = RegExp(
      r'\bdid\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s+'
      r'(?:message|text|sms|send|messaged|texted)',
      caseSensitive: true,
    );
    final didMatch = didPattern.firstMatch(q);
    if (didMatch != null) {
      final candidate = didMatch.group(1)?.trim();
      if (candidate != null && !_isStopWord(candidate)) {
        return candidate;
      }
    }

    // Pattern 4: "has <Name> texted/messaged"
    final hasPattern = RegExp(
      r'\bhas\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s+'
      r'(?:texted|messaged|sent)',
      caseSensitive: true,
    );
    final hasMatch = hasPattern.firstMatch(q);
    if (hasMatch != null) {
      final candidate = hasMatch.group(1)?.trim();
      if (candidate != null && !_isStopWord(candidate)) {
        return candidate;
      }
    }

    // Pattern 5: "<Name>'s messages"
    // "show me Aditya's messages"
    final possessivePattern = RegExp(
      r"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)'s\s+message",
      caseSensitive: true,
    );
    final possessiveMatch = possessivePattern.firstMatch(q);
    if (possessiveMatch != null) {
      return possessiveMatch.group(1)?.trim();
    }

    return null; // No sender name found
  }

  bool _isStopWord(String word) {
    const stopWords = {
      'I', 'Me', 'My', 'We', 'You', 'He', 'She', 'It',
      'They', 'Any', 'The', 'A', 'An', 'Did', 'Has',
      'Have', 'Do', 'Does', 'Get', 'Got', 'Show',
    };
    return stopWords.contains(word);
  }
/// Extract explicit date from message like "August 14", "Aug 17", "17th"
  DateTime? _parseDateFromMessage(String message) {
    final lower = message.toLowerCase();
    final now = DateTime.now();

    // Month name + day: "August 14", "aug 17"
    final monthMap = {
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

    for (final entry in monthMap.entries) {
      final pattern = RegExp(
        r'\b' + entry.key + r'[a-z]*\s+(\d{1,2})\b',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(lower);
      if (match != null) {
        final day = int.tryParse(match.group(1) ?? '');
        if (day != null && day >= 1 && day <= 31) {
          int year = now.year;
          final candidate = DateTime(year, entry.value, day);
          // If this date is more than 30 days in the past,
          // assume next year
          if (candidate.isBefore(
              now.subtract(const Duration(days: 30)))) {
            year = now.year + 1;
          }
          return DateTime(year, entry.value, day);
        }
      }
    }

    // ISO date in message: "2026-08-17"
    final isoPattern = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
    final isoMatch = isoPattern.firstMatch(message);
    if (isoMatch != null) {
      return DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    return null; // No explicit date found
  }

  void _addWelcome() {
    _messages.add(ChatMessage(
      text: 'Hi ${widget.userName}! 👋 I\'m UAILM.\n\n'
          'I can see your real tasks and help you manage them. Try asking:\n\n'
          '• "What should I focus on today?"\n'
          '• "What are my high priority tasks?"\n'
          '• "Mark my assignment complete"\n'
          '• "What\'s overdue?"',
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? overrideText]) async {
  final text = (overrideText ?? _controller.text).trim();
  if (text.isEmpty || _loading) return;
  if (overrideText == null) _controller.clear();

  setState(() {
    _messages.add(ChatMessage(text: text, isUser: true));
    _loading = true;
  });
  _scrollToBottom();

  try {
    // Fetch calendar events if permission granted
    // ── Fetch calendar events ──────────────────────────────────
    List<Map<String, dynamic>> calendarEvents = [];
    if (_calendarEnabled) {
      try {
        List<CalendarEventModel> events = [];
        final msgLower = text.toLowerCase();
        final DateTime? explicitDate = _parseDateFromMessage(text);

        if (explicitDate != null) {
          events = await _calendar.getEventsForDate(explicitDate);
        } else if (msgLower.contains('tomorrow')) {
          events = await _calendar.getTomorrowEvents();
        } else if (msgLower.contains('this week') ||
            msgLower.contains('upcoming')) {
          events = await _calendar.getUpcomingEvents(days: 7);
        } else if (msgLower.contains('today') ||
            msgLower.contains('meeting') ||
            msgLower.contains('event') ||
            msgLower.contains('calendar') ||
            msgLower.contains('schedule') ||
            msgLower.contains('what do i have') ||
            msgLower.contains('what time') ||
            msgLower.contains('add to calendar') ||
            msgLower.contains('add my meeting') ||
            msgLower.contains('add meeting') ||
            msgLower.contains('create event') ||
            msgLower.contains('put it on') ||
            msgLower.contains('book') ||
            msgLower.contains('slot')) {
          // Fetch upcoming events for conflict detection
          final today = await _calendar.getTodayEvents();
          final tomorrow = await _calendar.getTomorrowEvents();
          events = [...today, ...tomorrow];
        }
        calendarEvents = _calendar.eventsToJson(events);
      } catch (e) {
        debugPrint('Calendar fetch error: $e');
      }
    }

    // ── Fetch emails ───────────────────────────────────────────
    List<Map<String, dynamic>> emailPayload = [];
    if (_emailConnected) {
      try {
        final msgLower = text.toLowerCase();
        List<EmailModel> fetchedEmails = [];

        // Determine which emails to fetch based on query
        if (msgLower.contains('unread')) {
          fetchedEmails = await _email.fetchUnreadEmails();
        } else if (msgLower.contains('important') ||
            msgLower.contains('urgent')) {
          fetchedEmails = await _email.fetchImportantEmails();
        } else if (msgLower.contains('today') &&
            (msgLower.contains('email') ||
                msgLower.contains('mail') ||
                msgLower.contains('inbox'))) {
          fetchedEmails = await _email.fetchTodayEmails();
        } else if (msgLower.contains('from ')) {
          // Extract sender name after "from"
          final fromMatch =
              RegExp(r'from\s+(\w[\w\s]*)', caseSensitive: false)
                  .firstMatch(text);
          final sender = fromMatch?.group(1)?.trim() ?? '';
          if (sender.isNotEmpty) {
            fetchedEmails = await _email.fetchFromSender(sender);
          } else {
            fetchedEmails = await _email.fetchEmails();
          }
        } else if (msgLower.contains('email') ||
            msgLower.contains('mail') ||
            msgLower.contains('inbox') ||
            msgLower.contains('professor') ||
            msgLower.contains('received')) {
          // Any email-related query — fetch recent
          fetchedEmails = await _email.fetchEmails(maxResults: 10);
        }
        // For non-email queries, don't fetch emails at all
        // to avoid unnecessary API calls

        emailPayload = _email.emailsToJson(fetchedEmails);
        debugPrint(
            'ChatScreen: fetched ${fetchedEmails.length} emails');
      } catch (e) {
        debugPrint('Email fetch error: $e');
      }
    }
        // ── Fetch device messages ──────────────────────────────────
        // ── Fetch device messages ──────────────────────────────────
    List<Map<String, dynamic>> messagePayload = [];
    if (_messagesEnabled) {
      try {
        final msgLower = text.toLowerCase();

        // Detect if this query is about messages/SMS
        final isMessageQuery =
            msgLower.contains('message') ||
            msgLower.contains('sms') ||
            msgLower.contains('text me') ||
            msgLower.contains('texted') ||
            msgLower.contains('messaged') ||
            msgLower.contains('inbox') ||
            msgLower.contains('unread') ||
            msgLower.contains('did') && msgLower.contains('send') ||
            msgLower.contains('latest message') ||
            msgLower.contains('recent message') ||
            msgLower.contains('new message');

        if (isMessageQuery) {
          List<MessageModel> fetchedMessages = [];

          if (msgLower.contains('unread')) {
            fetchedMessages = await _sms.fetchUnread();
          } else if (msgLower.contains('today')) {
            fetchedMessages = await _sms.fetchToday();
          } else {
            // BUG FIX: Extract sender name from ANYWHERE in query,
            // not just after "from".
            //
            // Handles patterns like:
            //   "did Aditya message me?"
            //   "has Rahul texted?"
            //   "any messages from Priya?"
            //   "did I get a message from Aditya?"
            //   "Aditya message"
            final String? senderName =
                _extractSenderFromQuery(text);

            if (senderName != null) {
              // Fetch all and filter by resolved contact name
              fetchedMessages =
                  await _sms.fetchFromSender(senderName);

              // If no match found by name, fall back to recent
              // so the agent can at least see context
              if (fetchedMessages.isEmpty) {
                debugPrint(
                  'ChatScreen: no messages from "$senderName", '
                  'falling back to recent',
                );
                fetchedMessages =
                    await _sms.fetchRecent(count: 15);
              }
            } else {
              fetchedMessages =
                  await _sms.fetchRecent(count: 15);
            }
          }

          messagePayload =
              _sms.messagesToJson(fetchedMessages);
          debugPrint(
            'ChatScreen: sending ${messagePayload.length} '
            'messages to agent',
          );
        }
        // Non-message queries: skip SMS fetch entirely
      } catch (e) {
        debugPrint('MessageService fetch error: $e');
        messagePayload = [];
      }
    } else {
      debugPrint(
          'ChatScreen: _messagesEnabled=false, skipping SMS fetch');
    }

    // ── Send to agent ──────────────────────────────────────────
    final result = await _api.agentChatWithContext(
      userId: widget.userId,
      message: text,
      calendarEvents: calendarEvents,
      emails: emailPayload,
      messages: messagePayload,
    );

    if (!mounted) return;

    final response = result['response'] ?? 'No response';
    final requiresConfirmation =
        result['requires_confirmation'] ?? false;
    final pendingAction =
        result['pending_action'] as Map<String, dynamic>?;

    setState(() {
      _messages.add(ChatMessage(
        text: response,
        isUser: false,
        isConfirmation: requiresConfirmation,
        pendingAction: pendingAction,
      ));
      _loading = false;
      if (requiresConfirmation && pendingAction != null) {
        _pendingAction = pendingAction;
      }
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        text: '⚠️ Cannot reach backend. Is it running?',
        isUser: false,
      ));
      _loading = false;
    });
  }
  _scrollToBottom();
}

  Future<void> _confirmAction(String action) async {
  // Find last pending action
  Map<String, dynamic>? lastPending;
  for (int i = _messages.length - 1; i >= 0; i--) {
    if (_messages[i].pendingAction != null) {
      lastPending = _messages[i].pendingAction;
      break;
    }
  }
  if (lastPending == null) return;

  setState(() {
    _loading = true;
    _messages.add(ChatMessage(
      text: action == 'yes' ? 'Yes, go ahead.' : 'No, cancel.',
      isUser: true,
    ));
    _pendingAction = null;
  });
  _scrollToBottom();

  try {
    String responseText = '';
    final actionType = lastPending['type'] ?? '';

   if (action == 'no') {
      responseText = 'No problem! Action cancelled.';

    } else if (actionType == 'create_calendar_event') {
      // Flutter executes calendar creation directly.
      // NEVER trust the AI to claim success — we verify here.
      final title = lastPending['title'] as String? ?? 'Event';
      final dateStr = lastPending['date'] as String?;
      final timeStr = lastPending['time'] as String?;
      final durationHours =
          (lastPending['duration_hours'] as num?)?.toInt() ?? 1;

      // Resolve date+time to actual DateTime
      DateTime? start;
      DateTime? end;

      if (dateStr != null || timeStr != null) {
        start = _resolveEventDateTime(dateStr, timeStr);
        if (start != null) {
          end = start.add(Duration(hours: durationHours));
        }
      }

      if (start == null || end == null) {
        responseText =
            "I couldn't determine the exact date and time. "
            "Please specify the date and time more clearly, "
            "for example: 'Add meeting tomorrow at 5 PM'.";
      } else {
        // Actually call CalendarService — this is the ONLY place
        // where calendar creation is executed from chat
        final calResult = await _calendar.createEvent(
          title: title,
          start: start,
          end: end,
          description: 'Added via UAILM chat',
        );

        if (calResult.success) {
          responseText =
              "✅ Done! **$title** has been added to your "
              "calendar.\n\n"
              "📅 ${_formatDateTime(start)} – "
              "${_formatTime(end)}";
        } else {
          responseText =
              "⚠️ Could not add to calendar: "
              "${calResult.error ?? 'Unknown error'}. "
              "Please try again or add it manually.";
        }
      }

    } else if (actionType == 'delete_calendar_event') {
      // existing delete logic unchanged
      // Flutter executes calendar delete directly
      final eventId = lastPending['event_id'] ?? '';
      final calendarId = lastPending['calendar_id'] ?? '';
      final title = lastPending['event_title'] ?? 'event';

      if (eventId.isNotEmpty && calendarId.isNotEmpty) {
        final success =
            await _calendar.deleteEvent(eventId, calendarId);
        responseText = success
            ? "✅ Done! I've deleted '$title' from your calendar."
            : "⚠️ Could not delete the event. Please try from your calendar app.";
      } else {
        responseText = '⚠️ Could not identify the event to delete.';
      }
    } else {
      // Task actions — go through backend
      final taskId = lastPending['task_id'] as int?;
      final result = await _api.agentChatWithContext(
        userId: widget.userId,
        message: action == 'yes' ? 'confirm' : 'cancel',
        confirmAction: action == 'yes' ? actionType : 'cancel',
        confirmTaskId: action == 'yes' ? taskId : null,
      );
      responseText = result['response'] ?? 'Done.';
    }

    if (!mounted) return;
    setState(() {
      _messages.add(
          ChatMessage(text: responseText, isUser: false));
      _loading = false;
    });
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        text: '⚠️ Action failed. Please try again.',
        isUser: false,
      ));
      _loading = false;
    });
  }
  _scrollToBottom();
}

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Quick suggestion chips
  static const _suggestions = [
    'What should I focus on?',
    'High priority tasks?',
    "What's overdue?",
    'Due tomorrow?',
    'All my tasks',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('UAILM AI', style: AppTextStyles.titleMedium),
                Text('Knows your real tasks',
                    style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          // Suggestion chips — only show when no messages beyond welcome
          if (_messages.length <= 1)
            _buildSuggestions(),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) {
                  return _buildTypingIndicator();
                }
                return _buildMessage(_messages[i]);
              },
            ),
          ),

          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _suggestions.map((s) {
          return GestureDetector(
            onTap: () => _sendMessage(s),
            child: Container(
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(AppRadius.full),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    width: 0.5),
              ),
              child: Text(s,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.primary)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: msg.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: msg.isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.isUser) ...[
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(
                      right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 14),
                ),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? AppColors.primary
                        : AppColors.card,
                    borderRadius: BorderRadius.only(
                      topLeft:
                          const Radius.circular(AppRadius.lg),
                      topRight:
                          const Radius.circular(AppRadius.lg),
                      bottomLeft: Radius.circular(msg.isUser
                          ? AppRadius.lg
                          : AppRadius.sm),
                      bottomRight: Radius.circular(msg.isUser
                          ? AppRadius.sm
                          : AppRadius.lg),
                    ),
                    border: msg.isUser
                        ? null
                        : Border.all(
                            color: AppColors.divider,
                            width: 0.5),
                  ),
                  child: Text(
                    msg.text,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: msg.isUser
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Confirmation buttons for destructive actions
          if (msg.isConfirmation &&
              msg.pendingAction != null &&
              !msg.isUser)
            Padding(
              padding: const EdgeInsets.only(
                  left: 40, top: AppSpacing.sm),
              child: Row(
                children: [
                  _ConfirmButton(
                    label: 'Yes, do it',
                    color: AppColors.success,
                    icon: Icons.check_rounded,
                    onTap: () => _confirmAction('yes'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _ConfirmButton(
                    label: 'Cancel',
                    color: AppColors.textSecondary,
                    icon: Icons.close_rounded,
                    onTap: () => _confirmAction('no'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin:
                const EdgeInsets.only(right: AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 14),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                  color: AppColors.divider, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Thinking...',
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.sm,
        bottom:
            MediaQuery.of(context).padding.bottom + AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: AppTextStyles.bodyLarge,
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Ask about your tasks...',
                hintStyle: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                  borderSide: const BorderSide(
                      color: AppColors.divider, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                  borderSide: const BorderSide(
                      color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
    /// Resolve a date string + time string into a local DateTime.
  /// Returns null if date cannot be reliably determined.
  /// Never invents a date.
  DateTime? _resolveEventDateTime(
      String? dateStr, String? timeStr) {
    final now = DateTime.now();
    DateTime? resolvedDate;

    if (dateStr != null) {
      final lower = dateStr.toLowerCase();
      if (lower.contains('today')) {
        resolvedDate = DateTime(now.year, now.month, now.day);
      } else if (lower.contains('tomorrow')) {
        final t = now.add(const Duration(days: 1));
        resolvedDate = DateTime(t.year, t.month, t.day);
      } else {
        // Try weekday
        const weekdays = {
          'monday': 1, 'tuesday': 2, 'wednesday': 3,
          'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
        };
        for (final entry in weekdays.entries) {
          if (lower.contains(entry.key)) {
            int ahead = entry.value - now.weekday;
            if (ahead <= 0) ahead += 7;
            if (lower.contains('next')) ahead += 7;
            final t = now.add(Duration(days: ahead));
            resolvedDate = DateTime(t.year, t.month, t.day);
            break;
          }
        }
        // Try ISO date
        if (resolvedDate == null) {
          try {
            final parsed = DateTime.parse(dateStr);
            resolvedDate =
                DateTime(parsed.year, parsed.month, parsed.day);
          } catch (_) {}
        }
      }
    }

    if (resolvedDate == null) return null;

    // Resolve time
    int hour = 9; // default 9 AM only if time provided
    int minute = 0;
    bool hasTime = false;

    if (timeStr != null && timeStr.isNotEmpty) {
      final lower = timeStr.toLowerCase();
      final ampm = RegExp(
          r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
          caseSensitive: false);
      final match = ampm.firstMatch(lower);
      if (match != null) {
        int h = int.parse(match.group(1)!);
        final m = int.tryParse(match.group(2) ?? '0') ?? 0;
        final period = match.group(3)!.toLowerCase();
        if (period == 'pm' && h != 12) h += 12;
        if (period == 'am' && h == 12) h = 0;
        hour = h;
        minute = m;
        hasTime = true;
      } else {
        // 24h format
        final h24 = RegExp(r'\b(\d{1,2}):(\d{2})\b');
        final h24m = h24.firstMatch(lower);
        if (h24m != null) {
          hour = int.parse(h24m.group(1)!);
          minute = int.parse(h24m.group(2)!);
          hasTime = true;
        }
      }
      // If time string present but unparseable, don't invent time
      if (!hasTime) return null;
    } else {
      // No time provided at all — cannot place on calendar reliably
      return null;
    }

    return DateTime(
        resolvedDate.year, resolvedDate.month, resolvedDate.day,
        hour, minute);
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month]} ${dt.day} · $h:$m $period';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}

// Confirm/Cancel buttons for destructive actions
class _ConfirmButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _ConfirmButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
              color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: AppTextStyles.labelLarge
                    .copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}