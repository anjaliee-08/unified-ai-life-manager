import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_theme.dart';

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

  // Pending destructive action waiting for confirmation
  Map<String, dynamic>? _pendingAction;

  @override
  void initState() {
    super.initState();
    _addWelcome();
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

    if (overrideText == null) {
      _controller.clear();
    }

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final result = await _api.agentChat(
        userId: widget.userId,
        message: text,
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

        // Store pending action
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
    if (_pendingAction == null) return;

    final taskId = _pendingAction!['task_id'] as int?;
    setState(() {
      _pendingAction = null;
      _loading = true;
      _messages.add(ChatMessage(
        text: action == 'yes' ? 'Yes, go ahead.' : 'No, cancel.',
        isUser: true,
      ));
    });
    _scrollToBottom();

    try {
      final actionType = action == 'yes'
          ? _pendingAction == null
              ? 'cancel'
              : (_messages
                      .lastWhere((m) => m.pendingAction != null,
                          orElse: () => ChatMessage(
                              text: '', isUser: false))
                      .pendingAction?['type'] ??
                  'cancel')
          : 'cancel';

      // Get the last pending action type from messages
      String confirmType = 'cancel';
      int? confirmId;
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].pendingAction != null) {
          confirmType = action == 'yes'
              ? (_messages[i].pendingAction!['type'] ?? 'cancel')
              : 'cancel';
          confirmId = _messages[i].pendingAction!['task_id'];
          break;
        }
      }

      final result = await _api.agentChat(
        userId: widget.userId,
        message: action == 'yes' ? 'confirm' : 'cancel',
        confirmAction: action == 'yes' ? confirmType : 'cancel',
        confirmTaskId: action == 'yes' ? confirmId : null,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: result['response'] ?? 'Done.',
          isUser: false,
        ));
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