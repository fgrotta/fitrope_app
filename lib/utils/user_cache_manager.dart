import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/authentication/getUsersWithExpiringCertificates.dart';
import 'package:fitrope_app/api/authentication/getUsersWithExpiringSubscriptions.dart';

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

