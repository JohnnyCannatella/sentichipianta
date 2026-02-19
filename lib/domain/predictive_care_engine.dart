import 'adaptive_thresholds.dart';
import '../models/plant.dart';
import '../models/plant_reading.dart';

enum CareUrgency { now, soon, monitor }

class PlantCarePrediction {
  const PlantCarePrediction({
    required this.urgency,
    required this.summary,
    required this.wateringAction,
    required this.lightAction,
    required this.confidence,
    required this.nextWateringAt,
    required this.followUpQuestions,
    required this.shouldRequestPhoto,
  });

  final CareUrgency urgency;
  final String summary;
  final String wateringAction;
  final String lightAction;
  final double confidence;
  final DateTime? nextWateringAt;
  final List<String> followUpQuestions;
  final bool shouldRequestPhoto;

  Map<String, dynamic> toMap() {
    return {
      'urgency': urgency.name,
      'summary': summary,
      'watering_action': wateringAction,
      'light_action': lightAction,
      'confidence': confidence,
      'next_watering_at': nextWateringAt?.toIso8601String(),
      'follow_up_questions': followUpQuestions,
      'should_request_photo': shouldRequestPhoto,
    };
  }
}

class PredictiveCareEngine {
  PlantCarePrediction predict({
    required List<PlantReading> readings,
    Plant? plant,
    DateTime? now,
  }) {
    final sorted = [...readings]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final refTime = now ?? DateTime.now();
    final latest = sorted.isEmpty ? null : sorted.last;
    final adaptive = AdaptiveThresholdCalculator().fromReadings(
      plant: plant,
      readings: sorted,
    );

    if (latest == null) {
      return const PlantCarePrediction(
        urgency: CareUrgency.monitor,
        summary: 'Non ho abbastanza dati per una previsione affidabile.',
        wateringAction: 'Aspetto nuove letture di umidita suolo.',
        lightAction: 'Aspetto nuove letture di luce.',
        confidence: 0.2,
        nextWateringAt: null,
        followUpQuestions: [
          'Quando hai annaffiato l\'ultima volta?',
          'Che volume d\'acqua hai dato?',
        ],
        shouldRequestPhoto: false,
      );
    }

    final moistureLow = adaptive.moistureLow;
    final moistureHigh = adaptive.moistureHigh;
    final luxLow = adaptive.luxLow;
    final luxHigh = adaptive.luxHigh;

    final last24h = sorted
        .where(
          (r) => refTime.difference(r.createdAt) <= const Duration(hours: 24),
        )
        .toList(growable: false);

    final avgLux = _average(last24h.map((r) => r.lux));
    final slopePerHour = _moistureSlopePerHour(sorted);
    final nextWateringAt = _estimateNextWatering(
      latest: latest,
      moistureLow: moistureLow,
      slopePerHour: slopePerHour,
      now: refTime,
    );

    final wateringAction = _wateringAction(
      latest: latest,
      moistureLow: moistureLow,
      moistureHigh: moistureHigh,
      nextWateringAt: nextWateringAt,
    );

    final lightAction = _lightAction(
      avgLux: avgLux,
      luxLow: luxLow,
      luxHigh: luxHigh,
    );

    final followUpQuestions = <String>[];
    if (sorted.length < 8 || adaptive.confidence < 0.55) {
      followUpQuestions.add('Quando hai annaffiato l\'ultima volta?');
    }
    if (nextWateringAt == null && latest.moisture > moistureLow) {
      followUpQuestions.add('Il terriccio drena bene o resta bagnato a lungo?');
    }
    if (avgLux > 0 && (avgLux < luxLow * 0.7 || avgLux > luxHigh * 1.2)) {
      followUpQuestions.add(
        'La posizione attuale riceve sole diretto nelle ore centrali?',
      );
    }

    final shouldRequestPhoto =
        latest.moisture > moistureHigh || (avgLux > 0 && avgLux < luxLow * 0.5);

    final confidence = _confidence(
      totalReadings: sorted.length,
      last24hReadings: last24h.length,
      hasSlope: slopePerHour != null,
      hasLux: avgLux > 0,
    );

    final urgency = _urgency(
      latest: latest,
      moistureLow: moistureLow,
      moistureHigh: moistureHigh,
      avgLux: avgLux,
      luxLow: luxLow,
      nextWateringAt: nextWateringAt,
    );

    final summary = _summary(
      urgency: urgency,
      nextWateringAt: nextWateringAt,
      confidence: confidence,
      shouldRequestPhoto: shouldRequestPhoto,
    );

    return PlantCarePrediction(
      urgency: urgency,
      summary: summary,
      wateringAction: wateringAction,
      lightAction: lightAction,
      confidence: confidence,
      nextWateringAt: nextWateringAt,
      followUpQuestions: followUpQuestions,
      shouldRequestPhoto: shouldRequestPhoto,
    );
  }

