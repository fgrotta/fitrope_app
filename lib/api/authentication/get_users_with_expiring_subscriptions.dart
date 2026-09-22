import "package:flutter/foundation.dart";
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:fitrope_app/utils/subscription_expiry.dart';

List<FitropeUser>? _cachedUsersWithExpiringSubscriptions;
DateTime? _lastCacheTimeWithExpiringSubscriptions;
const Duration _cacheDurationWithExpiringSubscriptions = Duration(minutes: 5);

/// API ottimizzata per ottenere solo gli utenti con abbonamenti in scadenza
/// Utilizza query Firestore per massimizzare le performance
Future<List<FitropeUser>> getUsersWithExpiringSubscriptions() async {
  try {
    if (_cachedUsersWithExpiringSubscriptions != null &&
        _lastCacheTimeWithExpiringSubscriptions != null) {
      final timeSinceLastCache =
          DateTime.now().difference(_lastCacheTimeWithExpiringSubscriptions!);
      if (timeSinceLastCache < _cacheDurationWithExpiringSubscriptions) {
        return _cachedUsersWithExpiringSubscriptions!;
      }
    }

    _cachedUsersWithExpiringSubscriptions =
        (await getUsers()).where(hasSubscriptionExpiringInNext30Days).toList();
    _lastCacheTimeWithExpiringSubscriptions = DateTime.now();

    return _cachedUsersWithExpiringSubscriptions!;
  } catch (e) {
    debugPrint('Errore nel caricamento utenti con abbonamenti in scadenza: $e');
    return [];
  }
}

/// API per ottenere il conteggio degli utenti con abbonamenti in scadenza
/// Utile per badge o indicatori senza dover caricare tutti i dati
Future<int> getCountUsersWithExpiringSubscriptions() async {
  if (_cachedUsersWithExpiringSubscriptions != null &&
      _lastCacheTimeWithExpiringSubscriptions != null) {
    final timeSinceLastCache =
        DateTime.now().difference(_lastCacheTimeWithExpiringSubscriptions!);
    if (timeSinceLastCache < _cacheDurationWithExpiringSubscriptions) {
      return _cachedUsersWithExpiringSubscriptions!.length;
    }
  }

  try {
    _cachedUsersWithExpiringSubscriptions =
        (await getUsers()).where(hasSubscriptionExpiringInNext30Days).toList();
    _lastCacheTimeWithExpiringSubscriptions = DateTime.now();

    return _cachedUsersWithExpiringSubscriptions!.length;
  } catch (e) {
    debugPrint('Errore nel conteggio utenti con abbonamenti in scadenza: $e');
    return 0;
  }
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateUsersWithExpiringSubscriptionsCache() {
  _cachedUsersWithExpiringSubscriptions = null;
  _lastCacheTimeWithExpiringSubscriptions = null;
  RefreshManager().notifyRefresh();
}
