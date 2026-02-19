import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/predictive_care_engine.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';

class PredictiveCareCard extends StatelessWidget {
  const PredictiveCareCard({
    super.key,
    required this.plant,
    required this.readings,
  });

  final Plant? plant;
  final List<PlantReading> readings;

  @override
  Widget build(BuildContext context) {
    final prediction = PredictiveCareEngine().predict(
      readings: readings,
      plant: plant,
    );

    final urgencyStyle = _urgencyStyle(prediction.urgency);
    final nextWateringText = prediction.nextWateringAt == null
        ? 'Da stimare'
        : DateFormat(
            'EEE dd MMM, HH:mm',
            'it_IT',
          ).format(prediction.nextWateringAt!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: urgencyStyle.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: urgencyStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(urgencyStyle.icon, color: urgencyStyle.border),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Motore predittivo v2.0',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF1E252C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ConfidenceChip(value: prediction.confidence),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            prediction.summary,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF2B3440)),
          ),
          const SizedBox(height: 10),
          _Line(label: 'Irrigazione', value: prediction.wateringAction),
          const SizedBox(height: 6),
          _Line(label: 'Luce', value: prediction.lightAction),
          const SizedBox(height: 6),
          _Line(label: 'Prossima acqua', value: nextWateringText),
          if (prediction.followUpQuestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Se l\'AI ha dubbi, chiedera:',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF29313A),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...prediction.followUpQuestions
                .take(2)
                .map(
                  (question) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '- $question',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF3F4A55),
                      ),
                    ),
                  ),
                ),
          ],
          if (prediction.shouldRequestPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Consiglio: richiedere una foto foglia + terriccio per aumentare precisione.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A2D22),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _UrgencyStyle _urgencyStyle(CareUrgency urgency) {
    switch (urgency) {
      case CareUrgency.now:
        return const _UrgencyStyle(
          icon: Icons.priority_high_rounded,
          surface: Color(0xFFF5E0D7),
          border: Color(0xFFB65A42),
        );
      case CareUrgency.soon:
        return const _UrgencyStyle(
          icon: Icons.schedule_rounded,
          surface: Color(0xFFF4EDD8),
          border: Color(0xFF9E7A31),
        );
      case CareUrgency.monitor:
        return const _UrgencyStyle(
          icon: Icons.check_circle_outline_rounded,
          surface: Color(0xFFE5EEE2),
          border: Color(0xFF4A7652),
        );
    }
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xFF32404A)),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final percentage = (value * 100).round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2B3B48),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Conf. $percentage%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UrgencyStyle {
  const _UrgencyStyle({
    required this.icon,
    required this.surface,
    required this.border,
  });

  final IconData icon;
  final Color surface;
  final Color border;
}
