import 'package:fitrope_app/types/fitropeUser.dart';

/// `true` se l'iscrizione di questo utente a un corso è una "lezione di prova".
///
/// Il concetto non esiste sul corso: è la tipologia di abbonamento dell'utente
/// a renderlo tale. È estratto in una funzione perché fa da gate agli invii
/// WhatsApp e — a differenza del promemoria OneSignal, che in `kDebugMode`
/// parte per qualunque utente — qui il debug non deve mai bypassare il
/// controllo: ogni messaggio WhatsApp è reale e a pagamento.
bool isDemoLessonUser(FitropeUser user) =>
    user.isActive &&
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA;
