import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../models/plant_reading.dart';

class PlantStateArt extends StatelessWidget {
  const PlantStateArt({
    super.key,
    required this.plant,
    required this.reading,
    required this.size,
    required this.radius,
  });

  final Plant? plant;
  final PlantReading? reading;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final paths = _resolveAssetPaths();
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: _buildAssetWithFallback(paths, 0),
    );
  }

  Widget _buildAssetWithFallback(List<String> paths, int index) {
    return Image.asset(
      paths[index],
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        if (index + 1 >= paths.length) {
          return const SizedBox.shrink();
        }
        return _buildAssetWithFallback(paths, index + 1);
      },
    );
  }

  List<String> _resolveAssetPaths() {
    final type = PlantType.normalize(
      plant?.plantType ?? PlantType.fromName(plant?.name),
    );
    final state = _stateKey();
    final upperState = _capitalize(state);

    return [
      'assets/plant_states/$type/$state.png',
      'assets/plant_states/$type/$upperState.png',
      'assets/plant_states/$type/unknown.png',
      'assets/plant_states/$type/Unknown.png',
      'assets/plant_states/generic/$state.png',
      'assets/plant_states/generic/$upperState.png',
      'assets/plant_states/generic/unknown.png',
      'assets/plant_states/generic/Unknown.png',
    ];
  }

  String _stateKey() {
    if (reading == null || plant == null) {
      return 'unknown';
    }

    if (reading!.moisture < plant!.effectiveMoistureLow) {
      return 'thirsty';
    }
    if (reading!.moisture > plant!.effectiveMoistureHigh) {
      return 'overwatered';
    }
    if (reading!.lux < plant!.effectiveLuxLow) {
      return 'low_light';
    }
    if (reading!.lux > plant!.effectiveLuxHigh) {
      return 'high_light';
    }
    if (reading!.moisture >= plant!.effectiveMoistureOk &&
        reading!.lux >= plant!.effectiveLuxLow) {
      return 'happy';
    }

    return 'ok';
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}
