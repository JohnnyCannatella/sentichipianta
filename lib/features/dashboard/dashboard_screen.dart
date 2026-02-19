import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import 'predictive_care_card.dart';
import '../../widgets/plant_avatar.dart';
import '../../widgets/plant_picker_sheet.dart';
import '../../widgets/plant_state_art.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.plants,
    required this.selectedPlant,
    required this.onSelectPlant,
    required this.onOpenChat,
    required this.onRefresh,
  });

  final List<Plant> plants;
  final Plant? selectedPlant;
  final ValueChanged<Plant?> onSelectPlant;
  final VoidCallback onOpenChat;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final repository = PlantRepository();
    final interpreter = PlantInterpreter();

    return SafeArea(
      child: StreamBuilder<PlantReading?>(
        stream: repository.latestReadingForPlant(plantId: selectedPlant?.id),
        builder: (context, latestSnapshot) {
          final latest = latestSnapshot.data;
          final insight = interpreter.interpret(latest, plant: selectedPlant);

          return StreamBuilder<List<PlantReading>>(
            stream: repository.recentReadings(
              limit: 40,
              plantId: selectedPlant?.id,
            ),
            builder: (context, recentSnapshot) {
              final recent = recentSnapshot.data ?? const <PlantReading>[];
              return _DashboardLayout(
                plants: plants,
                selectedPlant: selectedPlant,
                latestReading: latest,
                recentReadings: recent,
                insight: insight,
                hasLoadingState:
                    latestSnapshot.connectionState == ConnectionState.waiting &&
                    latest == null,
                hasError: latestSnapshot.hasError || recentSnapshot.hasError,
                onSelectPlant: onSelectPlant,
                onOpenChat: onOpenChat,
                onRefresh: onRefresh,
              );
            },
          );
        },
      ),
    );
  }
}

class _DashboardLayout extends StatelessWidget {
  const _DashboardLayout({
    required this.plants,
    required this.selectedPlant,
    required this.latestReading,
    required this.recentReadings,
    required this.insight,
    required this.hasLoadingState,
    required this.hasError,
    required this.onSelectPlant,
    required this.onOpenChat,
    required this.onRefresh,
  });

