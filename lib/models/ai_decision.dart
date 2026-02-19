class AiDecision {
  const AiDecision({
    required this.id,
    required this.plantId,
    required this.createdAt,
    required this.source,
    required this.model,
    required this.sensorSnapshot,
    required this.recommendation,
    required this.confidence,
    required this.needsFollowUp,
    this.followUpDueAt,
    this.outcome,
  });

  final int id;
  final String plantId;
  final DateTime createdAt;
  final String source;
  final String? model;
  final Map<String, dynamic> sensorSnapshot;
  final Map<String, dynamic> recommendation;
  final double? confidence;
  final bool needsFollowUp;
  final DateTime? followUpDueAt;
  final String? outcome;

  factory AiDecision.fromMap(Map<String, dynamic> map) {
    return AiDecision(
      id: (map['id'] as num).toInt(),
      plantId: map['plant_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      source: map['source'] as String? ?? 'fireworks',
      model: map['model'] as String?,
      sensorSnapshot: Map<String, dynamic>.from(
        map['sensor_snapshot'] as Map? ?? {},
      ),
      recommendation: Map<String, dynamic>.from(
        map['recommendation'] as Map? ?? {},
      ),
      confidence: (map['confidence'] as num?)?.toDouble(),
      needsFollowUp: map['needs_follow_up'] as bool? ?? false,
      followUpDueAt: map['follow_up_due_at'] == null
          ? null
          : DateTime.tryParse(map['follow_up_due_at'] as String),
      outcome: map['outcome'] as String?,
    );
  }
}
