import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/simulation_permissions.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
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
/// quindi la barra nel suo `builder` sopravvive alla transizione (il logout
/// usa invece `pushReplacementNamed`, che qui non basterebbe: vedi sopra).
/// Effetto collaterale desiderato: `currentIndex` riparte da 0, si atterra
/// sulla Home.
///
/// Seconda ragione, indipendente: la `HomePage` decide in `initState`, dal
/// ruolo, a cosa agganciarsi (`refreshCourses` per un socio, le sezioni admin
/// per un Admin). Un dispatch in-place *senza* remount lascerebbe montata la
/// Home costruita per il ruolo precedente. I listener di `RefreshManager` non
/// sono più un rischio di leak: `RefreshListenersMixin` toglie in dispose
/// esattamente ciò che ogni State ha registrato.
class SimulationController {
  SimulationController._();

  /// Entra in simulazione su [target].
  ///
  /// Lo snapshot ricevuto dalla UI può provenire dalla cache utenti (5 minuti)
  /// oppure essere precedente a un abbonamento appena assegnato. Prima di
  /// attivare la sessione lo rilegge quindi dal server; fino a quel momento le
  /// guardie restano nello stato corrente e lo store conserva l'admin.
  ///
  /// Dopo l'`await` tutte le precondizioni vengono rivalidate: nel frattempo
  /// l'identità corrente o lo stato della simulazione possono essere cambiati.
  static Future<void> start(
    BuildContext context, {
    required FitropeUser target,
    Future<FitropeUser?> Function(String uid)? loadTarget,
  }) async {
    // Il predicato è ripetuto qui come precondizione, così l'invariante non
    // dipende dal call site che ha disegnato il bottone. Se fallisce lo dice:
    // il dialog di conferma è appena stato chiuso, e un `return` muto
    // sembrerebbe un tap andato a vuoto (caso reale: l'identità corrente o lo
    // stato della sessione cambiano tra l'apertura del dialog e la conferma).
    if (!canSimulateUser(
      actor: store.state.user,
      target: target,
      alreadySimulating: SimulationSession.isActive,
    )) {
      SnackBarUtils.showWarningSnackBar(
          context, 'Simulazione non disponibile per questo utente');
      return;
    }

    final admin = store.state.user!;
    store.dispatch(StartLoadingAction());

    try {
      final freshTarget = await (loadTarget ?? getUser)(target.uid);
      if (!context.mounted) {
        store.dispatch(FinishLoadingAction());
        return;
      }

      final actor = store.state.user;
      final canStart = freshTarget != null &&
          freshTarget.uid == target.uid &&
          actor?.uid == admin.uid &&
          canSimulateUser(
            actor: actor,
            target: freshTarget,
            alreadySimulating: SimulationSession.isActive,
          );
      if (!canStart) {
        store.dispatch(FinishLoadingAction());
        SnackBarUtils.showWarningSnackBar(
            context, 'Simulazione non più disponibile per questo utente');
        return;
      }

      // Da qui al remount la sequenza deve restare sincrona: i widget ancora
      // montati non devono osservare una sessione e uno store con identità
      // diverse in due frame distinti.
      SimulationSession.start(admin: admin, target: freshTarget);
      store.dispatch(SetUserAction(freshTarget));
      _remount();
    } catch (e) {
      store.dispatch(FinishLoadingAction());
      if (!context.mounted) return;
      debugPrint('⛔ [Simulazione] caricamento utente fallito: $e');
      SnackBarUtils.showErrorSnackBar(
          context, 'Impossibile caricare i dati aggiornati dell\'utente');
    }
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
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Il `context` della pagina, non quello del dialog: il dialog è
              // già stato chiuso e il suo Navigator non serve più.
              await start(context, target: target);
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

    // NIENTE invalidazione delle cache qui. Non serve — in simulazione non è
    // passata alcuna scrittura e le letture usano comunque l'auth dell'admin,
    // quindi le cache contengono esattamente ciò che l'admin rileggerebbe — e
    // fa lavoro inutile: `invalidateAllUserCaches()` (che per default è
    // l'unico punto a notificare dopo una mutazione utente) chiama
    // `RefreshManager().notifyRefresh()` in modo SINCRONO, mentre la HomePage
    // del socio è ancora montata (il remount arriva dopo). Il suo
    // `refreshCourses` copierebbe lo store (già = admin) nel proprio campo
    // `user` e la Home, ora da "Admin", monterebbe `AdminHomeSections`
    // (download del part + quattro letture) per pochi istanti prima di essere
    // smontata. Nessun leak — `RefreshListenersMixin` toglie tutto in dispose —
    // ma solo costi. Il refresh forzato al resume (`_onResumeRefresh`) resta la
    // via per rileggere dal server.

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
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      // Senza remount sessione e UI restano disallineate — esattamente il
      // sintomo del bug che `appNavigatorKey` è qui per evitare. Meglio
      // rumoroso che invisibile. Ma il `StartLoadingAction` è già partito:
      // senza questo Finish il Loader coprirebbe per sempre la prossima
      // schermata montata (Protected e LoginPage lo leggono entrambe).
      debugPrint(
          '⛔ [Simulazione] remount saltato: appNavigatorKey non montata.');
      store.dispatch(FinishLoadingAction());
      return;
    }
    navigator.pushNamedAndRemoveUntil(PROTECTED_ROUTE, (route) => false);

    // `StartLoadingAction` copre il frame di transizione con il `Loader` di
    // `Protected`, ma nessuno lo chiude: `Protected.initState` non dispatcha
    // `FinishLoadingAction`. Senza questa riga il Loader resterebbe sopra
    // l'app per sempre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      store.dispatch(FinishLoadingAction());
    });
  }
}
