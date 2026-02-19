import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/ai_service.dart';
import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../domain/predictive_care_engine.dart';
import '../../models/ai_decision.dart';
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
  final _aiService = AiService();
  final _repository = PlantRepository();
  final _interpreter = PlantInterpreter();
  final _predictiveEngine = PredictiveCareEngine();
  final _imagePicker = ImagePicker();

  PlantReading? _latestReading;
  List<PlantReading> _recentReadings = const <PlantReading>[];
  List<_PendingImageAttachment> _pendingAttachments =
      const <_PendingImageAttachment>[];
  bool _photoAssistSuggested = false;
  double? _lastAiConfidence;
  bool _isSending = false;
  bool _isClearing = false;
  bool _showScrollToBottom = false;
  bool _hasUnreadWhileAway = false;
  int _lastRenderedMessageCount = 0;
  StreamSubscription? _readingSub;
  StreamSubscription? _historySub;
  StreamSubscription? _aiDecisionSub;
  Timer? _routineTimer;
  Stream<List<ChatMessage>>? _messagesStream;
  ChatMessage? _fallbackAssistantMessage;
  PlantMood? _lastProactiveMood;
  DateTime? _lastProactiveAt;
  String? _lastProactivePlantId;
  final bool _routineEnabled = true;
  DateTime? _lastWaterRoutineAt;
  DateTime? _lastLightRoutineAt;
  DateTime? _lastTempRoutineAt;
  DateTime? _lastWaterNotificationAt;
  DateTime? _lastLightNotificationAt;
  DateTime? _lastTempNotificationAt;
  DateTime? _lastProactiveNotificationAt;
  DateTime? _lastFollowUpNotificationAt;
  int? _lastFollowUpDecisionId;
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
      _pendingAttachments = const <_PendingImageAttachment>[];
      _isSending = false;
      _fallbackAssistantMessage = null;
      _showScrollToBottom = false;
      _hasUnreadWhileAway = false;
      _photoAssistSuggested = false;
      _lastAiConfidence = null;
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
    _historySub?.cancel();
    _aiDecisionSub?.cancel();
    _routineTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _retryLocalSync() async {
    if (_isSending || _isClearing || widget.selectedPlant == null) {
      return;
    }
    final unsyncedUsers = _localMessages.where((m) => m.isUser).toList();
    if (unsyncedUsers.isEmpty) return;

    setState(() => _isSending = true);
    var successCount = 0;
    for (final message in unsyncedUsers) {
      final prediction = _predictiveEngine.predict(
        readings: _recentReadings,
        plant: widget.selectedPlant,
      );
      final result = await _aiService.generateReply(
        message: message.text,
        plant: widget.selectedPlant,
        reading: _latestReading,
        recentReadings: _recentReadings,
        prediction: prediction.toMap(),
      );
      if (result.persisted) {
        successCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (successCount == unsyncedUsers.length) {
        _localMessages.clear();
        _fallbackAssistantMessage = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          successCount == unsyncedUsers.length
              ? 'Messaggi sincronizzati.'
              : 'Sincronizzati $successCount/${unsyncedUsers.length}.',
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final hasAttachments = _pendingAttachments.isNotEmpty;
    if ((text.isEmpty && !hasAttachments) || _isSending || _isClearing) {
      return;
    }
    final effectiveText = text.isEmpty
        ? 'Analizza questa foto della pianta e dammi azioni concrete.'
        : text;
    final attachmentsToSend = List<_PendingImageAttachment>.from(
      _pendingAttachments,
    );
    final imagePayload = attachmentsToSend
        .map((item) => item.dataUrl)
        .toList(growable: false);
    final userMessageText = attachmentsToSend.isEmpty
        ? effectiveText
        : '[${attachmentsToSend.length} foto] $effectiveText';

    setState(() {
      _pendingMessages.add(
        ChatMessage(
          text: userMessageText,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _controller.clear();
      _pendingAttachments = const <_PendingImageAttachment>[];
      _isSending = true;
      _fallbackAssistantMessage = null;
    });

    _scheduleScrollToBottom(animated: true);

    try {
      final prediction = _predictiveEngine.predict(
        readings: _recentReadings,
        plant: widget.selectedPlant,
      );
      final result = await _aiService.generateReply(
        message: effectiveText,
        plant: widget.selectedPlant,
        reading: _latestReading,
        recentReadings: _recentReadings,
        prediction: prediction.toMap(),
        imageUrls: imagePayload,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final pendingUserMessages = List<ChatMessage>.from(_pendingMessages);
        _pendingMessages.clear();
        _isSending = false;
        _photoAssistSuggested =
            result.needsPhoto ||
            (result.confidence != null && result.confidence! < 0.62);
        _lastAiConfidence = result.confidence;
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
          _localMessages.add(
            ChatMessage(
              text: trimmedReply,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
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
        _localMessages.add(
          ChatMessage(
            text: 'Errore di rete. Riprova tra qualche secondo.',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
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

  Future<void> _addPhotoAttachment() async {
    if (_isSending || _isClearing || widget.selectedPlant == null) {
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scatta foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli da galleria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final base64Data = base64Encode(bytes);
    final mime = _mimeTypeForPath(picked.path);
    final attachment = _PendingImageAttachment(
      dataUrl: 'data:$mime;base64,$base64Data',
      fileName: picked.name,
    );

    if (!mounted) return;
    setState(() {
      final updated = [..._pendingAttachments, attachment];
      _pendingAttachments = updated.take(4).toList(growable: false);
      _photoAssistSuggested = true;
    });
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F5F0),
                  borderRadius: BorderRadius.circular(20),
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
            if (_localMessages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _LocalSyncBanner(
                  count: _localMessages.where((m) => m.isUser).length,
                  onRetry: _retryLocalSync,
                ),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.outline),
                ),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
                      return _EmptyState(
                        onStartPlantUpdate: _requestProactiveUpdate,
                      );
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
                                  child: const Icon(
                                    Icons.arrow_downward_rounded,
                                  ),
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
              attachments: _pendingAttachments,
              showAddPhotoAction: widget.selectedPlant != null,
              showPhotoHint:
                  _photoAssistSuggested || _pendingAttachments.isNotEmpty,
              confidence: _lastAiConfidence,
              onAddPhoto: _addPhotoAttachment,
              onClearAttachment: (id) {
                setState(() {
                  _pendingAttachments = _pendingAttachments
                      .where((item) => item.id != id)
                      .toList(growable: false);
                });
              },
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
      _historySub?.cancel();
      _latestReading = null;
      _recentReadings = const <PlantReading>[];
      _localMessages.clear();
      _pendingMessages.clear();
      _pendingAttachments = const <_PendingImageAttachment>[];
      _photoAssistSuggested = false;
      _lastAiConfidence = null;
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

    _historySub?.cancel();
    _historySub = _repository
        .recentReadings(limit: 72, plantId: plant.id)
        .listen((history) {
          if (!mounted) return;
          setState(() => _recentReadings = history);
        });

    _aiDecisionSub?.cancel();
    _aiDecisionSub = _repository
        .recentAiDecisions(plantId: plant.id, limit: 12)
        .listen((decisions) {
          _checkDueFollowUps(plant.name, decisions);
        });
  }

  void _checkDueFollowUps(String plantName, List<AiDecision> decisions) {
    final now = DateTime.now();
    final due = decisions
        .where((d) {
          return d.outcome == null &&
              d.followUpDueAt != null &&
              d.followUpDueAt!.isBefore(now);
        })
        .toList(growable: false);
    if (due.isEmpty) return;

    final target = due.first;
    if (_lastFollowUpDecisionId == target.id &&
        _lastFollowUpNotificationAt != null &&
        now.difference(_lastFollowUpNotificationAt!) <
            const Duration(hours: 8)) {
      return;
    }
    _lastFollowUpDecisionId = target.id;
    _lastFollowUpNotificationAt = now;
    NotificationService.instance.showRoutineAlert(
      title: '$plantName · Follow-up',
      body:
          'Aggiorna esito ultima decisione AI (migliorata/uguale/peggiorata).',
    );
  }

  void _startRoutineScheduler() {
    _routineTimer?.cancel();
    _routineTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!mounted || !_routineEnabled) return;
      _runRoutineChecks();
    });
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
        force ||
        _lastWaterRoutineAt == null ||
        now.difference(_lastWaterRoutineAt!) >= waterCooldown;
    final lightDue =
        force ||
        _lastLightRoutineAt == null ||
        now.difference(_lastLightRoutineAt!) >= lightCooldown;
    final tempDue =
        force ||
        _lastTempRoutineAt == null ||
        now.difference(_lastTempRoutineAt!) >= tempCooldown;

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
      _localMessages.add(
        ChatMessage(text: normalized, isUser: false, timestamp: timestamp),
      );
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
    if (temp > 30) {
      return 'Fa caldo, meglio evitare sole diretto nelle ore forti.';
    }
    return 'Temperatura nella mia zona comfort.';
  }

  void _notifyProactiveAlertIfNeeded(
    String plantName,
    PlantMood mood,
    String body,
  ) {
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

  _PlantVoice _voiceForPlant(Plant plant) {
    final personality = plant.personality.toLowerCase();
    if (personality.contains('iron')) {
      return const _PlantVoice(lead: 'Ehi');
    }
    if (personality.contains('poetic') ||
        personality.contains('poetica') ||
        personality.contains('poet')) {
      return const _PlantVoice(lead: 'Piccolo aggiornamento');
    }
    if (personality.contains('energ') || personality.contains('vivace')) {
      return const _PlantVoice(lead: 'Hey');
    }
    return const _PlantVoice(lead: 'Ciao');
  }

  void _maybeStartConversationFromReading(
    PlantReading? reading, {
    bool force = false,
  }) {
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
      final tooSoon =
          _lastProactiveAt != null &&
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
        ChatMessage(text: text, isUser: false, timestamp: now),
      );
      _lastProactiveMood = insight.mood;
      _lastProactiveAt = now;
    });
    _notifyProactiveAlertIfNeeded(plant.name, insight.mood, text);
  }

  String _proactiveTextFor(PlantInsight insight, PlantReading? reading) {
    final plant = widget.selectedPlant;
    final voice = plant != null
        ? _voiceForPlant(plant)
        : const _PlantVoice(lead: 'Ciao');
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
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
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
        entries.add(_ChatEntry.dayDivider(_formatDayDivider(day)));
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
  const _LocalSyncBanner({required this.count, required this.onRetry});

  final int count;
  final VoidCallback onRetry;

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
                  ? '$count messaggi non sincronizzati.'
                  : 'Risposte locali non sincronizzate.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF6C4D3C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Riprova sync')),
        ],
      ),
    );
  }
}

