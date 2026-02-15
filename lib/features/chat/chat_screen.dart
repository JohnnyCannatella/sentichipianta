import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/claude_service.dart';
import '../../data/plant_repository.dart';
import '../../models/chat_message.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../ui/app_colors.dart';
import '../../widgets/plant_picker_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.plants,
    required this.selectedPlant,
    required this.onSelectPlant,
  });

  final List<Plant> plants;
  final Plant? selectedPlant;
  final ValueChanged<Plant?> onSelectPlant;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _pendingMessages = <ChatMessage>[];
  final _claudeService = ClaudeService();
  final _repository = PlantRepository();

  PlantReading? _latestReading;
  bool _isSending = false;
  bool _isClearing = false;
  int _lastRenderedMessageCount = 0;
  StreamSubscription? _readingSub;
  Stream<List<ChatMessage>>? _messagesStream;
  ChatMessage? _fallbackAssistantMessage;

  @override
  void initState() {
    super.initState();
    _bindPlant(widget.selectedPlant);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPlant?.id != widget.selectedPlant?.id) {
      _bindPlant(widget.selectedPlant);
      _controller.clear();
      _pendingMessages.clear();
      _isSending = false;
      _fallbackAssistantMessage = null;
      _lastRenderedMessageCount = 0;
    }
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending || _isClearing) {
      return;
    }

    setState(() {
      _pendingMessages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _controller.clear();
      _isSending = true;
      _fallbackAssistantMessage = null;
    });

    _scheduleScrollToBottom(animated: true);

    try {
      final reply = await _claudeService.generateReply(
        message: text,
        plant: widget.selectedPlant,
        reading: _latestReading,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingMessages.clear();
        _isSending = false;
        final trimmedReply = reply.trim();
        if (trimmedReply.isNotEmpty) {
          _fallbackAssistantMessage = ChatMessage(
            text: trimmedReply,
            isUser: false,
            timestamp: DateTime.now(),
          );
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingMessages.clear();
        _isSending = false;
        _fallbackAssistantMessage = ChatMessage(
          text: 'Errore di rete. Riprova tra qualche secondo.',
          isUser: false,
          timestamp: DateTime.now(),
        );
      });
    }

    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _clearConversation() async {
    final plant = widget.selectedPlant;
    if (plant == null || _isClearing) {
      return;
    }
    if (_isSending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invio in corso: attendi qualche secondo e riprova.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancella conversazione'),
          content: Text('Vuoi eliminare tutti i messaggi con ${plant.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancella'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isClearing = true;
      _pendingMessages.clear();
    });

    try {
      final remaining = await _repository.clearConversation(plantId: plant.id);
      if (!mounted) {
        return;
      }
      if (remaining > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Non riesco a cancellare la chat (rimasti $remaining messaggi). Verifica i permessi Supabase.',
            ),
          ),
        );
        return;
      }
      _bindPlant(plant);
      _lastRenderedMessageCount = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversazione cancellata.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante la cancellazione.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  void _refresh() {
    _bindPlant(widget.selectedPlant);
    _lastRenderedMessageCount = 0;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Aggiornato ora')));
  }

  void _scheduleScrollToBottom({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      final offset = _scrollController.position.maxScrollExtent + 120;
      if (animated) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return;
      }

      _scrollController.jumpTo(offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFC7D3C0), Color(0xFFB6C5AE)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEFE8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xB2FFFFFF),
                    width: 1.2,
                  ),
                ),
                child: _ChatHeader(
                  plants: widget.plants,
                  selectedPlant: widget.selectedPlant,
                  latestReading: _latestReading,
                  isClearing: _isClearing,
                  isSending: _isSending,
                  onSelectPlant: widget.onSelectPlant,
                  onClearConversation: _clearConversation,
                  onRefresh: _refresh,
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.outline),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    final persisted = snapshot.data ?? const [];
                    final fallback = _fallbackAssistantMessage;
                    final showFallback =
                        fallback != null &&
                        !persisted.any(
                          (m) =>
                              !m.isUser &&
                              m.text.trim() == fallback.text.trim(),
                        );

                    final combined = [
                      ...persisted,
                      ..._pendingMessages,
                      if (showFallback) fallback,
                    ];

                    if (combined.length != _lastRenderedMessageCount) {
                      _lastRenderedMessageCount = combined.length;
                      _scheduleScrollToBottom(animated: persisted.isNotEmpty);
                    }

                    if (combined.isEmpty && !_isSending) {
                      return _EmptyState(onQuickPrompt: _handleQuickPrompt);
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: combined.length + (_isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isSending && index == combined.length) {
                          return const _TypingBubble();
                        }
                        final message = combined[index];
                        return _ChatBubble(message: message);
                      },
                    );
                  },
                ),
              ),
            ),
            _ChatInput(
              controller: _controller,
              isSending: _isSending,
              isClearing: _isClearing,
              hasPlant: widget.selectedPlant != null,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  void _handleQuickPrompt(String text) {
    _controller.text = text;
    _sendMessage();
  }

  void _bindPlant(Plant? plant) {
    if (plant == null) {
      _messagesStream = null;
      _readingSub?.cancel();
      _latestReading = null;
      _fallbackAssistantMessage = null;
      return;
    }

    _messagesStream = _repository.messages(plantId: plant.id);

    _readingSub?.cancel();
    _readingSub = _repository.latestReadingForPlant(plantId: plant.id).listen((
      reading,
    ) {
      setState(() => _latestReading = reading);
    });
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.plants,
    required this.selectedPlant,
    required this.latestReading,
    required this.isClearing,
    required this.isSending,
    required this.onSelectPlant,
    required this.onClearConversation,
    required this.onRefresh,
  });

  final List<Plant> plants;
  final Plant? selectedPlant;
  final PlantReading? latestReading;
  final bool isClearing;
  final bool isSending;
  final ValueChanged<Plant?> onSelectPlant;
  final VoidCallback onClearConversation;
  final VoidCallback onRefresh;

  static final _timeFormatter = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final title = selectedPlant?.name ?? 'Chat con la pianta';
    final subtitle = latestReading == null
        ? 'Nessuna lettura recente'
        : 'Ultima lettura ${_timeFormatter.format(latestReading!.createdAt)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F3EA),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFCFE6D6)),
                ),
                child: Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ChatHeaderControls(
          hasMultiplePlants: plants.length > 1,
          isClearing: isClearing,
          isSending: isSending,
          canDelete: selectedPlant != null,
          onPickPlant: () => PlantPickerSheet.show(
            context,
            plants: plants,
            selectedId: selectedPlant?.id,
            onChanged: onSelectPlant,
          ),
          onRefresh: onRefresh,
          onDelete: onClearConversation,
        ),
      ],
    );
  }
}

