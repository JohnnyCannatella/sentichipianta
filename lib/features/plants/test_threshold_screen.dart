import 'package:flutter/material.dart';

import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../ui/app_colors.dart';

class TestThresholdScreen extends StatefulWidget {
  const TestThresholdScreen({super.key, required this.plant});

  final Plant plant;

  @override
  State<TestThresholdScreen> createState() => _TestThresholdScreenState();
}

class _TestThresholdScreenState extends State<TestThresholdScreen> {
  double _moisture = 30;
  double _lux = 400;

  @override
  void initState() {
    super.initState();
    _moisture = widget.plant.effectiveMoistureOk;
    _lux = widget.plant.effectiveLuxLow + 200;
  }

  @override
  Widget build(BuildContext context) {
    final interpreter = PlantInterpreter();
    final reading = PlantReading(
      id: 0,
      createdAt: DateTime.now(),
      moisture: _moisture,
      lux: _lux,
      plantId: widget.plant.id,
    );
    final insight = interpreter.interpret(reading, plant: widget.plant);
    final isCritical = interpreter.isCritical(reading, plant: widget.plant);

    return Scaffold(
      appBar: AppBar(
        title: Text('Test soglie · ${widget.plant.name}'),
        backgroundColor: AppColors.background,
      ),
      body: Container(
        color: AppColors.background,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Simula i valori per vedere come reagisce la pianta.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            _InsightCard(insight: insight, isCritical: isCritical),
            const SizedBox(height: 20),
            Text('Umidita (${_moisture.toStringAsFixed(0)}%)'),
            Slider(
              value: _moisture,
              min: 0,
              max: 100,
              divisions: 100,
              label: _moisture.toStringAsFixed(0),
              onChanged: (value) => setState(() => _moisture = value),
            ),
            const SizedBox(height: 12),
            Text('Luce (${_lux.toStringAsFixed(0)} lx)'),
            Slider(
              value: _lux,
              min: 0,
              max: 20000,
              divisions: 100,
              label: _lux.toStringAsFixed(0),
              onChanged: (value) => setState(() => _lux = value),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.isCritical});

  final PlantInsight insight;
  final bool isCritical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCritical ? AppColors.alertBg : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCritical ? AppColors.alertBorder : AppColors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            insight.message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
