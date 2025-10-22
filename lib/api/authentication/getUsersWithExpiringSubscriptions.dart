import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';

List<FitropeUser>? _cachedUsersWithExpiringSubscriptions;
DateTime? _lastCacheTimeWithExpiringSubscriptions;
const Duration _cacheDurationWithExpiringSubscriptions = Duration(minutes: 5);

/// API ottimizzata per ottenere solo gli utenti con abbonamenti in scadenza
/// Utilizza query Firestore per massimizzare le performance
Future<List<FitropeUser>> getUsersWithExpiringSubscriptions() async {
  try {
    if (_cachedUsersWithExpiringSubscriptions != null && _lastCacheTimeWithExpiringSubscriptions != null) {
      final timeSinceLastCache = DateTime.now().difference(_lastCacheTimeWithExpiringSubscriptions!);
      if (timeSinceLastCache < _cacheDurationWithExpiringSubscriptions) {
        return _cachedUsersWithExpiringSubscriptions!;
      }
    }

    final oggi = DateTime.now();
    final dataLimite = oggi.add(Duration(days: AbbonamentoHelper.GIORNI_SOGLIA_SCADENZA_ABBONAMENTO));
    
    // Query ottimizzata: cerca solo utenti con abbonamento in scadenza
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('fineIscrizione', isNull: false)
        .where('fineIscrizione', isGreaterThanOrEqualTo: Timestamp.fromDate(oggi))
        .where('fineIscrizione', isLessThanOrEqualTo: Timestamp.fromDate(dataLimite))
        .orderBy('fineIscrizione', descending: false)
        .get();

    _cachedUsersWithExpiringSubscriptions = querySnapshot.docs
        .map((doc) => FitropeUser.fromJson(doc.data()))
        .toList();
    _lastCacheTimeWithExpiringSubscriptions = DateTime.now();

    return _cachedUsersWithExpiringSubscriptions!;
  } catch (e) {
    print('Errore nel caricamento utenti con abbonamenti in scadenza: $e');
    return [];
  }
}

/// API per ottenere il conteggio degli utenti con abbonamenti in scadenza
/// Utile per badge o indicatori senza dover caricare tutti i dati
Future<int> getCountUsersWithExpiringSubscriptions() async {
  if (_cachedUsersWithExpiringSubscriptions != null && _lastCacheTimeWithExpiringSubscriptions != null) {
    final timeSinceLastCache = DateTime.now().difference(_lastCacheTimeWithExpiringSubscriptions!);
    if (timeSinceLastCache < _cacheDurationWithExpiringSubscriptions) {
      return _cachedUsersWithExpiringSubscriptions!.length;
    }
  }

  try {
    final oggi = DateTime.now();
    final dataLimite = oggi.add(Duration(days: AbbonamentoHelper.GIORNI_SOGLIA_SCADENZA_ABBONAMENTO));
    
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('fineIscrizione', isNull: false)
        .where('fineIscrizione', isGreaterThanOrEqualTo: Timestamp.fromDate(oggi))
        .where('fineIscrizione', isLessThanOrEqualTo: Timestamp.fromDate(dataLimite))
        .get();

    _cachedUsersWithExpiringSubscriptions = querySnapshot.docs
        .map((doc) => FitropeUser.fromJson(doc.data()))
        .toList();
    _lastCacheTimeWithExpiringSubscriptions = DateTime.now();

    return _cachedUsersWithExpiringSubscriptions!.length;
  } catch (e) {
    print('Errore nel conteggio utenti con abbonamenti in scadenza: $e');
    return 0;
  }
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateUsersWithExpiringSubscriptionsCache() {
  _cachedUsersWithExpiringSubscriptions = null;
  _lastCacheTimeWithExpiringSubscriptions = null;
  RefreshManager().notifyRefresh();
}
