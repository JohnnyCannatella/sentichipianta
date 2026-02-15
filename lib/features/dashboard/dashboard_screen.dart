import 'package:flutter/material.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
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
        builder: (context, snapshot) {
          final reading = snapshot.data;
          final insight = interpreter.interpret(reading, plant: selectedPlant);

          return _DashboardBody(
            plants: plants,
            selectedPlant: selectedPlant,
            onSelectPlant: onSelectPlant,
            onRefresh: onRefresh,
            reading: reading,
            insight: insight,
          );
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.plants,
    required this.selectedPlant,
    required this.onSelectPlant,
    required this.onRefresh,
    required this.reading,
    required this.insight,
  });

  final List<Plant> plants;
  final Plant? selectedPlant;
  final ValueChanged<Plant?> onSelectPlant;
  final VoidCallback onRefresh;
  final PlantReading? reading;
  final PlantInsight insight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC7D3C0), Color(0xFFB6C5AE)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          children: [
            _TopBar(
              onSelectPlant: onSelectPlant,
              plants: plants,
              selectedPlant: selectedPlant,
              onRefresh: () {
                onRefresh();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aggiornato ora')),
                );
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: _HeroCard(
                          plantName: selectedPlant?.name ?? 'Senti Chi Pianta',
                          selectedPlant: selectedPlant,
                          personality: selectedPlant?.personality,
                          reading: reading,
                          insight: insight,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.plantName,
    required this.selectedPlant,
    required this.personality,
    required this.reading,
    required this.insight,
  });

  final String plantName;
  final Plant? selectedPlant;
  final String? personality;
  final PlantReading? reading;
  final PlantInsight insight;

  @override
  Widget build(BuildContext context) {
    final moisture = reading?.moisture;
    final lux = reading?.lux;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFE8),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: const Color(0xB2FFFFFF), width: 1.5),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 350,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 48,
                    child: _HeroImage(
                      selectedPlant: selectedPlant,
                      reading: reading,
                      plantName: plantName,
                      insight: insight,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    child: _MetricPill(
                      icon: Icons.water_drop_outlined,
                      label: 'Umidita',
                      value: moisture == null
                          ? '--'
                          : '${moisture.toStringAsFixed(0)}%',
                      progress:
                          moisture == null ? 0 : (moisture / 100).clamp(0.0, 1.0),
                    ),
                  ),
                  Positioned(
                    top: 142,
                    left: 2,
                    child: _MetricPill(
                      icon: Icons.eco_outlined,
                      label: 'Stato',
                      value: insight.title,
                      progress: _moodProgress(insight.mood),
                    ),
                  ),
                  Positioned(
                    top: 142,
                    right: 2,
                    child: _MetricPill(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Luce',
                      value: lux == null ? '--' : '${lux.toStringAsFixed(0)} lx',
                      progress: lux == null ? 0 : (lux / 20000).clamp(0.0, 1.0),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _BottomInfoPanel(
              plantName: plantName,
              message: _dailyBubbleMessage(insight),
            ),
          ],
        ),
      ),
    );
  }

  double _moodProgress(PlantMood mood) {
    switch (mood) {
      case PlantMood.thriving:
        return 1;
      case PlantMood.ok:
        return 0.75;
      case PlantMood.unknown:
        return 0.55;
      case PlantMood.dark:
      case PlantMood.thirsty:
        return 0.35;
      case PlantMood.stressed:
        return 0.2;
    }
  }

  String _dailyBubbleMessage(PlantInsight insight) {
    final today = DateTime.now();
    final seed = today.year + today.month + today.day + insight.mood.index;
    const thrivingMessages = [
      'Oggi sto bene, non preoccuparti.',
      'Mi sento in forma, continua cosi.',
      'Giornata ottima: acqua e luce in equilibrio.',
    ];
    const okMessages = [
      'Sto bene, controllami piu tardi.',
      'Per ora tutto regolare.',
      'Sono stabile e tranquilla.',
    ];
    const thirstyMessages = [
      'Mi dai un po\' d\'acqua?',
      'La terra e secca, ho sete.',
      'Serve irrigazione nelle prossime ore.',
    ];
    const darkMessages = [
      'Qui c\'e poca luce oggi.',
      'Spostami in una zona piu luminosa.',
      'Ho bisogno di piu luce per stare bene.',
    ];
    const stressedMessages = [
      'Sono un po\' sotto stress, aiutami.',
      'Condizioni troppo forti, riduciamole.',
      'Ho bisogno di una mano per recuperare.',
    ];
    const unknownMessages = [
      'Appena arrivano letture ti aggiorno.',
      'Sto aspettando i primi dati dai sensori.',
      'Connetti i dati e ti parlo meglio.',
    ];

    List<String> source;
    switch (insight.mood) {
      case PlantMood.thriving:
        source = thrivingMessages;
      case PlantMood.ok:
        source = okMessages;
      case PlantMood.thirsty:
        source = thirstyMessages;
      case PlantMood.dark:
        source = darkMessages;
      case PlantMood.stressed:
        source = stressedMessages;
      case PlantMood.unknown:
        source = unknownMessages;
    }
    return source[seed % source.length];
  }
}

