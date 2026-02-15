import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../ui/app_colors.dart';
import 'plant_avatar.dart';

class PlantPickerSheet {
  static Future<void> show(
    BuildContext context, {
    required List<Plant> plants,
    required String? selectedId,
    required ValueChanged<Plant?> onChanged,
  }) async {
    if (plants.length <= 1) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Seleziona pianta',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: plants.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: AppColors.outline),
                    itemBuilder: (context, index) {
                      final plant = plants[index];
                      final isSelected = plant.id == selectedId;
                      return ListTile(
                        leading: _PlantAvatar(plant: plant),
                        title: Text(plant.name),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          onChanged(plant);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlantAvatar extends StatelessWidget {
  const _PlantAvatar({required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.background,
      child: PlantAvatar(
        plantName: plant.name,
        plantType: plant.plantType,
        size: 36,
        radius: 999,
      ),
    );
  }
}
