import 'package:fitrope_app/types/fitropeUser.dart';

String getTipologiaIscrizioneLabel(TipologiaIscrizione tipologiaIscrizione) {
  switch(tipologiaIscrizione) {
    case TipologiaIscrizione.ABBONAMENTO : return 'Abbonamento';
    case TipologiaIscrizione.PACCHETTO_ENTRATE : return 'Pacchetto entrate';
  }
}