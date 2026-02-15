import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/claude_service.dart';
import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/chat_message.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../services/notification_service.dart';
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
  final _localMessages = <ChatMessage>[];
  final _claudeService = ClaudeService();
  final _repository = PlantRepository();
  final _interpreter = PlantInterpreter();

  PlantReading? _latestReading;
  bool _isSending = false;
  bool _isClearing = false;
  bool _showScrollToBottom = false;
  bool _hasUnreadWhileAway = false;
  int _lastRenderedMessageCount = 0;
  StreamSubscription? _readingSub;
  Timer? _routineTimer;
  Stream<List<ChatMessage>>? _messagesStream;
  ChatMessage? _fallbackAssistantMessage;
  PlantMood? _lastProactiveMood;
  DateTime? _lastProactiveAt;
  String? _lastProactivePlantId;
  bool _routineEnabled = true;
  DateTime? _nextRoutineAt;
  DateTime? _lastWaterRoutineAt;
  DateTime? _lastLightRoutineAt;
  DateTime? _lastTempRoutineAt;
  DateTime? _lastWaterNotificationAt;
  DateTime? _lastLightNotificationAt;
  DateTime? _lastTempNotificationAt;
  DateTime? _lastProactiveNotificationAt;
  static const _weekdayNames = [
    'Lunedi',
    'Martedi',
    'Mercoledi',
    'Giovedi',
    'Venerdi',
    'Sabato',
    'Domenica',
  ];
  static const _monthNames = [
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _bindPlant(widget.selectedPlant);
    _startRoutineScheduler();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPlant?.id != widget.selectedPlant?.id) {
      _bindPlant(widget.selectedPlant);
      _controller.clear();
      _pendingMessages.clear();
      _localMessages.clear();
      _isSending = false;
      _fallbackAssistantMessage = null;
      _showScrollToBottom = false;
      _hasUnreadWhileAway = false;
      _lastProactiveMood = null;
      _lastProactiveAt = null;
      _lastProactivePlantId = widget.selectedPlant?.id;
      _lastWaterRoutineAt = null;
      _lastLightRoutineAt = null;
      _lastTempRoutineAt = null;
      _lastWaterNotificationAt = null;
      _lastLightNotificationAt = null;
      _lastTempNotificationAt = null;
      _lastProactiveNotificationAt = null;
      _lastRenderedMessageCount = 0;
    }
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _routineTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
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
      _pendingMessages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _controller.clear();
      _isSending = true;
      _fallbackAssistantMessage = null;
    });

    _scheduleScrollToBottom(animated: true);

    try {
      final result = await _claudeService.generateReply(
        message: text,
        plant: widget.selectedPlant,
        reading: _latestReading,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final pendingUserMessages = List<ChatMessage>.from(_pendingMessages);
        _pendingMessages.clear();
        _isSending = false;
        final trimmedReply = result.reply.trim();
        if (result.persisted) {
          if (trimmedReply.isNotEmpty) {
            _fallbackAssistantMessage = ChatMessage(
              text: trimmedReply,
              isUser: false,
              timestamp: DateTime.now(),
            );
          }
          return;
        }

        _fallbackAssistantMessage = null;
        _localMessages.addAll(pendingUserMessages);
        if (trimmedReply.isNotEmpty) {
          _localMessages.add(ChatMessage(
            text: trimmedReply,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        } else {
          _fallbackAssistantMessage = ChatMessage(
            text: 'Messaggio non salvato. Verifica la connessione e riprova.',
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
        final pendingUserMessages = List<ChatMessage>.from(_pendingMessages);
        _pendingMessages.clear();
        _localMessages.addAll(pendingUserMessages);
        _localMessages.add(ChatMessage(
          text: 'Errore di rete. Riprova tra qualche secondo.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isSending = false;
        _fallbackAssistantMessage = null;
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
      _localMessages.clear();
      _fallbackAssistantMessage = null;
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
    _runRoutineChecks(force: true);
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
        if (_showScrollToBottom && mounted) {
          setState(() {
            _showScrollToBottom = false;
            _hasUnreadWhileAway = false;
          });
        }
        return;
      }

      _scrollController.jumpTo(offset);
      if (_showScrollToBottom && mounted) {
        setState(() {
          _showScrollToBottom = false;
          _hasUnreadWhileAway = false;
        });
      }
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    final shouldShow = distanceFromBottom > 220;
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() {
        _showScrollToBottom = shouldShow;
        if (!shouldShow) {
          _hasUnreadWhileAway = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF3F1EC), Color(0xFFE7E2D9)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F5F0),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFF0ECE4),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _RoutinePanel(
                enabled: _routineEnabled,
                nextCheckAt: _nextRoutineAt,
                water: _routineCheckForWater(widget.selectedPlant, _latestReading),
                light: _routineCheckForLight(widget.selectedPlant, _latestReading),
                temperature: _routineCheckForTemperature(_latestReading),
                onToggle: _setRoutineEnabled,
                onRunNow: () {
                  _runRoutineChecks(force: true);
                  _scheduleScrollToBottom(animated: true);
                },
              ),
            ),
            if (_localMessages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _LocalSyncBanner(
                  count: _localMessages.where((m) => m.isUser).length,
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
                      ..._localMessages,
                      ..._pendingMessages,
                      if (showFallback) fallback,
                    ];
                    final entries = _buildEntries(combined);

                    if (combined.length != _lastRenderedMessageCount) {
                      final hadNewMessages =
                          combined.length > _lastRenderedMessageCount;
                      _lastRenderedMessageCount = combined.length;
                      if (_shouldAutoScroll()) {
                        _scheduleScrollToBottom(animated: persisted.isNotEmpty);
                      } else if (hadNewMessages && !_hasUnreadWhileAway) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _hasUnreadWhileAway = true);
                        });
                      }
                    }

                    if (combined.isEmpty && !_isSending) {
                      return _EmptyState(onStartPlantUpdate: _requestProactiveUpdate);
                    }

                    return Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          itemCount: entries.length + (_isSending ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_isSending && index == entries.length) {
                              return const _TypingBubble();
                            }
                            final entry = entries[index];
                            if (entry.kind == _ChatEntryKind.dayDivider) {
                              return _DayDivider(label: entry.label!);
                            }
                            final message = entry.message!;
                            final prev = index > 0 ? entries[index - 1] : null;
                            final next = index + 1 < entries.length
                                ? entries[index + 1]
                                : null;
                            final groupedWithPrevious =
                                prev?.kind == _ChatEntryKind.message &&
                                prev!.message!.isUser == message.isUser;
                            final groupedWithNext =
                                next?.kind == _ChatEntryKind.message &&
                                next!.message!.isUser == message.isUser;
                            return _ChatBubble(
                              message: message,
                              groupedWithPrevious: groupedWithPrevious,
                              groupedWithNext: groupedWithNext,
                            );
                          },
                        ),
                        if (_showScrollToBottom)
                          Positioned(
                            right: 4,
                            bottom: 6,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (_hasUnreadWhileAway)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A3038),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Nuovi messaggi',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                FloatingActionButton.small(
                                  heroTag: 'chat_scroll_bottom',
                                  onPressed: () =>
                                      _scheduleScrollToBottom(animated: true),
                                  backgroundColor: const Color(0xFF2A3038),
                                  foregroundColor: Colors.white,
                                  child: const Icon(Icons.arrow_downward_rounded),
                                ),
                              ],
                            ),
                          ),
                      ],
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
              onNudgePlant: _requestProactiveUpdate,
            ),
          ],
        ),
      ),
    );
  }

  void _requestProactiveUpdate() {
    _maybeStartConversationFromReading(_latestReading, force: true);
    _scheduleScrollToBottom(animated: true);
  }

  void _bindPlant(Plant? plant) {
    if (plant == null) {
      _messagesStream = null;
      _readingSub?.cancel();
      _latestReading = null;
      _localMessages.clear();
      _pendingMessages.clear();
      _fallbackAssistantMessage = null;
      _hasUnreadWhileAway = false;
      _lastWaterNotificationAt = null;
      _lastLightNotificationAt = null;
      _lastTempNotificationAt = null;
      _lastProactiveNotificationAt = null;
      return;
    }

    _messagesStream = _repository.messages(plantId: plant.id);

    _readingSub?.cancel();
    _readingSub = _repository.latestReadingForPlant(plantId: plant.id).listen((
      reading,
    ) {
      setState(() => _latestReading = reading);
      _maybeStartConversationFromReading(reading);
      _runRoutineChecks();
    });
  }

  void _startRoutineScheduler() {
    _routineTimer?.cancel();
    _nextRoutineAt = DateTime.now().add(const Duration(minutes: 6));
    _routineTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!mounted || !_routineEnabled) return;
      _runRoutineChecks();
      setState(() {
        _nextRoutineAt = DateTime.now().add(const Duration(minutes: 6));
      });
    });
  }

  void _setRoutineEnabled(bool enabled) {
    setState(() => _routineEnabled = enabled);
    if (!enabled) {
      _routineTimer?.cancel();
      _nextRoutineAt = null;
      return;
    }
    _startRoutineScheduler();
    _runRoutineChecks(force: true);
  }

  void _runRoutineChecks({bool force = false}) {
    if (!_routineEnabled || !mounted) return;
    final plant = widget.selectedPlant;
    final reading = _latestReading;
    if (plant == null) return;

    final now = DateTime.now();
    const waterCooldown = Duration(minutes: 40);
    const lightCooldown = Duration(minutes: 40);
    const tempCooldown = Duration(minutes: 90);

    final waterDue =
        force || _lastWaterRoutineAt == null || now.difference(_lastWaterRoutineAt!) >= waterCooldown;
    final lightDue =
        force || _lastLightRoutineAt == null || now.difference(_lastLightRoutineAt!) >= lightCooldown;
    final tempDue =
        force || _lastTempRoutineAt == null || now.difference(_lastTempRoutineAt!) >= tempCooldown;

    final voice = _voiceForPlant(plant);

    if (reading != null && waterDue) {
      final waterText = reading.moisture < plant.effectiveMoistureLow
          ? '${voice.lead} Routine acqua: umidita al ${reading.moisture.toStringAsFixed(0)}%. Mi aiuti con irrigazione leggera?'
          : '${voice.lead} Routine acqua: siamo a ${reading.moisture.toStringAsFixed(0)}%, tutto sotto controllo.';
      _appendLocalAssistantUnique(waterText, now);
      _lastWaterRoutineAt = now;
      if (reading.moisture < plant.effectiveMoistureLow) {
        _notifyRoutineIfNeeded(
          kind: 'water',
          title: '${plant.name} · Routine acqua',
          body: 'Umidita bassa (${reading.moisture.toStringAsFixed(0)}%).',
        );
      }
    }

    if (reading != null && lightDue) {
      final lightText = reading.lux < plant.effectiveLuxLow
          ? '${voice.lead} Routine luce: siamo a ${reading.lux.toStringAsFixed(0)} lx, un po bassi. Possiamo cercare piu luce?'
          : '${voice.lead} Routine luce: ${reading.lux.toStringAsFixed(0)} lx, esposizione buona.';
      _appendLocalAssistantUnique(lightText, now);
      _lastLightRoutineAt = now;
      if (reading.lux < plant.effectiveLuxLow) {
        _notifyRoutineIfNeeded(
          kind: 'light',
          title: '${plant.name} · Routine luce',
          body: 'Luce bassa (${reading.lux.toStringAsFixed(0)} lx).',
        );
      }
    }

    if (tempDue) {
      final tempText = reading?.temperature != null
          ? '${voice.lead} Routine temperatura: ${reading!.temperature!.toStringAsFixed(1)}°C. ${_temperatureComment(reading.temperature!)}'
          : '${voice.lead} Routine temperatura: dato non disponibile. Se aggiungi il sensore termico ti aggiorno anche su questo.';
      _appendLocalAssistantUnique(tempText, now);
      _lastTempRoutineAt = now;
      if (reading?.temperature != null &&
          (reading!.temperature! < 16 || reading.temperature! > 30)) {
        _notifyRoutineIfNeeded(
          kind: 'temperature',
          title: '${plant.name} · Routine temperatura',
          body:
              'Temperatura fuori range (${reading.temperature!.toStringAsFixed(1)}°C).',
        );
      }
    }
  }

  void _appendLocalAssistantUnique(String text, DateTime timestamp) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    final lastAssistant = _lastAssistantText();
    if (lastAssistant == normalized) return;
    setState(() {
      _localMessages.add(ChatMessage(
        text: normalized,
        isUser: false,
        timestamp: timestamp,
      ));
    });
  }

  String? _lastAssistantText() {
    final all = [..._localMessages, ..._pendingMessages];
    for (var i = all.length - 1; i >= 0; i--) {
      if (!all[i].isUser) return all[i].text;
    }
    return null;
  }

  String _temperatureComment(double temp) {
    if (temp < 16) return 'Sento freddo, proteggimi nelle ore serali.';
    if (temp > 30) return 'Fa caldo, meglio evitare sole diretto nelle ore forti.';
    return 'Temperatura nella mia zona comfort.';
  }

  void _notifyProactiveAlertIfNeeded(String plantName, PlantMood mood, String body) {
    if (!(mood == PlantMood.thirsty ||
        mood == PlantMood.dark ||
        mood == PlantMood.stressed)) {
      return;
    }
    final now = DateTime.now();
    if (_lastProactiveNotificationAt != null &&
        now.difference(_lastProactiveNotificationAt!) <
            const Duration(minutes: 25)) {
      return;
    }
    _lastProactiveNotificationAt = now;
    NotificationService.instance.showRoutineAlert(
      title: '$plantName · Nuovo alert',
      body: body,
    );
  }

  void _notifyRoutineIfNeeded({
    required String kind,
    required String title,
    required String body,
  }) {
    final now = DateTime.now();
    DateTime? last;
    if (kind == 'water') {
      last = _lastWaterNotificationAt;
    } else if (kind == 'light') {
      last = _lastLightNotificationAt;
    } else if (kind == 'temperature') {
      last = _lastTempNotificationAt;
    }
    if (last != null && now.difference(last) < const Duration(minutes: 35)) {
      return;
    }
    if (kind == 'water') {
      _lastWaterNotificationAt = now;
    } else if (kind == 'light') {
      _lastLightNotificationAt = now;
    } else if (kind == 'temperature') {
      _lastTempNotificationAt = now;
    }
    NotificationService.instance.showRoutineAlert(title: title, body: body);
  }

  _RoutineCheckState _routineCheckForWater(Plant? plant, PlantReading? reading) {
    if (reading == null || plant == null) {
      return const _RoutineCheckState.waiting('In attesa');
    }
    if (reading.moisture < plant.effectiveMoistureLow) {
      return _RoutineCheckState.alert('Bassa', '${reading.moisture.toStringAsFixed(0)}%');
    }
    if (reading.moisture > plant.effectiveMoistureHigh) {
      return _RoutineCheckState.alert('Alta', '${reading.moisture.toStringAsFixed(0)}%');
    }
    return _RoutineCheckState.ok('Ok', '${reading.moisture.toStringAsFixed(0)}%');
  }

  _RoutineCheckState _routineCheckForLight(Plant? plant, PlantReading? reading) {
    if (reading == null || plant == null) {
      return const _RoutineCheckState.waiting('In attesa');
    }
    if (reading.lux < plant.effectiveLuxLow) {
      return _RoutineCheckState.alert('Bassa', '${reading.lux.toStringAsFixed(0)} lx');
    }
    if (reading.lux > plant.effectiveLuxHigh) {
      return _RoutineCheckState.alert('Alta', '${reading.lux.toStringAsFixed(0)} lx');
    }
    return _RoutineCheckState.ok('Ok', '${reading.lux.toStringAsFixed(0)} lx');
  }

  _RoutineCheckState _routineCheckForTemperature(PlantReading? reading) {
    if (reading == null) {
      return const _RoutineCheckState.waiting('In attesa');
    }
    if (reading.temperature == null) {
      return const _RoutineCheckState.waiting('No sensore');
    }
    final t = reading.temperature!;
    if (t < 16 || t > 30) {
      return _RoutineCheckState.alert('Fuori range', '${t.toStringAsFixed(1)}°C');
    }
    return _RoutineCheckState.ok('Ok', '${t.toStringAsFixed(1)}°C');
  }

  _PlantVoice _voiceForPlant(Plant plant) {
    final personality = plant.personality.toLowerCase();
    if (personality.contains('iron')) {
      return const _PlantVoice(
        lead: 'Ehi',
      );
    }
    if (personality.contains('poetic') ||
        personality.contains('poetica') ||
        personality.contains('poet')) {
      return const _PlantVoice(
        lead: 'Piccolo aggiornamento',
      );
    }
    if (personality.contains('energ') || personality.contains('vivace')) {
      return const _PlantVoice(
        lead: 'Hey',
      );
    }
    return const _PlantVoice(
      lead: 'Ciao',
    );
  }

  void _maybeStartConversationFromReading(PlantReading? reading, {bool force = false}) {
    final plant = widget.selectedPlant;
    if (plant == null) {
      return;
    }
    final now = DateTime.now();
    final insight = _interpreter.interpret(reading, plant: plant);
    final critical = _interpreter.isCritical(reading, plant: plant);

    if (_lastProactivePlantId != plant.id) {
      _lastProactivePlantId = plant.id;
      _lastProactiveMood = null;
      _lastProactiveAt = null;
    }

    if (!force) {
      final tooSoon = _lastProactiveAt != null &&
          now.difference(_lastProactiveAt!).inMinutes < 20;
      final sameMood = _lastProactiveMood == insight.mood;
      if (tooSoon || sameMood || !critical) {
        return;
      }
    }

    final text = _proactiveTextFor(insight, reading);
    if (_localMessages.isNotEmpty &&
        _localMessages.last.isUser == false &&
        _localMessages.last.text == text) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _localMessages.add(
        ChatMessage(
          text: text,
          isUser: false,
          timestamp: now,
        ),
      );
      _lastProactiveMood = insight.mood;
      _lastProactiveAt = now;
    });
    _notifyProactiveAlertIfNeeded(plant.name, insight.mood, text);
  }

  String _proactiveTextFor(PlantInsight insight, PlantReading? reading) {
    final plant = widget.selectedPlant;
    final voice = plant != null ? _voiceForPlant(plant) : const _PlantVoice(lead: 'Ciao');
    if (reading == null) {
      return '${voice.lead}, ti aggiorno io appena ricevo nuovi dati dai sensori.';
    }
    switch (insight.mood) {
      case PlantMood.thirsty:
        return '${voice.lead}, alert acqua: terreno secco (${reading.moisture.toStringAsFixed(0)}%). Mi aiuti con un po di acqua?';
      case PlantMood.dark:
        return '${voice.lead}, alert luce: siamo a ${reading.lux.toStringAsFixed(0)} lx. Possiamo spostarci in una zona piu luminosa?';
      case PlantMood.stressed:
        return '${voice.lead}, condizioni intense adesso. Umidita ${reading.moisture.toStringAsFixed(0)}%, luce ${reading.lux.toStringAsFixed(0)} lx. Ti va di riequilibrare insieme?';
      case PlantMood.thriving:
        return '${voice.lead}, sto bene: parametri in equilibrio. Continuo a monitorarmi e ti avviso io se cambia qualcosa.';
      case PlantMood.ok:
        return '${voice.lead}, situazione stabile al momento. Ti avviso appena vedo scostamenti.';
      case PlantMood.unknown:
        return '${voice.lead}, sono in ascolto: appena arrivano dati inizio a parlarti io.';
    }
  }

  bool _shouldAutoScroll() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final distanceFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    return distanceFromBottom < 120;
  }

  List<_ChatEntry> _buildEntries(List<ChatMessage> messages) {
    final entries = <_ChatEntry>[];
    DateTime? lastDay;
    for (final message in messages) {
      final day = DateTime(
        message.timestamp.year,
        message.timestamp.month,
        message.timestamp.day,
      );
      if (lastDay == null || day != lastDay) {
        entries.add(
          _ChatEntry.dayDivider(_formatDayDivider(day)),
        );
        lastDay = day;
      }
      entries.add(_ChatEntry.message(message));
    }
    return entries;
  }

  String _formatDayDivider(DateTime day) {
    final weekday = _weekdayNames[day.weekday - 1];
    final month = _monthNames[day.month - 1];
    return '$weekday ${day.day} $month';
  }
}

