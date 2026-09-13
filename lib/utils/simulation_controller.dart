import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/simulation_permissions.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:flutter/material.dart';

/// Entrata e uscita dalla modalità simulazione.
///
/// ## Perché un remount completo e non un semplice dispatch
///
/// Le pagine dell'area protetta catturano l'utente **una volta sola** in
/// `initState` (`Protected`, `HomePage`, `CalendarPage`) e non ascoltano lo
/// store: un dispatch non le ri-renderizza. Servono `State` nuovi.
///
/// `pushNamedAndRemoveUntil` è l'unica alternativa che funziona:
/// - una `key` sul subtree non fa nulla finché il Navigator non ricostruisce;
/// - una `ValueKey` su `MaterialApp` distrugge il Navigator e riparte da
///   `INITIAL_ROUTE` (lo splash);
/// - `pushReplacementNamed` sostituisce solo la route in cima: entrando dalla
///   `UserDetailPage` (pushata *sopra* `Protected`) lascerebbe sotto il
///   `Protected` dell'admin, stantio.
///
/// `pushNamedAndRemoveUntil` invece crea `State` nuovi, **svuota lo stack**
/// eliminando le pagine admin sottostanti e lascia intatto `MaterialApp` —
/// quindi la barra nel suo `builder` sopravvive alla transizione. È già
/// l'idioma del repo per i cambi di identità (`logoutRedirect`). Effetto
/// collaterale desiderato: `currentIndex` riparte da 0, si atterra sulla Home.
///
/// Seconda ragione, indipendente: `HomePage` registra e rimuove i listener del
/// `RefreshManager` in modo condizionale a `user.role`, con `user` riassegnato
/// da `refreshCourses`. Con un dispatch in-place *senza* remount farebbe leak di
/// 4 listener puntati a uno `State` morto, che `notifyRefresh()` chiamerebbe al
/// resume dell'app. Col remount la vecchia `HomePage` viene disposta col campo
/// `user` ancora = admin, quindi rimuove esattamente i listener che aveva
/// aggiunto.
class SimulationController {
  SimulationController._();

  /// Entra in simulazione su [target].
  ///
  /// L'**ordine è sincrono e obbligatorio**: gli `StoreConnector` ancora montati
  /// (`Protected`, `AdminUsersPage`, `CalendarPage`) ribuildano prima che la
  /// navigazione completi, e con un ordine diverso si vedrebbe un frame misto —
  /// pagine admin con l'identità dell'utente simulato.
  static void start(BuildContext context, {required FitropeUser target}) {
    // Il predicato è ripetuto qui come precondizione, così l'invariante non
    // dipende dal call site che ha disegnato il bottone.
    if (!canSimulateUser(
      actor: store.state.user,
      target: target,
      isMobileLayout: breakpointOf(context) == ScreenType.mobile,
      alreadySimulating: SimulationSession.isActive,
    )) {
      return;
    }

    final admin = store.state.user!;

    SimulationSession.start(admin: admin, target: target);
    store.dispatch(StartLoadingAction());
    store.dispatch(SetUserAction(target));

    _remount();
  }

  /// Dialog di conferma + [start]. È il punto di ingresso da usare dalla UI:
  /// tiene il testo della conferma in un posto solo per entrambi gli entry
  /// point (lista utenti e dettaglio utente).
  static void confirmAndStart(BuildContext context,
      {required FitropeUser target}) {
    final nome = '${target.name} ${target.lastName}'.trim();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Modalità simulazione'),
        content: Text(
          'Vedrai l\'app come $nome.\n\n'
          'Nessun dato potrà essere modificato.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                const Text('Annulla', style: TextStyle(color: onPrimaryColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Il `context` della pagina, non quello del dialog: il dialog è
              // già stato chiuso e il suo Navigator non serve più.
              start(context, target: target);
            },
            style: TextButton.styleFrom(foregroundColor: primaryColor),
            child: const Text(
              'Avvia simulazione',
              style:
                  TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Esce dalla simulazione e ripristina la vista dell'admin.
  ///
  /// Non prende un `BuildContext`: il chiamante tipico è la barra, che vive
  /// fuori dall'albero del Navigator (vedi [_remount]).
  static void stop() {
    final info = SimulationSession.current.value;
    if (info == null) return;

    final admin = info.realUser;

    SimulationSession.stop();
    store.dispatch(StartLoadingAction());
    // Lo snapshot catturato allo start, senza refetch: l'admin non può essersi
    // modificato durante la simulazione (nessuna scrittura è passata), e un
    // `await` sul percorso di uscita aggiungerebbe solo un modo di fallire.
    store.dispatch(SetUserAction(admin));

    // Le cache in memoria sono state riempite con le letture fatte "da utente":
    // svuotarle rende deterministico il ritorno alla vista admin.
    invalidateAllUserCaches();
    invalidateCoursesCache();

    // NOTA OneSignal: non c'è nulla da ripristinare, *proprio perché* in
    // simulazione non abbiamo mai chiamato OneSignal (vedi le guardie in
    // `onesignal_mobile.dart` / `onesignal_web.dart`). Se quelle guardie
    // venissero rimosse, qui andrebbe rifatto `OneSignalService.login(admin.uid)`.

    _remount();
  }

  static void _remount() {
    // `appNavigatorKey` e non `Navigator.of(context)`: `stop()` viene invocata
    // dalla barra, che sta nel `builder` di `MaterialApp` ed è quindi un
    // ANTENATO del Navigator. Da lì `Navigator.of` non trova nulla e lancia —
    // la sessione risulterebbe chiusa ma la pagina dell'utente simulato
    // resterebbe sullo schermo (bug visto in QA sull'emulatore).
    appNavigatorKey.currentState
        ?.pushNamedAndRemoveUntil(PROTECTED_ROUTE, (route) => false);

    // `StartLoadingAction` copre il frame di transizione con il `Loader` di
    // `Protected`, ma nessuno lo chiude: `Protected.initState` non dispatcha
    // `FinishLoadingAction`. Senza questa riga il Loader resterebbe sopra
    // l'app per sempre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      store.dispatch(FinishLoadingAction());
    });
  }
}