class _ChatHeaderControls extends StatelessWidget {
  const _ChatHeaderControls({
    required this.hasMultiplePlants,
    required this.isClearing,
    required this.isSending,
    required this.canDelete,
    required this.onPickPlant,
    required this.onRefresh,
    required this.onDelete,
  });

  final bool hasMultiplePlants;
  final bool isClearing;
  final bool isSending;
  final bool canDelete;
  final VoidCallback onPickPlant;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF191D18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMultiplePlants) ...[
            _HeaderPillButton(
              icon: Icons.swap_horiz,
              onTap: onPickPlant,
              tooltip: 'Seleziona pianta',
            ),
            const SizedBox(width: 6),
          ],
          _HeaderPillButton(
            icon: Icons.refresh,
            onTap: onRefresh,
            tooltip: 'Aggiorna',
          ),
          const SizedBox(width: 6),
          _HeaderPillButton(
            icon: isClearing ? Icons.hourglass_top : Icons.delete_outline,
            onTap: canDelete && !isClearing && !isSending ? onDelete : null,
            tooltip: 'Cancella conversazione',
          ),
        ],
      ),
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.white24,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF111612)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onQuickPrompt});

  final void Function(String) onQuickPrompt;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F5EC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFCFE5D6)),
              ),
              child: const Icon(
                Icons.spa_outlined,
                size: 38,
                color: Color(0xFF2F8C57),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Inizia una conversazione',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Fai una domanda sulla salute della pianta o chiedi consigli pratici.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5B6258)),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickPrompt(
                  icon: Icons.favorite_border,
                  label: 'Come stai?',
                  onTap: () => onQuickPrompt('Come stai oggi?'),
                ),
                _QuickPrompt(
                  icon: Icons.tips_and_updates_outlined,
                  label: 'Consigli rapidi',
                  onTap: () => onQuickPrompt('Cosa posso fare per aiutarti?'),
                ),
                _QuickPrompt(
                  icon: Icons.insights_outlined,
                  label: 'Spiegami i dati',
                  onTap: () => onQuickPrompt('Puoi spiegarmi i dati di oggi?'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickPrompt extends StatelessWidget {
  const _QuickPrompt({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAE5D8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFDDD5C7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF2E3C2F)),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: const Color(0xFF2E3C2F)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final bubbleColor = message.isUser
        ? AppColors.primary
        : const Color(0xFFF3F7F2);
    final borderColor = message.isUser
        ? AppColors.primaryDark
        : const Color(0xFFDDE5DB);
    final textColor = message.isUser ? Colors.white : AppColors.textDark;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 6),
            bottomRight: Radius.circular(message.isUser ? 6 : 18),
          ),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: message.isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: textColor),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: message.isUser
                    ? Colors.white.withValues(alpha: 0.8)
                    : AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE5DB)),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final activeIndex = (_controller.value * 3).floor().clamp(0, 2);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final isActive = index == activeIndex;
                return Container(
                  width: 7,
                  height: 7,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.isSending,
    required this.isClearing,
    required this.hasPlant,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isClearing;
  final bool hasPlant;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isDisabled = isSending || isClearing || !hasPlant;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              enabled: !isDisabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: hasPlant
                    ? 'Scrivi alla tua pianta...'
                    : 'Seleziona una pianta per iniziare',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: isDisabled ? null : onSend,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: AppColors.primary,
            ),
            icon: isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
