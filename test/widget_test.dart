import 'package:flutter_test/flutter_test.dart';

import 'package:sentichipianta/domain/predictive_care_engine.dart';
import 'package:sentichipianta/models/plant.dart';
import 'package:sentichipianta/models/plant_reading.dart';

void main() {
  group('PredictiveCareEngine', () {
    test('signals immediate watering when moisture is under threshold', () {
      final engine = PredictiveCareEngine();
      final now = DateTime(2026, 2, 17, 10, 0);
      final readings = [
        PlantReading(
          id: 1,
          createdAt: now.subtract(const Duration(hours: 2)),
          moisture: 18,
          lux: 200,
        ),
        PlantReading(
          id: 2,
          createdAt: now,
          moisture: 12,
          lux: 240,
        ),
      ];

      final prediction = engine.predict(
        readings: readings,
        now: now,
      );

      expect(prediction.urgency, CareUrgency.now);
      expect(prediction.wateringAction, contains('Annaffia ora'));
    });

    test('estimates next watering from moisture trend', () {
      final engine = PredictiveCareEngine();
      final now = DateTime(2026, 2, 17, 10, 0);
      final readings = [
        PlantReading(
          id: 1,
          createdAt: now.subtract(const Duration(hours: 6)),
          moisture: 52,
          lux: 700,
        ),
        PlantReading(
          id: 2,
          createdAt: now.subtract(const Duration(hours: 3)),
          moisture: 44,
          lux: 680,
        ),
        PlantReading(
          id: 3,
          createdAt: now,
          moisture: 36,
          lux: 720,
        ),
      ];

      final prediction = engine.predict(
        readings: readings,
        plant: const Plant(
          id: 'p1',
          name: 'Pepe',
          personality: 'test',
          plantType: PlantType.peperoncino,
          moistureLow: 15,
          moistureOk: 30,
          moistureHigh: 80,
          luxLow: 50,
          luxHigh: 18000,
        ),
        now: now,
      );

      expect(prediction.nextWateringAt, isNotNull);
      expect(prediction.urgency, isNot(CareUrgency.now));
      expect(prediction.wateringAction, contains('Prossima irrigazione stimata'));
    });
  });
}
