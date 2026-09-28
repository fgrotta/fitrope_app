import "package:flutter/foundation.dart";
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/utils/certificate_alerts.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';

List<FitropeUser>? _cachedUsersWithExpiringCertificates;
DateTime? _lastCacheTimeWithExpiringCertificates;
const Duration _cacheDurationWithExpiringCertificates = Duration(minutes: 5);

/// Soci con un abbonamento valido e un certificato medico mancante, scaduto o
/// in scadenza ([usersNeedingCertificateAttention]), già ordinati. Filtra in
/// memoria su [getUsers]: una query Firestore su `certificatoScadenza` non
/// vedrebbe chi il certificato non l'ha mai avuto.
Future<List<FitropeUser>> getUsersWithExpiringCertificates() async {
  try {
    if (_cachedUsersWithExpiringCertificates != null &&
        _lastCacheTimeWithExpiringCertificates != null) {
      final timeSinceLastCache =
          DateTime.now().difference(_lastCacheTimeWithExpiringCertificates!);
      if (timeSinceLastCache < _cacheDurationWithExpiringCertificates) {
        return _cachedUsersWithExpiringCertificates!;
      }
    }

    _cachedUsersWithExpiringCertificates =
        usersNeedingCertificateAttention(await getUsers());
    _lastCacheTimeWithExpiringCertificates = DateTime.now();

    return _cachedUsersWithExpiringCertificates!;
  } catch (e) {
    debugPrint('Errore nel caricamento utenti con certificati in scadenza: $e');
    return [];
  }
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateUsersWithExpiringCertificatesCache() {
  _cachedUsersWithExpiringCertificates = null;
  _lastCacheTimeWithExpiringCertificates = null;
  RefreshManager().notifyRefresh();
}