class _HeroImage extends StatefulWidget {
  const _HeroImage({
    required this.selectedPlant,
    required this.reading,
    required this.plantName,
    required this.insight,
  });

  final Plant? selectedPlant;
  final PlantReading? reading;
  final String plantName;
  final PlantInsight insight;

  @override
  State<_HeroImage> createState() => _HeroImageState();
}

class _HeroImageState extends State<_HeroImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: _durationForMood(widget.insight.mood),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(covariant _HeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insight.mood != widget.insight.mood) {
      _pulseController.duration = _durationForMood(widget.insight.mood);
      _pulseController.forward(from: 0);
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxScale = _maxScaleForMood(widget.insight.mood);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        final scale = 1.0 + (maxScale - 1.0) * t;
        return Transform.scale(scale: scale, child: child);
      },
      child: SizedBox(
        width: 266,
        height: 268,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: 10,
              child: Container(
                width: 196,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            PlantAvatar(
              plantName: widget.plantName,
              plantType: widget.selectedPlant?.plantType,
              size: 250,
              radius: 32,
            ),
            PlantStateArt(
              plant: widget.selectedPlant,
              reading: widget.reading,
              size: 250,
              radius: 32,
            ),
          ],
        ),
      ),
    );
  }

  Duration _durationForMood(PlantMood mood) {
    switch (mood) {
      case PlantMood.stressed:
      case PlantMood.thirsty:
        return const Duration(milliseconds: 1250);
      case PlantMood.dark:
        return const Duration(milliseconds: 1450);
      case PlantMood.thriving:
        return const Duration(milliseconds: 1900);
      case PlantMood.ok:
      case PlantMood.unknown:
        return const Duration(milliseconds: 1700);
    }
  }

  double _maxScaleForMood(PlantMood mood) {
    switch (mood) {
      case PlantMood.stressed:
      case PlantMood.thirsty:
        return 1.035;
      case PlantMood.dark:
        return 1.026;
      case PlantMood.thriving:
        return 1.02;
      case PlantMood.ok:
      case PlantMood.unknown:
        return 1.016;
    }
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x9A7D8C79),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xD4E3EBD8)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFE8F4E6), size: 18),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFE8F4E6),
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0x66FFFFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF87E86C)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomInfoPanel extends StatelessWidget {
  const _BottomInfoPanel({
    required this.plantName,
    required this.message,
  });

  final String plantName;
  final String message;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xDDF6F7F1),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xE6D9E0D3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plantName,
            style: style.headlineSmall?.copyWith(
              color: const Color(0xFF1A2318),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.bodyMedium?.copyWith(color: const Color(0xFF3F4D3B)),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onSelectPlant,
    required this.plants,
    required this.selectedPlant,
    required this.onRefresh,
  });

  final ValueChanged<Plant?> onSelectPlant;
  final List<Plant> plants;
  final Plant? selectedPlant;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Senti Chi Pianta',
            style: TextStyle(
              color: Color(0xFF1E2D1D),
              fontWeight: FontWeight.w700,
              fontSize: 24,
            ),
          ),
        ),
        _TopControlsPill(
          hasManyPlants: plants.length > 1,
          onPick: () => PlantPickerSheet.show(
            context,
            plants: plants,
            selectedId: selectedPlant?.id,
            onChanged: onSelectPlant,
          ),
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}

class _TopControlsPill extends StatelessWidget {
  const _TopControlsPill({
    required this.hasManyPlants,
    required this.onPick,
    required this.onRefresh,
  });

  final bool hasManyPlants;
  final VoidCallback onPick;
  final VoidCallback onRefresh;

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
          if (hasManyPlants)
            _TopPillAction(
              icon: Icons.eco_outlined,
              selected: true,
              onTap: onPick,
              tooltip: 'Seleziona pianta',
            ),
          if (hasManyPlants) const SizedBox(width: 6),
          _TopPillAction(
            icon: Icons.refresh,
            selected: !hasManyPlants,
            onTap: onRefresh,
            tooltip: 'Aggiorna',
          ),
        ],
      ),
    );
  }
}

class _TopPillAction extends StatelessWidget {
  const _TopPillAction({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: selected ? const Color(0xFF111612) : Colors.white,
          ),
        ),
      ),
    );
  }
}
