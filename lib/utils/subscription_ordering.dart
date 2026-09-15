import 'package:fitrope_app/types/fitrope_user.dart';

/// Ordine di business delle tipologie di abbonamento, usato ovunque se ne
/// mostri una distribuzione.
///
/// NON è l'ordine di dichiarazione di [TipologiaIscrizione]: `ABBONAMENTO_PROVA`
/// sta in coda all'enum solo perché aggiunto dopo. L'ordine vive qui e non
/// nell'enum perché quest'ultimo alimenta anche i dropdown di scrittura, dove un
/// riordino sarebbe un cambiamento invisibile in review.
const List<TipologiaIscrizione> kTipologiaIscrizioneOrder = [
  TipologiaIscrizione.PACCHETTO_ENTRATE,
  TipologiaIscrizione.ABBONAMENTO_PROVA,
  TipologiaIscrizione.ABBONAMENTO_MENSILE,
  TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE,
  TipologiaIscrizione.ABBONAMENTO_SEMESTRALE,
  TipologiaIscrizione.ABBONAMENTO_ANNUALE,
];

/// Conteggi in ordine canonico, con **tutte** le tipologie presenti anche a
/// zero.
///
/// Rimpiazza l'ordinamento per conteggio decrescente, che senza tie-break
/// lasciava l'ordine delle voci a pari merito alla `Map` di partenza: le voci si
/// scambiavano di posto a ogni refresh. Includendo anche gli zeri la posizione
/// di una voce non cambia mai.
List<MapEntry<TipologiaIscrizione, int>> orderedTipologiaCounts(
  Map<TipologiaIscrizione, int> counts,
) =>
    [for (final t in kTipologiaIscrizioneOrder) MapEntry(t, counts[t] ?? 0)];
