import 'package:cloud_functions/cloud_functions.dart';

/// Facade per la migrazione puntuale legacy, disponibile esclusivamente agli
/// Admin; autorizzazione e fingerprint sono sempre verificati dal server.
class LegacyUserMigrationApi {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west8');

  static Future<Map<String, dynamic>> preview(String userId) async {
    final result = await _functions
        .httpsCallable('previewLegacyUserMigration')
        .call(<String, dynamic>{'userId': userId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> migrateAuto({
    required String userId,
    required String expectedFingerprint,
  }) async {
    final result = await _functions.httpsCallable('migrateLegacyUser').call(
      <String, dynamic>{
        'userId': userId,
        'mode': 'AUTO',
        'expectedFingerprint': expectedFingerprint,
      },
    );
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> migrateGuided({
    required String userId,
    required String expectedFingerprint,
    required String planKey,
    required DateTime startDate,
    required DateTime endDate,
    int? remainingEntries,
  }) async {
    final result = await _functions.httpsCallable('migrateLegacyUser').call(
      <String, dynamic>{
        'userId': userId,
        'mode': 'GUIDED',
        'expectedFingerprint': expectedFingerprint,
        'target': <String, dynamic>{
          'planKey': planKey,
          'startDateMillis': startDate.millisecondsSinceEpoch,
          'endDateMillis': endDate.millisecondsSinceEpoch,
          if (remainingEntries != null) 'remainingEntries': remainingEntries,
        },
      },
    );
    return Map<String, dynamic>.from(result.data as Map);
  }
}
