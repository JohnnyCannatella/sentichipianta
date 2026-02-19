# Flutter -> Rive mapping

## Data source
- `PlantInsight.mood`
- `PlantReading.moisture`
- `PlantReading.lux`
- presenza stream/rete per `connected`

## Suggested mapping (Dart pseudo)
```dart
riveMoisture.value = reading?.moisture ?? 0;
riveLux.value = reading?.lux ?? 0;
riveConnected.value = reading != null;
riveCritical.value = interpreter.isCritical(reading, plant: selectedPlant);

switch (insight.mood) {
  case PlantMood.unknown: riveMood.value = 0; break;
  case PlantMood.thriving: riveMood.value = 1; break;
  case PlantMood.ok: riveMood.value = 2; break;
  case PlantMood.thirsty: riveMood.value = 3; break;
  case PlantMood.dark: riveMood.value = 4; break;
  case PlantMood.stressed: riveMood.value = 5; break;
}
```

## Runtime notes
- Quando `critical=true`, aumenta ampiezza pulse nel controller.
- Se `connected=false`, forza stato `sleep` e riduci motion.
- Applica transizioni brevi (150-250ms) tra stati normali; 80-140ms per critici.
