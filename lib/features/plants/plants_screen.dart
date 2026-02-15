import 'package:flutter/material.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../ui/app_colors.dart';
import '../../widgets/plant_avatar.dart';
import 'plant_detail_screen.dart';
import 'test_threshold_screen.dart';

enum _PlantSort { name, status }

class PlantsScreen extends StatefulWidget {
  const PlantsScreen({super.key});

  @override
  State<PlantsScreen> createState() => _PlantsScreenState();
}

class _PlantsScreenState extends State<PlantsScreen> {
  final _searchController = TextEditingController();
  bool _criticalOnly = false;
  _PlantSort _sort = _PlantSort.status;

  void _refresh() {
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aggiornato ora')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = PlantRepository();
    final interpreter = PlantInterpreter();

    return SafeArea(
      child: StreamBuilder<List<Plant>>(
        stream: repository.plants(),
        builder: (context, snapshot) {
          final plants = snapshot.data ?? const [];

          return StreamBuilder<List<PlantReading>>(
            stream: repository.recentReadings(limit: 200),
            builder: (context, readingsSnapshot) {
              final readings = readingsSnapshot.data ?? const [];
              final latestByPlant = <String, PlantReading>{};
              for (final reading in readings) {
                final plantId = reading.plantId;
                if (plantId == null) continue;
                latestByPlant.putIfAbsent(plantId, () => reading);
              }

              final query = _searchController.text.trim().toLowerCase();
              final filteredPlants = plants.where((plant) {
                final matchesQuery =
                    query.isEmpty || plant.name.toLowerCase().contains(query);
                if (!matchesQuery) {
                  return false;
                }
                if (!_criticalOnly) {
                  return true;
                }
                final latest = latestByPlant[plant.id];
                return interpreter.isCritical(latest, plant: plant);
              }).toList();

              filteredPlants.sort((a, b) {
                if (_sort == _PlantSort.name) {
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                }
                final aCritical =
                    interpreter.isCritical(latestByPlant[a.id], plant: a);
                final bCritical =
                    interpreter.isCritical(latestByPlant[b.id], plant: b);
                if (aCritical != bCritical) {
                  return aCritical ? -1 : 1;
                }
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

              final criticalCount = plants
                  .where(
                    (plant) =>
                        interpreter.isCritical(latestByPlant[plant.id], plant: plant),
                  )
                  .length;

              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFC7D3C0), Color(0xFFB6C5AE)],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEFE8),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xB2FFFFFF), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      _PlantsTopBar(
                        onRefresh: _refresh,
                        onAdd: () =>
                            _openEditor(context, repository, plants: plants),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Le mie piante',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _CountPill(
                            icon: Icons.spa_outlined,
                            label: 'Totali ${plants.length}',
                          ),
                          const SizedBox(width: 8),
                          _CountPill(
                            icon: Icons.warning_amber_rounded,
                            label: 'Critiche $criticalCount',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Cerca una pianta...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilterChip(
                            selected: _criticalOnly,
                            label: const Text('Solo critiche'),
                            onSelected: (value) {
                              setState(() => _criticalOnly = value);
                            },
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<_PlantSort>(
                            value: _sort,
                            underline: const SizedBox.shrink(),
                            borderRadius: BorderRadius.circular(12),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _sort = value);
                              }
                            },
                            items: const [
                              DropdownMenuItem(
                                value: _PlantSort.status,
                                child: Text('Ordina: stato'),
                              ),
                              DropdownMenuItem(
                                value: _PlantSort.name,
                                child: Text('Ordina: nome'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 210,
                        child: filteredPlants.isEmpty
                            ? _EmptyState(
                                onAdd: () => _openEditor(
                                  context,
                                  repository,
                                  plants: plants,
                                ),
                                message: plants.isEmpty
                                    ? 'Nessuna pianta configurata'
                                    : 'Nessuna pianta corrisponde ai filtri',
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: filteredPlants.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final plant = filteredPlants[index];
                                  final latest = latestByPlant[plant.id];
                                  final isCritical = interpreter.isCritical(
                                    latest,
                                    plant: plant,
                                  );
                                  return SizedBox(
                                    width: 178,
                                    child: GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              PlantDetailScreen(plant: plant),
                                        ),
                                      ),
                                      child: _PlantCard(
                                        plant: plant,
                                        isCritical: isCritical,
                                        onEdit: () => _openEditor(
                                          context,
                                          repository,
                                          plants: plants,
                                          plant: plant,
                                        ),
                                        onDuplicate: () => _duplicatePlant(
                                          context,
                                          repository,
                                          plant,
                                        ),
                                        onTest: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TestThresholdScreen(
                                              plant: plant,
                                            ),
                                          ),
                                        ),
                                        onDelete: () => _confirmDelete(
                                          context,
                                          repository,
                                          plant: plant,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Esplora',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 130,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: filteredPlants.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final plant = filteredPlants[index];
                            return _ExploreCard(plant: plant);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tips_and_updates_outlined,
                                color: AppColors.textDark),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Tip: usa il filtro "Solo critiche" per intervenire subito.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _duplicatePlant(
    BuildContext context,
    PlantRepository repository,
    Plant plant,
  ) async {
    final duplicateName = '${plant.name} copia';
    await repository.createPlant(
      name: duplicateName,
      personality: plant.personality,
      plantType: plant.plantType,
      notes: plant.notes,
      moistureLow: plant.moistureLow,
      moistureOk: plant.moistureOk,
      moistureHigh: plant.moistureHigh,
      luxLow: plant.luxLow,
      luxHigh: plant.luxHigh,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Creata "$duplicateName".')),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    PlantRepository repository, {
    required List<Plant> plants,
    Plant? plant,
  }) async {
    final nameController = TextEditingController(text: plant?.name ?? '');
    final personalityController =
        TextEditingController(text: plant?.personality ?? '');
    final notesController = TextEditingController(text: plant?.notes ?? '');
    final moistureLowController = TextEditingController(
      text: plant?.moistureLow?.toStringAsFixed(0) ?? '',
    );
    final moistureOkController = TextEditingController(
      text: plant?.moistureOk?.toStringAsFixed(0) ?? '',
    );
    final moistureHighController = TextEditingController(
      text: plant?.moistureHigh?.toStringAsFixed(0) ?? '',
    );
    final luxLowController = TextEditingController(
      text: plant?.luxLow?.toStringAsFixed(0) ?? '',
    );
    final luxHighController = TextEditingController(
      text: plant?.luxHigh?.toStringAsFixed(0) ?? '',
    );
    String? nameError;
    String? personalityError;
    String? moistureError;
    String? luxError;
    var selectedPlantType =
        PlantType.normalize(plant?.plantType ?? PlantType.fromName(plant?.name));

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5F2EA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void validate() {
              final name = nameController.text.trim();
              final personality = personalityController.text.trim();
              final moistureLow = _parseNumber(moistureLowController.text);
              final moistureOk = _parseNumber(moistureOkController.text);
              final moistureHigh = _parseNumber(moistureHighController.text);
              final luxLow = _parseNumber(luxLowController.text);
              final luxHigh = _parseNumber(luxHighController.text);
              final duplicate = plants.any(
                (item) =>
                    item.id != plant?.id &&
                    item.name.trim().toLowerCase() == name.toLowerCase(),
              );

              final moistureProvided =
                  moistureLow != null || moistureOk != null || moistureHigh != null;
              final luxProvided = luxLow != null || luxHigh != null;

              setModalState(() {
                nameError = name.isEmpty
                    ? 'Il nome e obbligatorio'
                    : duplicate
                        ? 'Nome gia presente'
                        : null;
                personalityError = personality.isEmpty
                    ? 'La personalita e obbligatoria'
                    : personality.length < 10
                        ? 'Personalita troppo breve'
                        : null;
                moistureError = moistureProvided
                    ? _validateMoisture(moistureLow, moistureOk, moistureHigh)
                    : null;
                luxError = luxProvided ? _validateLux(luxLow, luxHigh) : null;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plant == null ? 'Nuova pianta' : 'Modifica pianta',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    onChanged: (_) => validate(),
                    decoration: InputDecoration(
                      labelText: 'Nome',
                      filled: true,
                      errorText: nameError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: personalityController,
                    onChanged: (_) => validate(),
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Personalita',
                      filled: true,
                      errorText: personalityError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPlantType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo pianta',
                      filled: true,
                    ),
                    items: [
                      for (final type in PlantType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(PlantType.label(type)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(
                          () => selectedPlantType = PlantType.normalize(value),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Soglie umidita (%)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: moistureLowController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => validate(),
                          decoration: InputDecoration(
                            labelText: 'Min',
                            filled: true,
                            errorText: moistureError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: moistureOkController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => validate(),
                          decoration: InputDecoration(
                            labelText: 'Target',
                            filled: true,
                            errorText: moistureError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: moistureHighController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => validate(),
                          decoration: InputDecoration(
                            labelText: 'Max',
                            filled: true,
                            errorText: moistureError,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Soglie luce (lux)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: luxLowController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => validate(),
                          decoration: InputDecoration(
                            labelText: 'Min',
                            filled: true,
                            errorText: luxError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: luxHighController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => validate(),
                          decoration: InputDecoration(
                            labelText: 'Max',
                            filled: true,
                            errorText: luxError,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annulla'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            validate();
                            if (nameError == null &&
                                personalityError == null &&
                                moistureError == null &&
                                luxError == null) {
                              Navigator.pop(context, true);
                            }
                          },
                          child: const Text('Salva'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!context.mounted) {
      return;
    }

    if (saved != true) {
      return;
    }

    final name = nameController.text.trim();
    final personality = personalityController.text.trim();
    if (name.isEmpty || personality.isEmpty) {
      return;
    }

    final moistureLow = _parseNumber(moistureLowController.text);
    final moistureOk = _parseNumber(moistureOkController.text);
    final moistureHigh = _parseNumber(moistureHighController.text);
    final luxLow = _parseNumber(luxLowController.text);
    final luxHigh = _parseNumber(luxHighController.text);
    final notes = notesController.text.trim();

    if (plant == null) {
      await repository.createPlant(
        name: name,
        personality: personality,
        plantType: selectedPlantType,
        notes: notes.isEmpty ? null : notes,
        moistureLow: moistureLow,
        moistureOk: moistureOk,
        moistureHigh: moistureHigh,
        luxLow: luxLow,
        luxHigh: luxHigh,
      );
    } else {
      await repository.updatePlant(
        id: plant.id,
        name: name,
        personality: personality,
        plantType: selectedPlantType,
        notes: notes.isEmpty ? null : notes,
        moistureLow: moistureLow,
        moistureOk: moistureOk,
        moistureHigh: moistureHigh,
        luxLow: luxLow,
        luxHigh: luxHigh,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PlantRepository repository, {
    required Plant plant,
  }) async {
    final hasReadings = await repository.hasReadings(plant.id);
    if (!context.mounted) {
      return;
    }
    if (hasReadings) {
      final target = await _askMoveTarget(context, plant.id, repository);
      if (target == null) {
        return;
      }
      await repository.moveReadings(
        fromPlantId: plant.id,
        toPlantId: target.id,
      );
      if (!context.mounted) {
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare pianta?'),
        content: Text('Vuoi eliminare "${plant.name}" e i suoi dati?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await repository.deletePlant(plant.id);
    }
  }

  Future<Plant?> _askMoveTarget(
    BuildContext context,
    String fromPlantId,
    PlantRepository repository,
  ) async {
    final plants = await repository.plants().first;
    if (!context.mounted) {
      return null;
    }
    final choices = plants.where((plant) => plant.id != fromPlantId).toList();
    if (choices.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Impossibile spostare letture'),
          content: const Text(
            'Aggiungi un’altra pianta per poter spostare le letture prima di eliminare.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
      return null;
    }

    Plant? selected = choices.first;
    return showDialog<Plant>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Spostare letture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Seleziona la pianta di destinazione per le letture esistenti.',
              ),
              const SizedBox(height: 12),
              DropdownButton<Plant>(
                value: selected,
                items: [
                  for (final plant in choices)
                    DropdownMenuItem(
                      value: plant,
                      child: Text(plant.name),
                    ),
                ],
                onChanged: (value) => setState(() => selected = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Sposta'),
            ),
          ],
        ),
      ),
    );
  }
}

double? _parseNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed);
}

String? _validateMoisture(
  double? low,
  double? ok,
  double? high,
) {
  if (low == null && ok == null && high == null) {
    return null;
  }
  if (low == null || ok == null || high == null) {
    return 'Completa tutte le soglie umidita';
  }
  if (low < 0 || high > 100 || ok < 0 || ok > 100) {
    return 'Valori umidita tra 0 e 100';
  }
  if (low >= ok || ok >= high) {
    return 'Min < Target < Max';
  }
  return null;
}

String? _validateLux(double? low, double? high) {
  if (low == null && high == null) {
    return null;
  }
  if (low == null || high == null) {
    return 'Completa tutte le soglie luce';
  }
  if (low < 0 || high <= 0) {
    return 'Valori luce non validi';
  }
  if (low >= high) {
    return 'Min < Max';
  }
  return null;
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({
    required this.plant,
    required this.isCritical,
    required this.onTest,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Plant plant;
  final bool isCritical;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isCritical)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.alertBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.alertBorder),
                  ),
                  child: Text(
                    'Critico',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: const Color(0xFFD25B4B)),
                  ),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                iconColor: Colors.white,
                onSelected: (value) {
                  switch (value) {
                    case 'test':
                      onTest();
                      break;
                    case 'edit':
                      onEdit();
                      break;
                    case 'duplicate':
                      onDuplicate();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'test', child: Text('Test soglie')),
                  const PopupMenuItem(value: 'edit', child: Text('Modifica')),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplica'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Elimina')),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 86,
            child: Center(
              child: PlantAvatar(
                plantName: plant.name,
                plantType: plant.plantType,
                size: 86,
                radius: 16,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            plant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            PlantType.label(plant.plantType),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onAdd,
    required this.message,
  });

  final VoidCallback onAdd;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.spa, size: 42, color: Color(0xFF8E9A8B)),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF5B6258)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onAdd,
            child: const Text('Aggiungi pianta'),
          ),
        ],
      ),
    );
  }
}

class _PlantsTopBar extends StatelessWidget {
  const _PlantsTopBar({required this.onAdd, required this.onRefresh});

  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF191D18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopAction(icon: Icons.refresh, tooltip: 'Aggiorna', onTap: onRefresh),
              const SizedBox(width: 6),
              _TopAction(icon: Icons.add, tooltip: 'Aggiungi', onTap: onAdd),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Icon(Icons.spa, color: AppColors.primary, size: 28),
          ),
        ),
        const SizedBox(width: 1),
      ],
    );
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: Color(0xFF111612)),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Color(0x1F2F8C57),
            child: PlantAvatar(
              plantName: plant.name,
              plantType: plant.plantType,
              size: 56,
              radius: 999,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            plant.name,
            style: Theme.of(context).textTheme.labelMedium,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Indoor',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
