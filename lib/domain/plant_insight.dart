import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../models/plant_reading.dart';

enum PlantMood { thriving, ok, thirsty, dark, stressed, unknown }

class PlantInsight {
  PlantInsight({
    required this.mood,
    required this.title,
    required this.message,
    required this.accent,
  });

  final PlantMood mood;
  final String title;
  final String message;
  final Color accent;
}

class PlantInterpreter {
  static const double moistureLow = 15;
  static const double moistureOk = 30;
  static const double moistureHigh = 80;
  static const double luxLow = 50;
  static const double luxHigh = 18000;

  PlantInsight interpret(PlantReading? reading, {Plant? plant}) {
    final thresholds = _thresholdsFor(plant);
    if (reading == null) {
      return PlantInsight(
        mood: PlantMood.unknown,
        title: 'In ascolto',
        message: 'Sto aspettando i primi segnali dal terreno.',
        accent: const Color(0xFF8C7B6C),
      );
    }

    final moisture = reading.moisture;
    final lux = reading.lux;

    if (moisture < thresholds.moistureLow) {
      return PlantInsight(
        mood: PlantMood.thirsty,
        title: 'Radici assetate',
        message: 'Ho bisogno di acqua: la terra è troppo secca.',
        accent: const Color(0xFFC96B3C),
      );
    }

    if (lux < thresholds.luxLow) {
      return PlantInsight(
        mood: PlantMood.dark,
        title: 'Troppo buio',
        message: 'La luce è poca, faccio fatica a respirare.',
        accent: const Color(0xFF39424E),
      );
    }

    if (moisture > thresholds.moistureHigh || lux > thresholds.luxHigh) {
      return PlantInsight(
        mood: PlantMood.stressed,
        title: 'Troppo intenso',
        message: 'Sto lavorando al limite, meglio calmare le condizioni.',
        accent: const Color(0xFF6B4E3D),
      );
    }

    if (moisture >= thresholds.moistureOk && lux >= thresholds.luxLow) {
      return PlantInsight(
        mood: PlantMood.thriving,
        title: 'In piena forma',
        message: 'Mi sento bene, continua cosi.',
        accent: const Color(0xFF3C6E47),
      );
    }

    return PlantInsight(
      mood: PlantMood.ok,
      title: 'Stabile',
      message: 'Sono tranquilla, ma fammi controllare ogni tanto.',
      accent: const Color(0xFF4C6A58),
    );
  }

  bool isCritical(PlantReading? reading, {Plant? plant}) {
    if (reading == null) {
      return false;
    }
    final thresholds = _thresholdsFor(plant);
    final moisture = reading.moisture;
    final lux = reading.lux;
    return moisture < thresholds.moistureLow ||
        lux < thresholds.luxLow ||
        moisture > thresholds.moistureHigh ||
        lux > thresholds.luxHigh;
  }

  _Thresholds _thresholdsFor(Plant? plant) {
    return _Thresholds(
      moistureLow: plant?.effectiveMoistureLow ?? moistureLow,
      moistureOk: plant?.effectiveMoistureOk ?? moistureOk,
      moistureHigh: plant?.effectiveMoistureHigh ?? moistureHigh,
      luxLow: plant?.effectiveLuxLow ?? luxLow,
      luxHigh: plant?.effectiveLuxHigh ?? luxHigh,
    );
  }
}

class _Thresholds {
  const _Thresholds({
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
