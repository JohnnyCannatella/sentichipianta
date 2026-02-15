import 'package:flutter/material.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../ui/app_colors.dart';
import '../../widgets/plant_avatar.dart';

class PlantDetailScreen extends StatefulWidget {
  const PlantDetailScreen({super.key, required this.plant});

  final Plant plant;

  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final repository = PlantRepository();
    final interpreter = PlantInterpreter();

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: StreamBuilder<PlantReading?>(
          stream: repository.latestReadingForPlant(plantId: widget.plant.id),
          builder: (context, snapshot) {
            final reading = snapshot.data;
            final insight = interpreter.interpret(reading, plant: widget.plant);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          'My plants',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PlantHero(
                          plant: widget.plant,
                          reading: reading,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AlertCard(message: insight.message),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _StatTile(
                                label: 'Water tank',
                                value: reading == null
                                    ? '--'
                                    : '${reading.moisture.toStringAsFixed(0)}%',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatTile(
                                label: 'Light',
                                value: reading == null
                                    ? '--'
                                    : reading.lux.toStringAsFixed(0),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: _StatTile(label: 'Temp.', value: '--'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Tabs(
                          index: _tabIndex,
                          onChanged: (value) => setState(() => _tabIndex = value),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _tabIndex == 0
                              ? _StatisticsView(reading: reading)
                              : _InfoView(plant: widget.plant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlantHero extends StatelessWidget {
  const _PlantHero({required this.plant, required this.reading});

  final Plant plant;
  final PlantReading? reading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 200,
            child: PlantAvatar(
              plantName: plant.name,
              plantType: plant.plantType,
              size: 200,
              radius: 20,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plant.name,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                '26 weeks',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              _HeroStat(
                value: reading == null
                    ? '--'
                    : '${reading!.moisture.toStringAsFixed(0)}%',
                label: 'Humidity',
              ),
              const SizedBox(height: 12),
              _HeroStat(
                value: reading == null ? '--' : reading!.lux.toStringAsFixed(0),
                label: 'Light',
              ),
              const SizedBox(height: 12),
              const _HeroStat(value: '--', label: 'Next watering'),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: Colors.white),
        ),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleSmall),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Statistics',
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Information',
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : AppColors.textDark,
                ),
          ),
        ),
      ),
    );
  }
}

class _StatisticsView extends StatelessWidget {
  const _StatisticsView({required this.reading});

  final PlantReading? reading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        reading == null
            ? 'Nessun dato disponibile'
            : 'Umidita ${reading!.moisture.toStringAsFixed(0)}% · '
                'Luce ${reading!.lux.toStringAsFixed(0)}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _InfoView extends StatelessWidget {
  const _InfoView({required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Text(
        plant.notes?.isNotEmpty == true
            ? plant.notes!
            : 'Nessuna informazione disponibile.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
