import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/plant.dart';
import '../models/plant_reading.dart';

class ClaudeService {
  Future<String> generateReply({
    required String message,
    required Plant? plant,
    PlantReading? reading,
  }) async {
    if (AppConfig.claudeEndpoint.contains('YOUR_API_ENDPOINT')) {
      return 'Sono ancora in ascolto: collegami alla mia voce digitale.';
    }

    final payload = {
      'message': message,
      'plant': {
        'name': plant?.name ?? 'Senti Chi Pianta',
        'personality': plant?.personality ??
            'Gentile, poetica, ironica quanto basta. Parla in prima persona.',
      },
      'reading': reading == null
          ? null
          : {
              'moisture': reading.moisture,
              'lux': reading.lux,
              'created_at': reading.createdAt.toIso8601String(),
            },
      };

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (AppConfig.chatSecret.isNotEmpty) {
      headers['x-chat-secret'] = AppConfig.chatSecret;
    }

    if (plant != null) {
      payload['plant_id'] = plant.id;
    }

    final response = await http.post(
      Uri.parse(AppConfig.claudeEndpoint),
      headers: headers,
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return 'Sto provando a parlare, ma la mia voce digitale non risponde.';
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['reply'] as String?)?.trim().isNotEmpty == true
        ? decoded['reply'] as String
        : 'Mi manca la voce: puoi riprovare?';
  }

}
