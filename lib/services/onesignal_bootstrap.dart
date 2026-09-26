import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/services/onesignal_service.dart';

// TODO: Sostituire con il tuo OneSignal App ID dalla dashboard
const String oneSignalAppId = '154fc17b-3ef8-4421-a1e6-466172fa48db';

/// OneSignal è attivo solo in produzione. In modalità emulatore registrerebbe
/// il device (e al login gli utenti seed) sull'app OneSignal di PRODUZIONE,
/// rompendo l'isolamento del QA; staging non ha un'app OneSignal propria.
const bool oneSignalEnabled =
    !bool.fromEnvironment('USE_EMULATOR') && !isStaging;

bool _initialized = false;

/// Unico punto che inizializza OneSignal, idempotente. Sul web il SDK viene
/// scaricato proprio da qui (vedi `oneSignalLoadSdk` in `web/index.html`),
/// quindi va chiamato solo quando serve: all'avvio se l'utente è già loggato
/// (`main.dart`) e prima di legare l'identità (`Protected`).
void ensureOneSignalInitialized() {
  if (!oneSignalEnabled || _initialized) return;
  _initialized = true;
  OneSignalService.initialize(oneSignalAppId);
}
