import 'package:fitrope_app/types/fitropeUser.dart';

String getTipologiaIscrizioneTitle(TipologiaIscrizione tipologiaIscrizione, bool isExpired) {
  switch(tipologiaIscrizione) {
    case TipologiaIscrizione.ABBONAMENTO_MENSILE : return 'Abbonamento mensile${isExpired ? ' (Scaduto)' : ''}';
    case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE : return 'Abbonamento trimestrale';
    case TipologiaIscrizione.PACCHETTO_ENTRATE : return 'Pacchetto entrate';
  }
}

String getTipologiaIscrizioneDescription(FitropeUser user) {
  switch(user.tipologiaIscrizione) {
    case TipologiaIscrizione.ABBONAMENTO_MENSILE : return 'Entrate disponibili: ${user.entrateSettimanali} volte a settimana';
    case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE : return 'Entrate disponibili: ${user.entrateSettimanali} volte a settimana';
    case TipologiaIscrizione.PACCHETTO_ENTRATE : return 'Entrate disponibili: ${user.entrateDisponibili}';
    default: return '';
  }
}