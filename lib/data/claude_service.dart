import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/plant.dart';
import '../models/plant_reading.dart';

class ClaudeReplyResult {
  ClaudeReplyResult({
    required this.reply,
    required this.persisted,
  });

  final String reply;
  final bool persisted;
}

class ClaudeService {
  Future<ClaudeReplyResult> generateReply({
    required String message,
    required Plant? plant,
    PlantReading? reading,
  }) async {
    if (AppConfig.claudeEndpoint.contains('YOUR_API_ENDPOINT')) {
      return ClaudeReplyResult(
        reply: 'Sono ancora in ascolto: collegami alla mia voce digitale.',
        persisted: false,
      );
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
              'temperature': reading.temperature,
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

    final decoded = _decodeBody(response.body);
    final reply = (decoded?['reply'] as String?)?.trim();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return ClaudeReplyResult(
        reply: reply?.isNotEmpty == true
            ? reply!
            : 'Sto provando a parlare, ma la mia voce digitale non risponde.',
        persisted: false,
      );
    }

    return ClaudeReplyResult(
      reply: reply?.isNotEmpty == true ? reply! : 'Mi manca la voce: puoi riprovare?',
      persisted: true,
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
