class PlantReading {
  const PlantReading({
    required this.id,
    required this.createdAt,
    required this.moisture,
    required this.lux,
    this.plantId,
  });

  final int id;
  final DateTime createdAt;
  final double moisture;
  final double lux;
  final String? plantId;

  factory PlantReading.fromMap(Map<String, dynamic> map) {
    return PlantReading(
      id: (map['id'] as num).toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
      moisture: (map['moisture'] as num).toDouble(),
      lux: (map['lux'] as num).toDouble(),
      plantId: map['plant_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'moisture': moisture,
      'lux': lux,
      'plant_id': plantId,
    };
  }
}
