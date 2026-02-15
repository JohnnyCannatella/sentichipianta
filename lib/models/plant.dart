class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.personality,
    required this.plantType,
    this.photoUrl,
    this.notes,
    this.moistureLow,
    this.moistureOk,
    this.moistureHigh,
    this.luxLow,
    this.luxHigh,
  });

  final String id;
  final String name;
  final String personality;
  final String plantType;
  final String? photoUrl;
  final String? notes;
  final double? moistureLow;
  final double? moistureOk;
  final double? moistureHigh;
  final double? luxLow;
  final double? luxHigh;

  static const double defaultMoistureLow = 15;
  static const double defaultMoistureOk = 30;
  static const double defaultMoistureHigh = 80;
  static const double defaultLuxLow = 50;
  static const double defaultLuxHigh = 18000;

  factory Plant.fromMap(Map<String, dynamic> map) {
    return Plant(
      id: map['id'] as String,
      name: map['name'] as String,
      personality: map['personality'] as String? ??
          'Gentile, poetica, ironica quanto basta. Parla in prima persona.',
      plantType: PlantType.normalize(
        map['plant_type'] as String? ?? PlantType.fromName(map['name'] as String),
      ),
      photoUrl: map['photo_url'] as String?,
      notes: map['notes'] as String?,
      moistureLow: (map['moisture_low'] as num?)?.toDouble(),
      moistureOk: (map['moisture_ok'] as num?)?.toDouble(),
      moistureHigh: (map['moisture_high'] as num?)?.toDouble(),
      luxLow: (map['lux_low'] as num?)?.toDouble(),
      luxHigh: (map['lux_high'] as num?)?.toDouble(),
    );
  }

  double get effectiveMoistureLow => moistureLow ?? defaultMoistureLow;
  double get effectiveMoistureOk => moistureOk ?? defaultMoistureOk;
  double get effectiveMoistureHigh => moistureHigh ?? defaultMoistureHigh;
  double get effectiveLuxLow => luxLow ?? defaultLuxLow;
  double get effectiveLuxHigh => luxHigh ?? defaultLuxHigh;
}

class PlantType {
  static const generic = 'generic';
  static const peperoncino = 'peperoncino';
  static const sansevieria = 'sansevieria';
  static const bonsai = 'bonsai';
  static const cactus = 'cactus';

  static const values = [
    generic,
    peperoncino,
    sansevieria,
    bonsai,
    cactus,
  ];

  static String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    if (values.contains(normalized)) {
      return normalized;
    }
    return generic;
  }

  static String fromName(String? name) {
    final normalized = (name ?? '').toLowerCase();
    if (normalized.contains('peper') ||
        normalized.contains('peperonc') ||
        normalized.contains('pepper') ||
        normalized.contains('chili')) {
      return peperoncino;
    }
    if (normalized.contains('sansevieria') ||
        normalized.contains('sanseveria') ||
        normalized.contains('snake')) {
      return sansevieria;
    }
    if (normalized.contains('bonsai')) {
      return bonsai;
    }
    if (normalized.contains('cactus')) {
      return cactus;
    }
    return generic;
  }

  static String label(String value) {
    switch (normalize(value)) {
      case peperoncino:
        return 'Peperoncino';
      case sansevieria:
        return 'Sansevieria';
      case bonsai:
        return 'Bonsai';
      case cactus:
        return 'Cactus';
      default:
        return 'Generica';
    }
  }
}