  CareUrgency _urgency({
    required PlantReading latest,
    required double moistureLow,
    required double moistureHigh,
    required double avgLux,
    required double luxLow,
    required DateTime? nextWateringAt,
  }) {
    if (latest.moisture <= moistureLow || latest.moisture >= moistureHigh) {
      return CareUrgency.now;
    }
    if (avgLux > 0 && avgLux < luxLow * 0.7) {
      return CareUrgency.soon;
    }
    if (nextWateringAt != null &&
        nextWateringAt.isBefore(
          DateTime.now().add(const Duration(hours: 12)),
        )) {
      return CareUrgency.soon;
    }
    return CareUrgency.monitor;
  }

  String _summary({
    required CareUrgency urgency,
    required DateTime? nextWateringAt,
    required double confidence,
    required bool shouldRequestPhoto,
  }) {
    switch (urgency) {
      case CareUrgency.now:
        return 'Serve un intervento adesso: umidita suolo fuori zona sicura.';
      case CareUrgency.soon:
        final when = nextWateringAt == null
            ? 'nelle prossime ore'
            : _relativeEta(nextWateringAt.difference(DateTime.now()));
        return 'Trend da monitorare: probabile intervento $when.';
      case CareUrgency.monitor:
        final confidenceLabel = confidence >= 0.7 ? 'alta' : 'media';
        final photoHint = shouldRequestPhoto
            ? ' Meglio aggiungere una foto per confermare lo stato visivo.'
            : '';
        return 'Condizione stabile, confidenza $confidenceLabel.$photoHint';
    }
  }

  String _wateringAction({
    required PlantReading latest,
    required double moistureLow,
    required double moistureHigh,
    required DateTime? nextWateringAt,
  }) {
    if (latest.moisture <= moistureLow) {
      return 'Annaffia ora in modo graduale e ricontrolla umidita tra 3 ore.';
    }
    if (latest.moisture >= moistureHigh) {
      return 'Non annaffiare: suolo troppo umido, attendi asciugatura parziale.';
    }
    if (nextWateringAt != null) {
      return 'Prossima irrigazione stimata ${_relativeEta(nextWateringAt.difference(DateTime.now()))}.';
    }
    return 'Mantieni monitoraggio ogni 4-6 ore prima di irrigare.';
  }

  String _lightAction({
    required double avgLux,
    required double luxLow,
    required double luxHigh,
  }) {
    if (avgLux <= 0) {
      return 'Dati luce insufficienti: controlla il sensore BH1750FVI.';
    }
    if (avgLux < luxLow) {
      return 'Sposta la pianta verso una zona piu luminosa per 2-3 ore al giorno.';
    }
    if (avgLux > luxHigh) {
      return 'Riduci esposizione diretta nelle ore centrali per evitare stress.';
    }
    return 'Esposizione luce coerente con il profilo attuale.';
  }

  DateTime? _estimateNextWatering({
    required PlantReading latest,
    required double moistureLow,
    required double? slopePerHour,
    required DateTime now,
  }) {
    if (latest.moisture <= moistureLow) {
      return now;
    }
    if (slopePerHour == null || slopePerHour >= -0.02) {
      return null;
    }

    final delta = latest.moisture - moistureLow;
    final hours = delta / slopePerHour.abs();
    if (hours.isNaN || !hours.isFinite || hours <= 0) {
      return null;
    }

    final capped = hours.clamp(1, 96).round();
    return now.add(Duration(hours: capped));
  }

  double _confidence({
    required int totalReadings,
    required int last24hReadings,
    required bool hasSlope,
    required bool hasLux,
  }) {
    var score = 0.25;
    score += (totalReadings / 20).clamp(0, 0.3);
    score += (last24hReadings / 12).clamp(0, 0.25);
    if (hasSlope) score += 0.1;
    if (hasLux) score += 0.1;
    return score.clamp(0.15, 0.95);
  }

  double _average(Iterable<double> values) {
    final list = values.where((v) => v.isFinite).toList(growable: false);
    if (list.isEmpty) {
      return 0;
    }
    final sum = list.fold<double>(0, (acc, value) => acc + value);
    return sum / list.length;
  }

  double? _moistureSlopePerHour(List<PlantReading> sorted) {
    if (sorted.length < 3) {
      return null;
    }

    final sample = sorted.length > 24
        ? sorted.sublist(sorted.length - 24)
        : sorted;
    final first = sample.first;
    final last = sample.last;
    final elapsedHours =
        last.createdAt.difference(first.createdAt).inMinutes / 60.0;

    if (elapsedHours <= 0) {
      return null;
    }

    return (last.moisture - first.moisture) / elapsedHours;
  }

  String _relativeEta(Duration duration) {
    if (duration.inHours <= 1) {
      return 'entro 1 ora';
    }
    if (duration.inHours < 24) {
      return 'tra ${duration.inHours} ore';
    }
    final days = (duration.inHours / 24).ceil();
    return 'tra $days giorni';
  }
}