class _LocalSyncBanner extends StatelessWidget {
  const _LocalSyncBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2E8DF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0CDBF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: Color(0xFF6C4D3C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count > 0
                  ? '$count messaggi non sincronizzati. Verranno reinviati quando torni online.'
                  : 'Risposte locali non sincronizzate.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF6C4D3C),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutinePanel extends StatelessWidget {
  const _RoutinePanel({
    required this.enabled,
    required this.nextCheckAt,
    required this.water,
    required this.light,
    required this.temperature,
    required this.onToggle,
    required this.onRunNow,
  });

  final bool enabled;
  final DateTime? nextCheckAt;
  final _RoutineCheckState water;
  final _RoutineCheckState light;
  final _RoutineCheckState temperature;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final nextText = nextCheckAt == null
        ? 'Pausa'
        : DateFormat('HH:mm').format(nextCheckAt!);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2EB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3DBCF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 17, color: Color(0xFF3E434D)),
              const SizedBox(width: 6),
              Text(
                'Routine della pianta',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF2F333B),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Switch.adaptive(
                value: enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _RoutineChip(label: 'Acqua', state: water)),
              const SizedBox(width: 6),
              Expanded(child: _RoutineChip(label: 'Luce', state: light)),
              const SizedBox(width: 6),
              Expanded(child: _RoutineChip(label: 'Temp', state: temperature)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Prossimo check: $nextText',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF646058),
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: enabled ? onRunNow : null,
                child: const Text('Esegui ora'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutineChip extends StatelessWidget {
  const _RoutineChip({
    required this.label,
    required this.state,
  });

  final String label;
  final _RoutineCheckState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: state.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: state.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: state.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 1),
          Text(
            '${state.label}${state.value == null ? '' : ' · ${state.value}'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: state.text.withValues(alpha: 0.86),
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RoutineCheckState {
  const _RoutineCheckState.ok(this.label, this.value)
      : background = const Color(0xFFE8EEE8),
        border = const Color(0xFFC9D4C8),
        text = const Color(0xFF2F4A33);

  const _RoutineCheckState.alert(this.label, this.value)
      : background = const Color(0xFFF3E5DF),
        border = const Color(0xFFE0BFB2),
        text = const Color(0xFF6A4033);

  const _RoutineCheckState.waiting(this.label)
      : value = null,
        background = const Color(0xFFECEAE4),
        border = const Color(0xFFDCD5C9),
        text = const Color(0xFF58554E);

  final String label;
  final String? value;
  final Color background;
  final Color border;
  final Color text;
}

class _PlantVoice {
  const _PlantVoice({
    required this.lead,
  });

  final String lead;
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
                  color: const Color(0xFFEDEAE3),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFDED8CC)),
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
        color: const Color(0xFF252B33),
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
  const _EmptyState({required this.onStartPlantUpdate});

  final VoidCallback onStartPlantUpdate;

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
                color: const Color(0xFFEFEBE4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDDD6CA)),
              ),
              child: const _BreathePlantIcon(),
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
              'La tua pianta puo iniziare da sola: premi il pulsante qui sotto e lascia che ti aggiorni lei.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5B6258)),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onStartPlantUpdate,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Lascia parlare la pianta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreathePlantIcon extends StatefulWidget {
  const _BreathePlantIcon();

