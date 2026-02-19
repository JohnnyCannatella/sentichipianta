import 'package:flutter_test/flutter_test.dart';
import 'package:sentichipianta/domain/adaptive_thresholds.dart';
import 'package:sentichipianta/models/plant.dart';
import 'package:sentichipianta/models/plant_reading.dart';

void main() {
  group('AdaptiveThresholdCalculator', () {
    test('returns base thresholds when history is short', () {
      final calc = AdaptiveThresholdCalculator();
      final plant = const Plant(
        id: '1',
        name: 'Pepe',
        personality: 'test',
        plantType: PlantType.peperoncino,
      );

      final result = calc.fromReadings(
        plant: plant,
        readings: [
          PlantReading(
            id: 1,
            createdAt: DateTime(2026, 2, 17, 10),
            moisture: 40,
            lux: 3000,
          ),
        ],
      );

      expect(result.adapted, isFalse);
      expect(result.moistureOk, plant.effectiveMoistureOk);
    });

    test('adapts thresholds with enough history but keeps ordering', () {
      final calc = AdaptiveThresholdCalculator();
      final plant = const Plant(
        id: '1',
        name: 'Pepe',
        personality: 'test',
        plantType: PlantType.peperoncino,
      );

      final readings = List.generate(36, (index) {
        return PlantReading(
          id: index + 1,
          createdAt: DateTime(2026, 2, 1).add(Duration(hours: index * 6)),
          moisture: 52 - (index * 0.45),
          lux: 2800 + (index * 35),
        );
      });

      final result = calc.fromReadings(plant: plant, readings: readings);

      expect(result.adapted, isTrue);
      expect(result.moistureLow < result.moistureOk, isTrue);
      expect(result.moistureOk < result.moistureHigh, isTrue);
      expect(result.luxLow < result.luxHigh, isTrue);
      expect(result.confidence, greaterThan(0.5));
    });
  });
}
