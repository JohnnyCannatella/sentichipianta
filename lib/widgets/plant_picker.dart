import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../ui/app_colors.dart';
import 'plant_avatar.dart';

class PlantPicker extends StatelessWidget {
  const PlantPicker({
    super.key,
    required this.plants,
    required this.selectedId,
    required this.onChanged,
    this.showLabel = true,
    this.showPill = true,
  });

  final List<Plant> plants;
  final String? selectedId;
  final ValueChanged<Plant?> onChanged;
  final bool showLabel;
  final bool showPill;

  @override
  Widget build(BuildContext context) {
    if (plants.length <= 1) {
      return const SizedBox.shrink();
    }

    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _resolveSelectedId(),
        dropdownColor: AppColors.card,
        iconEnabledColor: showPill ? Colors.white : Colors.white70,
        icon: const Icon(Icons.keyboard_arrow_down),
        isDense: true,
        isExpanded: false,
        itemHeight: 56,
        menuMaxHeight: 280,
        selectedItemBuilder: showLabel
            ? null
            : (context) => [
                  for (final _ in plants)
                    const SizedBox(
                      width: 1,
                      height: 20,
                    ),
                ],
        items: [
          for (final plant in plants)
            DropdownMenuItem(
              value: plant.id,
              child: _PlantMenuItem(plant: plant),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          final plant = plants.firstWhere(
            (item) => item.id == value,
            orElse: () => plants.first,
          );
          onChanged(plant);
        },
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Colors.white),
      ),
    );

    final sizedDropdown = SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerRight,
        child: dropdown,
      ),
    );

    final constrainedDropdown = showLabel
        ? sizedDropdown
        : SizedBox(
            width: 40,
            height: 36,
            child: Align(
              alignment: Alignment.centerRight,
              child: dropdown,
            ),
          );

    if (!showPill) {
      return constrainedDropdown;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      constraints: const BoxConstraints(minHeight: 36),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primaryDark),
      ),
      child: constrainedDropdown,
    );
  }

  String? _resolveSelectedId() {
    if (plants.isEmpty) {
      return null;
    }
    if (selectedId == null) {
      return plants.first.id;
    }
    final exists = plants.any((plant) => plant.id == selectedId);
    return exists ? selectedId : plants.first.id;
  }
}

class _PlantMenuItem extends StatelessWidget {
  const _PlantMenuItem({required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.background,
          child: PlantAvatar(
            plantName: plant.name,
            plantType: plant.plantType,
            size: 36,
            radius: 999,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            plant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