  @override
  State<_BreathePlantIcon> createState() => _BreathePlantIconState();
}

class _BreathePlantIconState extends State<_BreathePlantIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scale = 1 + (_controller.value * 0.08);
        return Transform.scale(
          scale: scale,
          child: const Icon(
            Icons.spa_outlined,
            size: 38,
            color: Color(0xFF2F3640),
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.groupedWithPrevious,
    required this.groupedWithNext,
  });

  final ChatMessage message;
  final bool groupedWithPrevious;
  final bool groupedWithNext;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final bubbleColor = message.isUser
        ? AppColors.primary
        : const Color(0xFFF5F2EC);
    final borderColor = message.isUser
        ? AppColors.primaryDark
        : const Color(0xFFE4DED3);
    final textColor = message.isUser ? Colors.white : AppColors.textDark;

    return Align(
      alignment: alignment,
      child: Container(
        margin: EdgeInsets.only(
          top: groupedWithPrevious ? 2 : 8,
          bottom: groupedWithNext ? 2 : 8,
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(
              message.isUser
                  ? (groupedWithPrevious ? 12 : 18)
                  : (groupedWithPrevious ? 6 : 18),
            ),
            topRight: Radius.circular(
              message.isUser
                  ? (groupedWithPrevious ? 6 : 18)
                  : (groupedWithPrevious ? 12 : 18),
            ),
            bottomLeft: Radius.circular(
              message.isUser
                  ? (groupedWithNext ? 12 : 18)
                  : (groupedWithNext ? 6 : 18),
            ),
            bottomRight: Radius.circular(
              message.isUser
                  ? (groupedWithNext ? 6 : 18)
                  : (groupedWithNext ? 12 : 18),
            ),
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
            if (!groupedWithNext) ...[
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
          ],
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0xFFDAD4C8), height: 1),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEE9DF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFDCD5C9)),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF5C5952),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const Expanded(
            child: Divider(color: Color(0xFFDAD4C8), height: 1),
          ),
        ],
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
          color: const Color(0xFFF5F2EC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4DED3)),
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
    required this.onNudgePlant,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isClearing;
  final bool hasPlant;
  final VoidCallback onSend;
  final VoidCallback onNudgePlant;

  @override
  Widget build(BuildContext context) {
    final isDisabled = isSending || isClearing || !hasPlant;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: isDisabled ? null : onNudgePlant,
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Fai iniziare la pianta'),
              ),
            ),
          ),
          Row(
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
        ],
      ),
    );
  }
}

enum _ChatEntryKind { dayDivider, message }

class _ChatEntry {
  const _ChatEntry._({
    required this.kind,
    this.label,
    this.message,
  });

  const _ChatEntry.dayDivider(String label)
      : this._(kind: _ChatEntryKind.dayDivider, label: label);

  const _ChatEntry.message(ChatMessage message)
      : this._(kind: _ChatEntryKind.message, message: message);

  final _ChatEntryKind kind;
  final String? label;
  final ChatMessage? message;
}