  final List<Plant> plants;
  final Plant? selectedPlant;
  final PlantReading? latestReading;
  final List<PlantReading> recentReadings;
  final PlantInsight insight;
  final bool hasLoadingState;
  final bool hasError;
  final ValueChanged<Plant?> onSelectPlant;
  final VoidCallback onOpenChat;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final healthScore = _healthScore(latestReading, selectedPlant);
    final urgency = _urgencyLabel(insight.mood);
    final statusTone = _statusTone(insight.mood);
    final isCriticalMood = _isCriticalMood(insight.mood);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2F0EB), Color(0xFFE4DED5)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 12 : 16,
          12,
          isCompact ? 12 : 16,
          18,
        ),
        child: Column(
          children: [
            _DashboardTopBar(
              plants: plants,
              selectedPlant: selectedPlant,
              onSelectPlant: onSelectPlant,
              onRefresh: onRefresh,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (hasError) const _OfflineBanner(),
                    _SectionReveal(
                      delayMs: 0,
                      urgent: isCriticalMood,
                      child: _HeroStateCard(
                        selectedPlant: selectedPlant,
                        latestReading: latestReading,
                        insight: insight,
                        urgency: urgency,
                        statusTone: statusTone,
                        healthScore: healthScore,
                        onOpenChat: onOpenChat,
                        compact: isCompact,
                        criticalMood: isCriticalMood,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionReveal(
                      delayMs: 60,
                      urgent: isCriticalMood,
                      child: _AlertCard(
                        mood: insight.mood,
                        title: insight.title,
                        message: insight.message,
                        tone: statusTone,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionReveal(
                      delayMs: 120,
                      urgent: isCriticalMood,
                      child: hasLoadingState && latestReading == null
                          ? const _LoadingCard()
                          : _SensorPanel(
                              reading: latestReading,
                              plant: selectedPlant,
                              compact: isCompact,
                            ),
                    ),
                    const SizedBox(height: 12),
                    _SectionReveal(
                      delayMs: 180,
                      urgent: isCriticalMood,
                      child: _QuickActionsRow(
                        onOpenChat: onOpenChat,
                        onRefresh: onRefresh,
                        compact: isCompact,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionReveal(
                      delayMs: 210,
                      urgent: isCriticalMood,
                      child: PredictiveCareCard(
                        plant: selectedPlant,
                        readings: recentReadings,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionReveal(
                      delayMs: 240,
                      urgent: isCriticalMood,
                      child: _TrendCard(
                        title: 'Trend ultime 24h',
                        subtitle: 'Umidita e luce aggiornate in tempo reale',
                        points: recentReadings.take(24).toList(growable: false),
                        compact: isCompact,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionReveal(
                      delayMs: 300,
                      urgent: isCriticalMood,
                      child: _TimelineCard(
                        readings: recentReadings
                            .take(8)
                            .toList(growable: false),
                        textTheme: theme.textTheme,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _healthScore(PlantReading? reading, Plant? plant) {
    if (reading == null) return 52;
    final moisture = reading.moisture;
    final lux = reading.lux;

    final moistureTarget =
        plant?.effectiveMoistureOk ?? Plant.defaultMoistureOk;
    final luxLow = plant?.effectiveLuxLow ?? Plant.defaultLuxLow;
    final luxHigh = plant?.effectiveLuxHigh ?? Plant.defaultLuxHigh;
    final luxTarget = (luxLow + luxHigh) / 2;

    final moistureDelta = (moisture - moistureTarget).abs();
    final luxDelta = (lux - luxTarget).abs();

    final moisturePenalty = (moistureDelta * 1.6).clamp(0, 65);
    final luxPenalty = ((luxDelta / math.max(luxTarget, 1)) * 90).clamp(0, 55);

    final score = (100 - moisturePenalty - luxPenalty).round().clamp(0, 100);
    return score;
  }

  String _urgencyLabel(PlantMood mood) {
    switch (mood) {
      case PlantMood.thriving:
        return 'Tutto sotto controllo';
      case PlantMood.ok:
        return 'Controllo di routine';
      case PlantMood.thirsty:
        return 'Azione consigliata oggi';
      case PlantMood.dark:
        return 'Serve piu luce';
      case PlantMood.stressed:
        return 'Intervento prioritario';
      case PlantMood.unknown:
        return 'In attesa di dati';
    }
  }

  _StatusTone _statusTone(PlantMood mood) {
    switch (mood) {
      case PlantMood.thriving:
        return const _StatusTone(
          surface: Color(0xFFE9ECEF),
          accent: Color(0xFF3E5A7A),
          text: Color(0xFF1F2B36),
        );
      case PlantMood.ok:
        return const _StatusTone(
          surface: Color(0xFFECE9E2),
          accent: Color(0xFF5E6470),
          text: Color(0xFF2F333B),
        );
      case PlantMood.thirsty:
        return const _StatusTone(
          surface: Color(0xFFF5E6D9),
          accent: Color(0xFFB35F34),
          text: Color(0xFF4C2A18),
        );
      case PlantMood.dark:
        return const _StatusTone(
          surface: Color(0xFFE5E9EE),
          accent: Color(0xFF4E5B68),
          text: Color(0xFF25303A),
        );
      case PlantMood.stressed:
        return const _StatusTone(
          surface: Color(0xFFF1DFD9),
          accent: Color(0xFF8E4939),
          text: Color(0xFF3A1F18),
        );
      case PlantMood.unknown:
        return const _StatusTone(
          surface: Color(0xFFECE7DF),
          accent: Color(0xFF8B7864),
          text: Color(0xFF3C3127),
        );
    }
  }

  bool _isCriticalMood(PlantMood mood) {
    return mood == PlantMood.thirsty ||
        mood == PlantMood.dark ||
        mood == PlantMood.stressed;
  }
}

class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar({
    required this.plants,
    required this.selectedPlant,
    required this.onSelectPlant,
    required this.onRefresh,
  });

  final List<Plant> plants;
  final Plant? selectedPlant;
  final ValueChanged<Plant?> onSelectPlant;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Command Center',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF232830),
                ),
              ),
              Text(
                selectedPlant?.name ?? 'Nessuna pianta selezionata',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4B4F58),
                ),
              ),
            ],
          ),
        ),
        _TopActionPill(
          icon: Icons.swap_horiz,
          enabled: plants.length > 1,
          tooltip: 'Cambia pianta',
          onTap: () => PlantPickerSheet.show(
            context,
            plants: plants,
            selectedId: selectedPlant?.id,
            onChanged: onSelectPlant,
          ),
        ),
        const SizedBox(width: 8),
        _TopActionPill(
          icon: Icons.refresh,
          enabled: true,
          tooltip: 'Aggiorna dati',
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _TopActionPill extends StatelessWidget {
  const _TopActionPill({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFF2A3038) : const Color(0x66111711),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _HeroStateCard extends StatelessWidget {
  const _HeroStateCard({
    required this.selectedPlant,
    required this.latestReading,
    required this.insight,
    required this.urgency,
    required this.statusTone,
    required this.healthScore,
    required this.onOpenChat,
    required this.compact,
    required this.criticalMood,
  });

  final Plant? selectedPlant;
  final PlantReading? latestReading;
  final PlantInsight insight;
  final String urgency;
  final _StatusTone statusTone;
  final int healthScore;
  final VoidCallback onOpenChat;
  final bool compact;
  final bool criticalMood;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        compact ? 12 : 14,
        14,
        compact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F2),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE1DBD1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusTone.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        urgency,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusTone.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      insight.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: const Color(0xFF222831),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      insight.message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4A4F59),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ScoreRing(
                score: healthScore,
                tone: statusTone,
                compact: compact,
                warningPulse: criticalMood,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF1EEE8), Color(0xFFE8E1D7)],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  bottom: 6,
                  child: Container(
                    width: compact ? 130 : 160,
                    height: compact ? 22 : 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                SizedBox(
                  height: compact ? 186 : 220,
                  child: _LivePlantPreview(
                    selectedPlant: selectedPlant,
                    latestReading: latestReading,
                    mood: insight.mood,
                    size: compact ? 180 : 210,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(
                compact ? 'Azione consigliata' : 'Cosa devo fare ora?',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePlantPreview extends StatefulWidget {
  const _LivePlantPreview({
    required this.selectedPlant,
    required this.latestReading,
    required this.mood,
    required this.size,
  });

  final Plant? selectedPlant;
  final PlantReading? latestReading;
  final PlantMood mood;
  final double size;

  @override
  State<_LivePlantPreview> createState() => _LivePlantPreviewState();
}

class _LivePlantPreviewState extends State<_LivePlantPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _critical =>
      widget.mood == PlantMood.thirsty ||
      widget.mood == PlantMood.dark ||
      widget.mood == PlantMood.stressed;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationForMood(widget.mood),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _LivePlantPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _controller.duration = _durationForMood(widget.mood);
      _controller.forward(from: 0);
      _controller.repeat();
    }
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
        final t = _controller.value * 2 * math.pi;
        final sway = (_critical ? 0.032 : 0.015) * math.sin(t);
        final breathe = 1 + (_critical ? 0.018 : 0.010) * math.sin(t + 1.6);
        final bob = (_critical ? 2.2 : 1.1) * math.sin(t);
        final shake = _critical ? 1.8 * math.sin(t * 5) : 0.0;

        return Transform.translate(
          offset: Offset(shake, bob),
          child: Transform.rotate(
            angle: sway,
            child: Transform.scale(
              scale: breathe,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PlantAvatar(
                    plantName: widget.selectedPlant?.name ?? 'Senti Chi Pianta',
                    plantType: widget.selectedPlant?.plantType,
                    size: widget.size,
                    radius: 26,
                  ),
                  PlantStateArt(
                    plant: widget.selectedPlant,
                    reading: widget.latestReading,
                    size: widget.size,
                    radius: 26,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Duration _durationForMood(PlantMood mood) {
    switch (mood) {
      case PlantMood.stressed:
      case PlantMood.thirsty:
        return const Duration(milliseconds: 1200);
      case PlantMood.dark:
        return const Duration(milliseconds: 1400);
      case PlantMood.thriving:
        return const Duration(milliseconds: 1900);
      case PlantMood.ok:
      case PlantMood.unknown:
        return const Duration(milliseconds: 1650);
    }
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.tone,
    required this.compact,
    required this.warningPulse,
  });

  final int score;
  final _StatusTone tone;
  final bool compact;
  final bool warningPulse;

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);
    return _WarningPulse(
      enabled: warningPulse,
      child: SizedBox(
        width: compact ? 74 : 84,
        height: compact ? 74 : 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: compact ? 6 : 7,
              backgroundColor: tone.surface,
              valueColor: AlwaysStoppedAnimation<Color>(tone.accent),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF222830),
                  ),
                ),
                const Text(
                  'salute',
                  style: TextStyle(fontSize: 11, color: Color(0xFF626670)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningPulse extends StatefulWidget {
  const _WarningPulse({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_WarningPulse> createState() => _WarningPulseState();
}

class _WarningPulseState extends State<_WarningPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.055,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _WarningPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) {
      return;
    }
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
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
      builder: (context, child) => Transform.scale(
        scale: widget.enabled ? _scale.value : 1,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.mood,
    required this.title,
    required this.message,
    required this.tone,
  });

  final PlantMood mood;
  final String title;
  final String message;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconForMood(mood), color: tone.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tone.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(color: tone.text.withValues(alpha: 0.86)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForMood(PlantMood mood) {
    switch (mood) {
      case PlantMood.thriving:
        return Icons.verified_rounded;
      case PlantMood.ok:
        return Icons.info_outline;
      case PlantMood.thirsty:
        return Icons.water_drop;
      case PlantMood.dark:
        return Icons.wb_shade;
      case PlantMood.stressed:
        return Icons.warning_amber;
      case PlantMood.unknown:
        return Icons.sensors_off;
    }
  }
}

class _SensorPanel extends StatelessWidget {
  const _SensorPanel({
    required this.reading,
    required this.plant,
    required this.compact,
  });

  final PlantReading? reading;
  final Plant? plant;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final moisture = reading?.moisture;
    final lux = reading?.lux;
    final moistureTarget =
        plant?.effectiveMoistureOk ?? Plant.defaultMoistureOk;
    final luxLow = plant?.effectiveLuxLow ?? Plant.defaultLuxLow;
    final luxHigh = plant?.effectiveLuxHigh ?? Plant.defaultLuxHigh;
    final luxTarget = (luxLow + luxHigh) / 2;

    final cards = [
      _GaugeCard(
        label: 'Umidita',
        icon: Icons.water_drop_outlined,
        value: moisture == null ? '--' : '${moisture.toStringAsFixed(0)}%',
        targetLabel: 'Target ${moistureTarget.toStringAsFixed(0)}%',
        progress: moisture == null ? 0 : (moisture / 100).clamp(0.0, 1.0),
        deltaLabel: moisture == null
            ? 'Nessun dato'
            : _deltaLabel(moisture - moistureTarget, suffix: '%'),
        compact: compact,
      ),
      _GaugeCard(
        label: 'Luce',
        icon: Icons.wb_sunny_outlined,
        value: lux == null ? '--' : '${lux.toStringAsFixed(0)} lx',
        targetLabel: 'Target ${luxTarget.toStringAsFixed(0)} lx',
        progress: lux == null ? 0 : (lux / (luxHigh * 1.2)).clamp(0.0, 1.0),
        deltaLabel: lux == null
            ? 'Nessun dato'
            : _deltaLabel(lux - luxTarget, suffix: ' lx'),
        compact: compact,
      ),
    ];
    if (compact) {
      return Column(
        children: [cards.first, const SizedBox(height: 10), cards.last],
      );
    }
    return Row(
      children: [
        Expanded(child: cards.first),
        const SizedBox(width: 10),
        Expanded(child: cards.last),
      ],
    );
  }

  String _deltaLabel(double delta, {required String suffix}) {
    if (delta.abs() < 0.5) return 'In target';
    final prefix = delta > 0 ? '+' : '';
    return '$prefix${delta.toStringAsFixed(0)}$suffix vs target';
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.targetLabel,
    required this.progress,
    required this.deltaLabel,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final String value;
  final String targetLabel;
  final double progress;
  final String deltaLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        compact ? 10 : 12,
        12,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1DBD1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF323741)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF323741),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF20252D),
              fontWeight: FontWeight.w700,
              fontSize: compact ? 22 : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            targetLabel,
            style: const TextStyle(color: Color(0xFF666A73), fontSize: 12),
          ),
          SizedBox(height: compact ? 8 : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE6E1D7),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF5F718D),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            deltaLabel,
            style: const TextStyle(color: Color(0xFF545965), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onOpenChat,
    required this.onRefresh,
    required this.compact,
  });

  final VoidCallback onOpenChat;
  final VoidCallback onRefresh;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionTile(
        icon: Icons.water_drop,
        label: 'Irrigato ora',
        compact: compact,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Evento salvato nella timeline locale.'),
            ),
          );
        },
      ),
      _ActionTile(
        icon: Icons.forum_outlined,
        label: 'Apri chat',
        compact: compact,
        onTap: onOpenChat,
      ),
      _ActionTile(
        icon: Icons.sync,
        label: 'Risincronizza',
        compact: compact,
        onTap: onRefresh,
      ),
    ];
    if (compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions
            .map(
              (tile) => SizedBox(
                width: (MediaQuery.sizeOf(context).width - 40) / 2,
                child: tile,
              ),
            )
            .toList(growable: false),
      );
    }
    return Row(
      children: [
        Expanded(child: actions[0]),
        const SizedBox(width: 8),
        Expanded(child: actions[1]),
        const SizedBox(width: 8),
        Expanded(child: actions[2]),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 10 : 12,
          horizontal: 10,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFEFEAE2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDD6CB)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF2B3038)),
            SizedBox(height: compact ? 4 : 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B3038),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.points,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final List<PlantReading> points;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final moisture = points
        .map((e) => e.moisture)
        .toList(growable: false)
        .reversed
        .toList();
    final lux = points
        .map((e) => e.lux)
        .toList(growable: false)
        .reversed
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F2),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE1DBD1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF232931),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF666B76)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: compact ? 158 : 94,
            child: compact
                ? Column(
                    children: [
                      Expanded(
                        child: _Sparkline(
                          points: moisture,
                          color: const Color(0xFF5D7895),
                          fillColor: const Color(0x665D7895),
                          label: 'Umidita',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _Sparkline(
                          points: lux,
                          color: const Color(0xFFB37A2E),
                          fillColor: const Color(0x66B37A2E),
                          label: 'Luce',
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _Sparkline(
                          points: moisture,
                          color: const Color(0xFF5D7895),
                          fillColor: const Color(0x665D7895),
                          label: 'Umidita',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Sparkline(
                          points: lux,
                          color: const Color(0xFFB37A2E),
                          fillColor: const Color(0x66B37A2E),
                          label: 'Luce',
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({
    required this.points,
    required this.color,
    required this.fillColor,
    required this.label,
  });

  final List<double> points;
  final Color color;
  final Color fillColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF5D6270),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: CustomPaint(
              painter: _SparklinePainter(
                points: points,
                lineColor: color,
                fillColor: fillColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> points;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final maxY = points.reduce(math.max);
    final minY = points.reduce(math.min);
    final span = math.max(maxY - minY, 0.001);
    final path = Path();
    final fill = Path();

    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final normalized = (points[i] - minY) / span;
      final y = size.height - normalized * (size.height - 2);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
      if (i == points.length - 1) {
        fill.lineTo(x, size.height);
        fill.close();
      }
    }

    canvas.drawPath(
      fill,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.readings, required this.textTheme});

  final List<PlantReading> readings;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F2),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE1DBD1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Timeline eventi',
            style: textTheme.titleMedium?.copyWith(
              color: const Color(0xFF232931),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (readings.isEmpty)
            Text(
              'Nessun evento recente. Appena arrivano dati li vedrai qui.',
              style: textTheme.bodySmall?.copyWith(
                color: const Color(0xFF656A74),
              ),
            )
          else
            ...readings.map((reading) => _TimelineRow(reading: reading)),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.reading});

  final PlantReading reading;
  static final DateFormat _formatter = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF6A7388),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_formatter.format(reading.createdAt)}  ·  Umidita ${reading.moisture.toStringAsFixed(0)}% · Luce ${reading.lux.toStringAsFixed(0)} lx',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF3F4450)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0EB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0DAD0)),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2E3DA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD79A77)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Color(0xFF8F4C2F), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connessione instabile: alcuni dati potrebbero non essere aggiornati.',
              style: TextStyle(
                color: Color(0xFF6B3924),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionReveal extends StatefulWidget {
  const _SectionReveal({
    required this.child,
    required this.delayMs,
    required this.urgent,
  });

  final Widget child;
  final int delayMs;
  final bool urgent;

  @override
  State<_SectionReveal> createState() => _SectionRevealState();
}

class _SectionRevealState extends State<_SectionReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final opacityDuration = Duration(milliseconds: widget.urgent ? 200 : 320);
    final slideDuration = Duration(milliseconds: widget.urgent ? 240 : 380);
    final curve = widget.urgent ? Curves.easeOutQuad : Curves.easeOutCubic;
    final initialOffset = widget.urgent
        ? const Offset(0, 0.02)
        : const Offset(0, 0.04);

    return AnimatedOpacity(
      duration: opacityDuration,
      curve: curve,
      opacity: _visible ? 1 : 0,
      child: AnimatedSlide(
        duration: slideDuration,
        curve: curve,
        offset: _visible ? Offset.zero : initialOffset,
        child: widget.child,
      ),
    );
  }
}

class _StatusTone {
  const _StatusTone({
    required this.surface,
    required this.accent,
    required this.text,
  });

  final Color surface;
  final Color accent;
  final Color text;
}
