import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../domain/predictive_care_engine.dart';
import '../../models/ai_decision.dart';
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
            final screenHeight = MediaQuery.sizeOf(context).height;
            final tabContentHeight = (screenHeight * 0.2).clamp(120.0, 220.0);

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
                          style: Theme.of(context).textTheme.titleMedium
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
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _AlertCard(message: insight.message),
                        const SizedBox(height: 16),
                        StreamBuilder<List<PlantReading>>(
                          stream: repository.recentReadings(
                            limit: 48,
                            plantId: widget.plant.id,
                          ),
                          builder: (context, historySnapshot) {
                            final history =
                                historySnapshot.data ?? const <PlantReading>[];
                            final prediction = PredictiveCareEngine().predict(
                              readings: history,
                              plant: widget.plant,
                            );
                            return _AutomationPanel(
                              latestReading: reading,
                              plant: widget.plant,
                              prediction: prediction,
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<List<AiDecision>>(
                          stream: repository.recentAiDecisions(
                            plantId: widget.plant.id,
                            limit: 8,
                          ),
                          builder: (context, decisionSnapshot) {
                            final decisions =
                                decisionSnapshot.data ?? const <AiDecision>[];
                            return _AiDecisionsPanel(
                              decisions: decisions,
                              onSetOutcome: (decision, outcome) async {
                                await repository.updateAiDecisionOutcome(
                                  decisionId: decision.id,
                                  outcome: outcome,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Esito aggiornato.'),
                                  ),
                                );
                              },
                            );
                          },
                        ),
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
                          onChanged: (value) =>
                              setState(() => _tabIndex = value),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: tabContentHeight,
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
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                '26 weeks',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
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
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.white70),
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
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _AutomationPanel extends StatelessWidget {
  const _AutomationPanel({
    required this.latestReading,
    required this.plant,
    required this.prediction,
  });

  final PlantReading? latestReading;
  final Plant plant;
  final PlantCarePrediction prediction;

  @override
  Widget build(BuildContext context) {
    final nextCheck = DateFormat(
      'HH:mm',
    ).format(DateTime.now().add(const Duration(minutes: 6)));
    final nextWatering = prediction.nextWateringAt == null
        ? 'Da stimare'
        : DateFormat(
            'EEE dd MMM HH:mm',
            'it_IT',
          ).format(prediction.nextWateringAt!);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3DBCF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Color(0xFF3E434D)),
              const SizedBox(width: 6),
              Text(
                'Automazione routine',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF2F333B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _UrgencyBadge(urgency: prediction.urgency),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RoutineMetricChip(
                  label: 'Acqua',
                  value: latestReading == null
                      ? 'In attesa'
                      : '${latestReading!.moisture.toStringAsFixed(0)}%',
                  alert:
                      latestReading != null &&
                      (latestReading!.moisture < plant.effectiveMoistureLow ||
                          latestReading!.moisture >
                              plant.effectiveMoistureHigh),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _RoutineMetricChip(
                  label: 'Luce',
                  value: latestReading == null
                      ? 'In attesa'
                      : '${latestReading!.lux.toStringAsFixed(0)} lx',
                  alert:
                      latestReading != null &&
                      (latestReading!.lux < plant.effectiveLuxLow ||
                          latestReading!.lux > plant.effectiveLuxHigh),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Check: $nextCheck',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF646058),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Acqua: $nextWatering',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF646058),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutineMetricChip extends StatelessWidget {
  const _RoutineMetricChip({
    required this.label,
    required this.value,
    required this.alert,
  });

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: alert ? const Color(0xFFF3E5DF) : const Color(0xFFE8EEE8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alert ? const Color(0xFFE0BFB2) : const Color(0xFFC9D4C8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alert ? const Color(0xFF6A4033) : const Color(0xFF2F4A33),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: alert ? const Color(0xFF6A4033) : const Color(0xFF2F4A33),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _UrgencyBadge extends StatelessWidget {
  const _UrgencyBadge({required this.urgency});

  final CareUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (urgency) {
      CareUrgency.now => ('Ora', const Color(0xFF8D4737)),
      CareUrgency.soon => ('Presto', const Color(0xFF8F6A22)),
      CareUrgency.monitor => ('Stabile', const Color(0xFF3C6945)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AiDecisionsPanel extends StatelessWidget {
  const _AiDecisionsPanel({
    required this.decisions,
    required this.onSetOutcome,
  });

  final List<AiDecision> decisions;
  final Future<void> Function(AiDecision decision, String outcome) onSetOutcome;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dueFollowUps = decisions
        .where(
          (d) =>
              d.outcome == null &&
              d.followUpDueAt != null &&
              d.followUpDueAt!.isBefore(now),
        )
        .length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                'Storico decisioni AI',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (dueFollowUps > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5DF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0BFB2)),
              ),
              child: Text(
                dueFollowUps == 1
                    ? 'Follow-up in scadenza: aggiorna l\'esito dell\'ultima decisione.'
                    : 'Follow-up in scadenza: aggiorna $dueFollowUps esiti per migliorare l\'AI.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF6A4033),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (decisions.isEmpty)
            Text(
              'Nessuna decisione salvata finora.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            )
          else
            SizedBox(
              height: 172,
              child: ListView.separated(
                itemCount: decisions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = decisions[index];
                  final reply = (item.recommendation['reply'] as String? ?? '')
                      .split('\n')
                      .first
                      .trim();
                  final confidenceText = item.confidence == null
                      ? 'n/a'
                      : '${(item.confidence! * 100).round()}%';
                  final createdAt = DateFormat(
                    'dd/MM HH:mm',
                  ).format(item.createdAt.toLocal());
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F4EE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE7DFD1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              createdAt,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                            const Spacer(),
                            Text(
                              'Conf. $confidenceText',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reply.isEmpty ? 'Decisione senza testo.' : reply,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _OutcomeButton(
                              label: 'Migliorata',
                              selected: item.outcome == 'improved',
                              onTap: () => onSetOutcome(item, 'improved'),
                            ),
                            const SizedBox(width: 6),
                            _OutcomeButton(
                              label: 'Uguale',
                              selected: item.outcome == 'same',
                              onTap: () => onSetOutcome(item, 'same'),
                            ),
                            const SizedBox(width: 6),
                            _OutcomeButton(
                              label: 'Peggiorata',
                              selected: item.outcome == 'worse',
                              onTap: () => onSetOutcome(item, 'worse'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OutcomeButton extends StatelessWidget {
  const _OutcomeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFD8D2C6),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? AppColors.primaryDark : AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
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
