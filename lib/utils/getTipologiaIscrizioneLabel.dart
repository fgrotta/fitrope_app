import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/formatDate.dart';

String getTipologiaIscrizioneTitle(TipologiaIscrizione tipologiaIscrizione, bool isExpired) {
  switch(tipologiaIscrizione) {
    case TipologiaIscrizione.ABBONAMENTO_MENSILE : return 'Abbonamento mensile${isExpired ? ' (Scaduto)' : ''}';
    case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE : return 'Abbonamento trimestrale';
    case TipologiaIscrizione.ABBONAMENTO_SEMESTRALE : return 'Abbonamento semestrale';
    case TipologiaIscrizione.ABBONAMENTO_ANNUALE : return 'Abbonamento annuale';
    case TipologiaIscrizione.PACCHETTO_ENTRATE : return 'Pacchetto entrate';
    case TipologiaIscrizione.ABBONAMENTO_PROVA : return 'Lezione di prova';
  }
}

String getTipologiaIscrizioneDescription(FitropeUser user) {
  switch(user.tipologiaIscrizione) {
    case TipologiaIscrizione.ABBONAMENTO_MENSILE : return 'Entrate disponibili: ${user.entrateSettimanali} volte a settimana \nScadenza Abbonamento: ${formatDate(user.fineIscrizione?.toDate())}';
    case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE : return 'Entrate disponibili: ${user.entrateSettimanali} volte a settimana \nScadenza Abbonamento: ${formatDate(user.fineIscrizione?.toDate())}';
    case TipologiaIscrizione.ABBONAMENTO_SEMESTRALE : return 'Entrate disponibili: ${user.entrateSettimanali} volte a settimana \nScadenza Abbonamento: ${formatDate(user.fineIscrizione?.toDate())}';
    case TipologiaIscrizione.ABBONAMENTO_ANNUALE : return 'Entrate disponibili: ${user.entrateSettimanali} volte a settimana \nScadenza Abbonamento: ${formatDate(user.fineIscrizione?.toDate())}';
    case TipologiaIscrizione.PACCHETTO_ENTRATE : return 'Entrate disponibili: ${user.entrateDisponibili} \nScadenza Abbonamento: ${formatDate(user.fineIscrizione?.toDate())}';
    case TipologiaIscrizione.ABBONAMENTO_PROVA : return 'Entrate disponibili: ${user.entrateDisponibili} \nScadenza Abbonamento: ${formatDate(user.fineIscrizione?.toDate())}';
    default: return '';
  }
}

String getTipologiaIscrizioneLabel(TipologiaIscrizione? tipologia) {
  switch (tipologia) {
    case TipologiaIscrizione.PACCHETTO_ENTRATE:
      return 'Pacchetto Entrate';
    case TipologiaIscrizione.ABBONAMENTO_MENSILE:
      return 'Abbonamento Mensile';
    case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE:
      return 'Abbonamento Trimestrale';
    case TipologiaIscrizione.ABBONAMENTO_SEMESTRALE:
      return 'Abbonamento Semestrale';
    case TipologiaIscrizione.ABBONAMENTO_ANNUALE:
      return 'Abbonamento Annuale';
    case TipologiaIscrizione.ABBONAMENTO_PROVA:
      return 'Abbonamento di Prova';
    default:
      return 'Nessun abbonamento';
  }
}