import '../models/plant.dart';
import '../models/plant_reading.dart';

class AdaptiveThresholds {
  const AdaptiveThresholds({
    required this.moistureLow,
    required this.moistureOk,
    required this.moistureHigh,
    required this.luxLow,
    required this.luxHigh,
    required this.confidence,
    required this.adapted,
  });

  final double moistureLow;
  final double moistureOk;
  final double moistureHigh;
  final double luxLow;
  final double luxHigh;
  final double confidence;
  final bool adapted;

  Map<String, dynamic> toMap() {
    return {
      'moisture_low': moistureLow,
      'moisture_ok': moistureOk,
      'moisture_high': moistureHigh,
      'lux_low': luxLow,
      'lux_high': luxHigh,
      'adaptive_confidence': confidence,
      'adaptive_enabled': adapted,
    };
  }
}

class AdaptiveThresholdCalculator {
  AdaptiveThresholds fromReadings({
    required Plant? plant,
    required List<PlantReading> readings,
  }) {
    final baseLow = plant?.effectiveMoistureLow ?? Plant.defaultMoistureLow;
    final baseOk = plant?.effectiveMoistureOk ?? Plant.defaultMoistureOk;
    final baseHigh = plant?.effectiveMoistureHigh ?? Plant.defaultMoistureHigh;
    final baseLuxLow = plant?.effectiveLuxLow ?? Plant.defaultLuxLow;
    final baseLuxHigh = plant?.effectiveLuxHigh ?? Plant.defaultLuxHigh;

    final sample = [...readings]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final capped = sample.length > 120
        ? sample.sublist(sample.length - 120)
        : sample;

    if (capped.length < 24) {
      return AdaptiveThresholds(
        moistureLow: baseLow,
        moistureOk: baseOk,
        moistureHigh: baseHigh,
        luxLow: baseLuxLow,
        luxHigh: baseLuxHigh,
        confidence: _confidence(capped.length),
        adapted: false,
      );
    }

    final moistureValues = capped
        .map((r) => r.moisture)
        .toList(growable: false);
    final luxValues = capped.map((r) => r.lux).toList(growable: false);

    final moistureMedian = _percentile(moistureValues, 0.5);
    final luxMedian = _percentile(luxValues, 0.5);

    final moistureShift = (moistureMedian - baseOk).clamp(-8.0, 8.0);
    final moistureLow = (baseLow + moistureShift * 0.8).clamp(5.0, 85.0);
    final moistureOk = (baseOk + moistureShift).clamp(8.0, 90.0);
    final moistureHigh = (baseHigh + moistureShift * 0.8).clamp(15.0, 95.0);

    final baseLuxMid = (baseLuxLow + baseLuxHigh) / 2;
    final luxRange = (baseLuxHigh - baseLuxLow).abs();
    final maxLuxShift = (luxRange * 0.2).clamp(500.0, 8000.0);
    final luxShift = (luxMedian - baseLuxMid).clamp(-maxLuxShift, maxLuxShift);
    final luxLow = (baseLuxLow + luxShift * 0.65).clamp(150.0, 60000.0);
    final luxHigh = (baseLuxHigh + luxShift * 0.65).clamp(500.0, 90000.0);

    final ordered = _ensureOrder(
      moistureLow: moistureLow,
      moistureOk: moistureOk,
      moistureHigh: moistureHigh,
      luxLow: luxLow,
      luxHigh: luxHigh,
    );

    return AdaptiveThresholds(
      moistureLow: ordered.moistureLow,
      moistureOk: ordered.moistureOk,
      moistureHigh: ordered.moistureHigh,
      luxLow: ordered.luxLow,
      luxHigh: ordered.luxHigh,
      confidence: _confidence(capped.length),
      adapted: true,
    );
  }

  _OrderedThresholds _ensureOrder({
    required double moistureLow,
    required double moistureOk,
    required double moistureHigh,
    required double luxLow,
    required double luxHigh,
  }) {
    var low = moistureLow;
    var ok = moistureOk;
    var high = moistureHigh;

    if (low >= ok) {
      ok = low + 5;
    }
    if (ok >= high) {
      high = ok + 7;
    }
    if (high > 95) {
      high = 95;
      if (ok >= high) ok = high - 5;
      if (low >= ok) low = ok - 5;
    }

    var lLow = luxLow;
    var lHigh = luxHigh;
    if (lLow >= lHigh) {
      lHigh = lLow + 1200;
    }

    return _OrderedThresholds(
      moistureLow: low.clamp(5.0, 85.0),
      moistureOk: ok.clamp(8.0, 90.0),
      moistureHigh: high.clamp(15.0, 95.0),
      luxLow: lLow.clamp(150.0, 60000.0),
      luxHigh: lHigh.clamp(500.0, 90000.0),
    );
  }

  double _confidence(int count) {
    return (0.35 + (count / 120)).clamp(0.35, 0.95);
  }

  double _percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    if (sorted.length == 1) return sorted.first;
    final position = (sorted.length - 1) * p;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}

class _OrderedThresholds {
  const _OrderedThresholds({
    required this.moistureLow,
    required this.moistureOk,
    required this.moistureHigh,
    required this.luxLow,
    required this.luxHigh,
  });

  final double moistureLow;
  final double moistureOk;
  final double moistureHigh;
  final double luxLow;
  final double luxHigh;
}
