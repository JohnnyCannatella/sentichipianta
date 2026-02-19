import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../models/plant.dart';
import '../models/ai_decision.dart';
import '../models/chat_message.dart';
import '../models/plant_reading.dart';

class PlantRepository {
  PlantRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  static const Duration _pollInterval = Duration(seconds: 4);

  static void _notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  Stream<T> _watch<T>(Future<T> Function() loader) {
    return Stream.multi((controller) {
      var disposed = false;

      Future<void> push() async {
        try {
          final data = await loader();
          if (!disposed) {
            controller.add(data);
          }
        } catch (error, stackTrace) {
          if (!disposed) {
            controller.addError(error, stackTrace);
          }
        }
      }

      push();
      final changeSub = _changesController.stream.listen((_) => push());
      final timer = Timer.periodic(_pollInterval, (_) => push());

      controller.onCancel = () async {
        disposed = true;
        timer.cancel();
        await changeSub.cancel();
      };
    });
  }

  Stream<Plant?> primaryPlant() {
    return _watch(() async {
      final rows = await _client
          .from('plants')
          .select()
          .order('created_at', ascending: true)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) {
        return null;
      }
      return Plant.fromMap(Map<String, dynamic>.from(list.first as Map));
    });
  }

  Stream<List<Plant>> plants() {
    return _watch(() async {
      final rows = await _client
          .from('plants')
          .select()
          .order('created_at', ascending: true);
      final list = rows as List<dynamic>;
      return list
          .map((row) => Plant.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
    });
  }

  Future<void> createPlant({
    required String name,
    required String personality,
    required String plantType,
    String? photoUrl,
    String? notes,
    double? moistureLow,
    double? moistureOk,
    double? moistureHigh,
    double? luxLow,
    double? luxHigh,
  }) async {
    await _client.from('plants').insert({
      'name': name,
      'personality': personality.isEmpty
          ? 'Gentile, poetica, ironica quanto basta. Parla in prima persona.'
          : personality,
      'plant_type': plantType,
      'photo_url': photoUrl,
      'notes': notes,
      'moisture_low': moistureLow,
      'moisture_ok': moistureOk,
      'moisture_high': moistureHigh,
      'lux_low': luxLow,
      'lux_high': luxHigh,
    });
    _notifyChanged();
  }

  Future<void> updatePlant({
    required String id,
    required String name,
    required String personality,
    required String plantType,
    String? photoUrl,
    String? notes,
    double? moistureLow,
    double? moistureOk,
    double? moistureHigh,
    double? luxLow,
    double? luxHigh,
  }) async {
    await _client
        .from('plants')
        .update({
          'name': name,
          'personality': personality.isEmpty
              ? 'Gentile, poetica, ironica quanto basta. Parla in prima persona.'
              : personality,
          'plant_type': plantType,
          'photo_url': photoUrl,
          'notes': notes,
          'moisture_low': moistureLow,
          'moisture_ok': moistureOk,
          'moisture_high': moistureHigh,
          'lux_low': luxLow,
          'lux_high': luxHigh,
        })
        .eq('id', id);
    _notifyChanged();
  }

  Future<void> deletePlant(String id) async {
    await _client.from('plants').delete().eq('id', id);
    _notifyChanged();
  }

  Future<void> moveReadings({
    required String fromPlantId,
    required String toPlantId,
  }) async {
    await _client
        .from('readings')
        .update({'plant_id': toPlantId})
        .eq('plant_id', fromPlantId);
    _notifyChanged();
  }

  Future<bool> hasReadings(String plantId) async {
    final response = await _client
        .from('readings')
        .select('id')
        .eq('plant_id', plantId)
        .limit(1);
    return response.isNotEmpty;
  }

  Stream<PlantReading?> latestReading() {
    return latestReadingForPlant();
  }

  Stream<PlantReading?> latestReadingForPlant({String? plantId}) {
    return _client
        .from('readings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) {
          final filteredRows = plantId != null && plantId.isNotEmpty
              ? rows.where((row) => row['plant_id'] == plantId).toList()
              : rows;
          if (filteredRows.isEmpty) {
            return null;
          }
          return PlantReading.fromMap(
            Map<String, dynamic>.from(filteredRows.first),
          );
        });
  }

  Stream<List<PlantReading>> recentReadings({int limit = 20, String? plantId}) {
    return _client
        .from('readings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) {
          final filteredRows = plantId != null && plantId.isNotEmpty
              ? rows.where((row) => row['plant_id'] == plantId)
              : rows;
          return filteredRows
              .take(limit)
              .map(
                (row) => PlantReading.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false);
        });
  }

  Stream<List<PlantReading>> readingsSince({
    required DateTime since,
    String? plantId,
  }) {
    return _client
        .from('readings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) {
          final filteredRows = rows.where((row) {
            if (plantId != null &&
                plantId.isNotEmpty &&
                row['plant_id'] != plantId) {
              return false;
            }
            final createdAt = DateTime.tryParse(
              row['created_at'] as String? ?? '',
            );
            return createdAt != null && createdAt.isAfter(since);
          });
          return filteredRows
              .map(
                (row) => PlantReading.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false);
        });
  }

  Stream<List<ChatMessage>> messages({required String plantId}) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('created_at', ascending: true)
        .map(
          (rows) => rows
              .map((row) => ChatMessage.fromMap(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  Future<int> clearConversation({required String plantId}) async {
    await _client.from('messages').delete().eq('plant_id', plantId);
    // Verify effective deletion (useful when RLS prevents delete silently).
    final remaining = await _client
        .from('messages')
        .select('id')
        .eq('plant_id', plantId);
    _notifyChanged();
    return (remaining as List<dynamic>).length;
  }

  Stream<List<AiDecision>> recentAiDecisions({
    required String plantId,
    int limit = 20,
  }) {
    return _client
        .from('ai_decisions')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .take(limit)
              .map((row) => AiDecision.fromMap(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  Future<void> updateAiDecisionOutcome({
    required int decisionId,
    required String outcome,
  }) async {
    await _client
        .from('ai_decisions')
        .update({'outcome': outcome})
        .eq('id', decisionId);
    _notifyChanged();
  }
}
