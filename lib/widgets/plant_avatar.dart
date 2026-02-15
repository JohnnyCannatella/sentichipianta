import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../ui/app_colors.dart';

class PlantAvatar extends StatelessWidget {
  const PlantAvatar({
    super.key,
    required this.plantName,
    this.plantType,
    this.size = 120,
    this.radius = 18,
  });

  final String plantName;
  final String? plantType;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolvedType = PlantType.normalize(
      plantType ?? PlantType.fromName(plantName),
    );
    final assetPaths = [
      'assets/plant_states/$resolvedType/ok.png',
      'assets/plant_states/$resolvedType/Ok.png',
      'assets/plant_states/$resolvedType/unknown.png',
      'assets/plant_states/$resolvedType/Unknown.png',
      'assets/plant_states/generic/ok.png',
      'assets/plant_states/generic/unknown.png',
    ];
    final style = _AvatarStyle.fromPlantName(plantName);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: style.gradient,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: -size * 0.1,
              child: Container(
                width: size * 0.72,
                height: size * 0.24,
                decoration: const BoxDecoration(
                  color: Color(0x3D000000),
                  borderRadius: BorderRadius.all(Radius.elliptical(90, 35)),
                ),
              ),
            ),
            _buildAssetWithFallback(assetPaths, style, 0),
            Positioned(
              top: size * 0.08,
              right: size * 0.08,
              child: Container(
                width: size * 0.16,
                height: size * 0.16,
                decoration: const BoxDecoration(
                  color: Color(0x55FFFFFF),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetWithFallback(
    List<String> paths,
    _AvatarStyle style,
    int index,
  ) {
    return Image.asset(
      paths[index],
      width: size * 0.92,
      height: size * 0.92,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        if (index + 1 >= paths.length) {
          return Icon(
            style.icon,
            size: size * 0.46,
            color: Colors.white,
          );
        }
        return _buildAssetWithFallback(paths, style, index + 1);
      },
    );
  }
}

class _AvatarStyle {
  const _AvatarStyle({required this.icon, required this.gradient});

  final IconData icon;
  final List<Color> gradient;

  factory _AvatarStyle.fromPlantName(String name) {
    final normalized = name.toLowerCase();

    if (normalized.contains('peper') ||
        normalized.contains('chili') ||
        normalized.contains('pepper')) {
      return const _AvatarStyle(
        icon: Icons.local_fire_department,
        gradient: [Color(0xFFE4674D), Color(0xFFB53A27)],
      );
    }

    if (normalized.contains('bonsai')) {
      return const _AvatarStyle(
        icon: Icons.park,
        gradient: [Color(0xFF6AAE7A), Color(0xFF2D6A4F)],
      );
    }

    if (normalized.contains('sansevieria') ||
        normalized.contains('sanseveria') ||
        normalized.contains('snake')) {
      return const _AvatarStyle(
        icon: Icons.grass,
        gradient: [Color(0xFF8CCF89), Color(0xFF2E7D32)],
      );
    }

    if (normalized.contains('cactus')) {
      return const _AvatarStyle(
        icon: Icons.local_florist,
        gradient: [Color(0xFF8BC34A), Color(0xFF33691E)],
      );
    }

    if (normalized.contains('orchid')) {
      return const _AvatarStyle(
        icon: Icons.spa,
        gradient: [Color(0xFFD57FB5), Color(0xFF8E4D7A)],
      );
    }

    return const _AvatarStyle(
      icon: Icons.spa,
      gradient: [AppColors.primarySoft, AppColors.primaryDark],
    );
  }
}
