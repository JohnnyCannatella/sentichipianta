import 'package:flutter/material.dart';

import '../models/plant.dart';

typedef PlantChanged = void Function(Plant? plant);

typedef PlantSelectorBuilder = Widget Function(
  BuildContext context,
  List<Plant> plants,
  Plant? selected,
  PlantChanged onChanged,
);

class PlantSelection extends StatelessWidget {
  const PlantSelection({
    super.key,
    required this.plants,
    required this.selected,
    required this.onChanged,
    required this.builder,
  });

  final List<Plant> plants;
  final Plant? selected;
  final PlantChanged onChanged;
  final PlantSelectorBuilder builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, plants, selected, onChanged);
  }
}
