import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../ui/app_colors.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.plant,
  });

  final Plant? plant;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _days = 7;
  bool _criticalOnly = false;

  void _refresh() {
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aggiornato ora')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = PlantRepository();
    final interpreter = PlantInterpreter();

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFC7D3C0), Color(0xFFB6C5AE)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFEDEFE8),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xB2FFFFFF), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _Header(
              plantName: widget.plant?.name,
              onRefresh: _refresh,
              onCopyReport: () async {
                final readings = await repository
                    .readingsSince(
                      since: DateTime.now().subtract(Duration(days: _days)),
                      plantId: widget.plant?.id,
                    )
                    .first;
                final visible = _criticalOnly
                    ? readings
                        .where(
                          (reading) => interpreter.isCritical(
                            reading,
                            plant: widget.plant,
                          ),
                        )
                        .toList()
                    : readings;
                if (visible.isEmpty || !context.mounted) {
                  return;
                }
                final avgMoisture =
                    visible.map((e) => e.moisture).reduce((a, b) => a + b) /
                        visible.length;
                final avgLux =
                    visible.map((e) => e.lux).reduce((a, b) => a + b) /
                        visible.length;

                final text = StringBuffer()
                  ..writeln(
                    'Report ${widget.plant?.name ?? 'tutte le piante'} - ultimi $_days giorni',
                  )
                  ..writeln('Letture: ${visible.length}')
                  ..writeln('Media umidita: ${avgMoisture.toStringAsFixed(1)}%')
                  ..writeln('Media luce: ${avgLux.toStringAsFixed(0)} lx')
                  ..writeln(
                    'Filtro critico: ${_criticalOnly ? 'attivo' : 'disattivo'}',
                  );

                await Clipboard.setData(ClipboardData(text: text.toString()));
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report copiato negli appunti.')),
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(label: '7g', value: 7, current: _days, onTap: _setDays),
                _FilterChip(
                  label: '14g',
                  value: 14,
                  current: _days,
                  onTap: _setDays,
                ),
                _FilterChip(
                  label: '30g',
                  value: 30,
                  current: _days,
                  onTap: _setDays,
                ),
                FilterChip(
                  selected: _criticalOnly,
                  label: const Text('Solo critiche'),
                  onSelected: (value) => setState(() => _criticalOnly = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<PlantReading>>(
                stream: repository.readingsSince(
                  since: DateTime.now().subtract(Duration(days: _days)),
                  plantId: widget.plant?.id,
                ),
                builder: (context, snapshot) {
                  final filtered = snapshot.data ?? const [];
                  final visible = _criticalOnly
                      ? filtered
                          .where(
                            (reading) => interpreter.isCritical(
                              reading,
                              plant: widget.plant,
                            ),
                          )
                          .toList()
                      : filtered;

                  if (visible.isEmpty) {
                    return const _EmptyState();
                  }

                  final avgMoisture =
                      visible.map((e) => e.moisture).reduce((a, b) => a + b) /
                          visible.length;
                  final latest = visible.first;

                  return Column(
                    children: [
                      _SummaryCards(
                        readingsCount: visible.length,
                        avgMoisture: avgMoisture,
                        latestAt: latest.createdAt,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final reading = visible[index];
                            final isCritical = interpreter.isCritical(
                              reading,
                              plant: widget.plant,
                            );

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCritical
                                      ? AppColors.alertBorder
                                      : AppColors.outline,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat(
                                          'dd/MM/yyyy HH:mm',
                                        ).format(reading.createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: const Color(0xFF6E665B),
                                            ),
                                      ),
                                      const Spacer(),
                                      if (isCritical)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.alertBg,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            'Critico',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: AppColors.alertText,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _StatPill(
                                          label: 'Umidita',
                                          value:
                                              '${reading.moisture.toStringAsFixed(0)}%',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _StatPill(
                                          label: 'Luce',
                                          value:
                                              '${reading.lux.toStringAsFixed(0)} lx',
                                        ),
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
                  );
                },
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  void _setDays(int value) {
    setState(() => _days = value);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.plantName,
    required this.onRefresh,
    required this.onCopyReport,
  });

  final String? plantName;
  final VoidCallback onRefresh;
  final VoidCallback onCopyReport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Storico letture',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                plantName == null ? 'Tutte le piante' : 'Pianta: $plantName',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF191D18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderAction(icon: Icons.refresh, tooltip: 'Aggiorna', onTap: onRefresh),
              const SizedBox(width: 6),
              _HeaderAction(
                icon: Icons.copy_all_outlined,
                tooltip: 'Copia report',
                onTap: onCopyReport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: Color(0xFF111612)),
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.readingsCount,
    required this.avgMoisture,
    required this.latestAt,
  });

  final int readingsCount;
  final double avgMoisture;
  final DateTime latestAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Letture',
            value: '$readingsCount',
            icon: Icons.dataset_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: 'Media H2O',
            value: '${avgMoisture.toStringAsFixed(0)}%',
            icon: Icons.water_drop_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: 'Ultima',
            value: DateFormat('HH:mm').format(latestAt),
            icon: Icons.access_time,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

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
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(height: 6),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  final String label;
  final int value;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return InkWell(
      onTap: () => onTap(value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.outline),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? Colors.white : AppColors.textDark,
              ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Text(
          'Nessuna lettura trovata per il filtro selezionato.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
