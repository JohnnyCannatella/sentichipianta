import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../domain/adaptive_thresholds.dart';
import '../models/plant.dart';
import '../models/plant_reading.dart';

class AiReplyResult {
  AiReplyResult({
    required this.reply,
    required this.persisted,
    required this.needsPhoto,
    required this.confidence,
  });

  final String reply;
  final bool persisted;
  final bool needsPhoto;
  final double? confidence;
}

class AiService {
  Future<AiReplyResult> generateReply({
    required String message,
    required Plant? plant,
    PlantReading? reading,
    List<PlantReading> recentReadings = const <PlantReading>[],
    Map<String, dynamic>? prediction,
    List<String> imageUrls = const <String>[],
  }) async {
    if (AppConfig.aiEndpoint.contains('YOUR_API_ENDPOINT')) {
      return AiReplyResult(
        reply: 'Sono ancora in ascolto: collegami al motore AI Fireworks.',
        persisted: false,
        needsPhoto: false,
        confidence: null,
      );
    }

    final adaptiveThresholds = AdaptiveThresholdCalculator().fromReadings(
      plant: plant,
      readings: recentReadings,
    );

    final payload = <String, dynamic>{
      'message': message,
      'plant': {
        'name': plant?.name ?? 'Senti Chi Pianta',
        'personality':
            plant?.personality ??
            'Gentile, poetica, ironica quanto basta. Parla in prima persona.',
        'plant_type': plant?.plantType ?? 'generic',
        'thresholds': adaptiveThresholds.toMap(),
      },
      'reading': reading == null
          ? null
          : {
              'moisture': reading.moisture,
              'lux': reading.lux,
              'temperature': reading.temperature,
              'created_at': reading.createdAt.toIso8601String(),
            },
      'reading_history': recentReadings
          .take(48)
          .map(
            (item) => {
              'moisture': item.moisture,
              'lux': item.lux,
              'temperature': item.temperature,
              'created_at': item.createdAt.toIso8601String(),
            },
          )
          .toList(growable: false),
      'prediction': prediction,
      'images': imageUrls,
    };

    if (plant != null) {
      payload['plant_id'] = plant.id;
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (!AppConfig.supabaseAnonKey.contains('YOUR_ANON_KEY')) {
      headers['apikey'] = AppConfig.supabaseAnonKey;
      headers['authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
    }
    if (AppConfig.chatSecret.isNotEmpty) {
      headers['x-chat-secret'] = AppConfig.chatSecret;
    }

    final response = await http.post(
      Uri.parse(AppConfig.aiEndpoint),
      headers: headers,
      body: jsonEncode(payload),
    );

    final decoded = _decodeBody(response.body);
    final reply = (decoded?['reply'] as String?)?.trim();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return AiReplyResult(
        reply: reply?.isNotEmpty == true
            ? reply!
            : 'Il motore AI non risponde al momento, riproviamo tra poco.',
        persisted: false,
        needsPhoto: false,
        confidence: null,
      );
    }

    return AiReplyResult(
      reply: reply?.isNotEmpty == true
          ? reply!
          : 'Mi manca la voce: puoi riprovare?',
      persisted: true,
      needsPhoto: decoded?['needs_photo'] as bool? ?? false,
      confidence: (decoded?['confidence'] as num?)?.toDouble(),
    );
  }
}

Map<String, dynamic>? _decodeBody(String body) {
  try {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      return data;
    }
  } catch (_) {
    // Ignore invalid body: caller will use fallback messages.
  }
  return null;
}
