import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/api/authentication/get_users_with_expiring_certificates.dart';
import 'package:fitrope_app/api/authentication/get_users_with_expiring_subscriptions.dart';

/// Invalida tutte le cache relative agli utenti
///
/// Questa funzione centralizza la gestione dell'invalidazione delle cache
/// quando viene creato, aggiornato o cancellato un utente.
/// Invalida:
/// - Cache degli utenti principali
/// - Cache degli utenti con certificati in scadenza
/// - Cache degli utenti con abbonamenti in scadenza
void invalidateAllUserCaches() {
  invalidateUsersCache();
  invalidateUsersWithExpiringCertificatesCache();
  invalidateUsersWithExpiringSubscriptionsCache();
}
