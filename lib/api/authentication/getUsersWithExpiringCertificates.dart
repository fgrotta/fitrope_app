import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';


List<FitropeUser>? _cachedUsersWithExpiringCertificates;
DateTime? _lastCacheTimeWithExpiringCertificates;
const Duration _cacheDurationWithExpiringCertificates = Duration(minutes: 5);

/// API ottimizzata per ottenere solo gli utenti con certificati in scadenza
/// Utilizza query Firestore per massimizzare le performance
Future<List<FitropeUser>> getUsersWithExpiringCertificates() async {
  try {
    if (_cachedUsersWithExpiringCertificates != null && _lastCacheTimeWithExpiringCertificates != null) {
      final timeSinceLastCache = DateTime.now().difference(_lastCacheTimeWithExpiringCertificates!);
      if (timeSinceLastCache < _cacheDurationWithExpiringCertificates) {
        return _cachedUsersWithExpiringCertificates!;
      }
    }

    final oggi = DateTime.now();
    final dataLimite = oggi.add(Duration(days: CertificatoHelper.GIORNI_SOGLIA_SCADENZA));
    
    // Query ottimizzata: cerca solo utenti con certificato in scadenza
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('certificatoScadenza', isNull: false)
        .where('certificatoScadenza', isLessThanOrEqualTo: Timestamp.fromDate(dataLimite))
        .orderBy('certificatoScadenza', descending: false)
        .get();

    _cachedUsersWithExpiringCertificates = querySnapshot.docs
        .map((doc) => FitropeUser.fromJson(doc.data()))
        .toList();
    _lastCacheTimeWithExpiringCertificates = DateTime.now();

    return _cachedUsersWithExpiringCertificates!;
  } catch (e) {
    print('Errore nel caricamento utenti con certificati in scadenza: $e');
    return [];
  }
}

/// API per ottenere il conteggio degli utenti con certificati in scadenza
/// Utile per badge o indicatori senza dover caricare tutti i dati
Future<int> getCountUsersWithExpiringCertificates() async {
  if (_cachedUsersWithExpiringCertificates != null && _lastCacheTimeWithExpiringCertificates != null) {
    final timeSinceLastCache = DateTime.now().difference(_lastCacheTimeWithExpiringCertificates!);
    if (timeSinceLastCache < _cacheDurationWithExpiringCertificates) {
      return _cachedUsersWithExpiringCertificates!.length;
    }
  }

  try {
    final oggi = DateTime.now();
    final dataLimite = oggi.add(Duration(days: CertificatoHelper.GIORNI_SOGLIA_SCADENZA));
    
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('certificatoScadenza', isNull: false)
        .where('certificatoScadenza', isLessThanOrEqualTo: Timestamp.fromDate(dataLimite))
        .get();

    _cachedUsersWithExpiringCertificates = querySnapshot.docs
        .map((doc) => FitropeUser.fromJson(doc.data()))
        .toList();
    _lastCacheTimeWithExpiringCertificates = DateTime.now();

    return _cachedUsersWithExpiringCertificates!.length;
  } catch (e) {
    print('Errore nel conteggio utenti con certificati in scadenza: $e');
    return 0;
  }
 
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateUsersWithExpiringCertificatesCache() {
  _cachedUsersWithExpiringCertificates = null;
  _lastCacheTimeWithExpiringCertificates = null;
}