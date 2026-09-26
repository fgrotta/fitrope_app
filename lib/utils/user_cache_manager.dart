import 'package:fitrope_app/utils/refresh_manager.dart';
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
///
/// È l'UNICO punto che notifica `RefreshManager` dopo una mutazione utente, e
/// lo fa una volta sola: le `invalidate*` singole azzerano soltanto. Chi
/// notifica per conto suo subito dopo (il refresh al resume di `Protected`)
/// passa `notify: false`, altrimenti ogni listener girerebbe due volte.
void invalidateAllUserCaches({bool notify = true}) {
  invalidateUsersCache();
  invalidateUsersWithExpiringCertificatesCache();
  invalidateUsersWithExpiringSubscriptionsCache();
  if (notify) RefreshManager().notifyRefresh();
}