class _PlantVoice {
  const _PlantVoice({required this.lead});

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
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
    final maxBubbleWidth = math.min(
      MediaQuery.sizeOf(context).width * 0.82,
      460.0,
    );
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
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
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
              ).textTheme.bodyLarge?.copyWith(color: textColor, height: 1.3),
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
          const Expanded(child: Divider(color: Color(0xFFDAD4C8), height: 1)),
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
          const Expanded(child: Divider(color: Color(0xFFDAD4C8), height: 1)),
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
    required this.attachments,
    required this.showAddPhotoAction,
    required this.showPhotoHint,
    required this.confidence,
    required this.onAddPhoto,
    required this.onClearAttachment,
    required this.onSend,
    required this.onNudgePlant,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isClearing;
  final bool hasPlant;
  final List<_PendingImageAttachment> attachments;
  final bool showAddPhotoAction;
  final bool showPhotoHint;
  final double? confidence;
  final VoidCallback onAddPhoto;
  final ValueChanged<String> onClearAttachment;
  final VoidCallback onSend;
  final VoidCallback onNudgePlant;

  @override
  Widget build(BuildContext context) {
    final isDisabled = isSending || isClearing || !hasPlant;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, math.max(10, bottomInset)),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final attachment = attachments[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECE7DD),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFDDD5C7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_outlined, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            attachment.fileName,
                            style: Theme.of(context).textTheme.labelSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => onClearAttachment(attachment.id),
                            child: const Icon(Icons.close, size: 14),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemCount: attachments.length,
                ),
              ),
            ),
          if (showPhotoHint && attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2E8DF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE0CDBF)),
                  ),
                  child: Text(
                    confidence != null
                        ? 'Confidenza ${(confidence! * 100).round()}%: aggiungi foto per verifica.'
                        : 'Aggiungi foto per migliorare l\'analisi.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF6C4D3C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: isDisabled ? null : onNudgePlant,
                tooltip: 'Fai iniziare la pianta',
                icon: const Icon(Icons.campaign_outlined),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFECE7DD),
                  minimumSize: const Size(44, 44),
                ),
              ),
              const SizedBox(width: 8),
              if (showAddPhotoAction) ...[
                IconButton(
                  onPressed: isDisabled ? null : onAddPhoto,
                  tooltip: 'Aggiungi foto',
                  icon: const Icon(Icons.add_a_photo_outlined),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFECE7DD),
                    minimumSize: const Size(44, 44),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
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
              const SizedBox(width: 8),
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

class _PendingImageAttachment {
  const _PendingImageAttachment._({
    required this.id,
    required this.dataUrl,
    required this.fileName,
  });

  factory _PendingImageAttachment({
    required String dataUrl,
    required String fileName,
  }) {
    return _PendingImageAttachment._(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dataUrl: dataUrl,
      fileName: fileName,
    );
  }

  final String id;
  final String dataUrl;
  final String fileName;
}

enum _ChatEntryKind { dayDivider, message }

class _ChatEntry {
  const _ChatEntry._({required this.kind, this.label, this.message});

  const _ChatEntry.dayDivider(String label)
    : this._(kind: _ChatEntryKind.dayDivider, label: label);

  const _ChatEntry.message(ChatMessage message)
    : this._(kind: _ChatEntryKind.message, message: message);

  final _ChatEntryKind kind;
  final String? label;
  final ChatMessage? message;
}
