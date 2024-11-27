import 'package:fitrope_app/types/fitropeUser.dart';

String getTipologiaIscrizioneLabel(TipologiaIscrizione tipologiaIscrizione) {
  switch(tipologiaIscrizione) {
    case TipologiaIscrizione.ABBONAMENTO_MENSILE : return 'Abbonamento mensile';
    case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE : return 'Abbonamento trimestrale';
    case TipologiaIscrizione.PACCHETTO_ENTRATE : return 'Pacchetto entrate';
  }
}