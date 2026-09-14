import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/foundation.dart';

/// Installa [refreshed] in `store.state.user` **solo se l'identità corrente è
/// ancora la sua**.
///
/// I refresh delle pagine catturano l'utente in un campo e dispatchano il
/// risultato dopo un `await`, protetti dal solo `mounted`. Ma `mounted` non dice
/// nulla sull'identità: durante la transizione di `pushNamedAndRemoveUntil` la
/// pagina vecchia resta montata fino a fine animazione (~300ms), più che
/// sufficiente per un round trip Firestore.
///
/// Senza questo controllo, uscendo dalla modalità simulazione un
/// `getUserData(socio)` in volo reinstallava il **socio** nello store *dopo*
/// `SimulationSession.stop()`: sessione spenta (quindi guardie Layer A e B
/// disarmate) ma `store.state.user` = socio, cioè scritture reali a suo nome
/// senza più alcun blocco. La stessa race in entrata lasciava la barra accesa
/// con l'admin nello store.
///
/// Vale per OGNI dispatch di `SetUserAction` che segue un `await` e non è un
/// vero cambio di identità (login, start/stop simulazione, `resetUser`):
/// pagine, `callEnrollmentFunction`, `UserDetailPage.saveChanges`. Un pre-check
/// sull'uid prima dell'await evita solo una fetch inutile, non la race.
/// **Un refresh non cambia mai chi sei, aggiorna solo i dati di chi sei già**.
void dispatchUserRefreshIfCurrent(FitropeUser refreshed) {
  final currentUid = store.state.user?.uid;
  if (currentUid != refreshed.uid) {
    debugPrint(
        '↩️ Refresh utente scartato: lo store è su $currentUid, non su ${refreshed.uid}');
    return;
  }
  store.dispatch(SetUserAction(refreshed));
}
