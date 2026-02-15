import 'package:flutter/material.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant_insight.dart';
import '../../models/plant.dart';
import '../../models/plant_reading.dart';
import '../../services/notification_service.dart';
import '../history/history_screen.dart';
import '../chat/chat_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../plants/plants_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  Plant? _selectedPlant;
  bool? _lastCritical;

  final _repository = PlantRepository();
  final _interpreter = PlantInterpreter();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Plant>>(
      stream: _repository.plants(),
      builder: (context, snapshot) {
        final plants = snapshot.data ?? const [];
        final selectedExists = _selectedPlant != null &&
            plants.any((plant) => plant.id == _selectedPlant!.id);

        if (_selectedPlant != null && !selectedExists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedPlant = plants.isEmpty ? null : plants.first);
          });
        }

        if (_selectedPlant == null && plants.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_selectedPlant == null && plants.isNotEmpty) {
              setState(() => _selectedPlant = plants.first);
            }
          });
        }

        final pages = [
          DashboardScreen(
            plants: plants,
            selectedPlant: _selectedPlant,
            onSelectPlant: _handleSelectPlant,
            onOpenChat: () => setState(() => _index = 1),
            onRefresh: () => setState(() {}),
          ),
          ChatScreen(
            plants: plants,
            selectedPlant: _selectedPlant,
            onSelectPlant: _handleSelectPlant,
          ),
          HistoryScreen(plant: _selectedPlant),
          const PlantsScreen(),
        ];

        return StreamBuilder<PlantReading?>(
          stream: _repository.latestReadingForPlant(
            plantId: _selectedPlant?.id,
          ),
          builder: (context, readingSnapshot) {
            final reading = readingSnapshot.data;
            final insight =
                _interpreter.interpret(reading, plant: _selectedPlant);
            final critical =
                _interpreter.isCritical(reading, plant: _selectedPlant);

            if (_lastCritical != critical) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_lastCritical != null && !_lastCritical! && critical) {
                  NotificationService.instance.showCriticalAlert(
                    title: _selectedPlant?.name ?? 'Senti Chi Pianta',
                    body: insight.message,
                  );
                }
                _lastCritical = critical;
              });
            }

            return Scaffold(
              body: IndexedStack(
                index: _index,
                children: pages,
              ),
              bottomNavigationBar: _BottomPillNav(
                selectedIndex: _index,
                showCriticalBadge: critical,
                onSelected: (value) => setState(() => _index = value),
              ),
            );
          },
        );
      },
    );
  }

  void _handleSelectPlant(Plant? plant) {
    if (plant == null || plant.id == _selectedPlant?.id) {
      return;
    }
    setState(() => _selectedPlant = plant);
  }
}

class _BottomPillNav extends StatelessWidget {
  const _BottomPillNav({
    required this.selectedIndex,
    required this.showCriticalBadge,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool showCriticalBadge;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Dashboard', 'Chat', 'Storico', 'Piante'];
    const outlinedIcons = [
      Icons.eco_outlined,
      Icons.favorite_border,
      Icons.shopping_cart_outlined,
      Icons.person_outline,
    ];
    const filledIcons = [
      Icons.eco,
      Icons.favorite,
      Icons.shopping_cart,
      Icons.person,
    ];

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF161915),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: List.generate(labels.length, (index) {
            final selected = selectedIndex == index;
            return _BottomPillItem(
              label: labels[index],
              icon: selected ? filledIcons[index] : outlinedIcons[index],
              selected: selected,
              showBadge: index == 0 && showCriticalBadge,
              onTap: () => onSelected(index),
            );
          }),
        ),
      ),
    );
  }
}

class _BottomPillItem extends StatelessWidget {
  const _BottomPillItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.showBadge,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool showBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? const Color(0xFF111612) : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: selected ? 148 : 54,
      height: 48,
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: fg, size: 24),
                  if (showBadge)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD25B4B),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111612),
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
