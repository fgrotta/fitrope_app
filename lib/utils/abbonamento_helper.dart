import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

/// Helper per la gestione degli abbonamenti
class AbbonamentoHelper {
  /// Finestra giorni per KPI dashboard / filtro lista utenti «in scadenza»
  static const int giorniFinestraScadenzaKpi = 30;

  /// Data di fine iscrizione di default in base alla tipologia di abbonamento.
  /// Garantisce che ogni iscrizione abbia sempre una scadenza impostata.
  /// - Prova: 30 giorni
  /// - Pacchetto ingressi: 3 mesi
  /// - Abbonamenti temporali: durata naturale del tipo
  static DateTime defaultFineIscrizione(TipologiaIscrizione tipo,
      {DateTime? from}) {
    final base = from ?? DateTime.now();
    switch (tipo) {
      case TipologiaIscrizione.ABBONAMENTO_PROVA:
        return base.add(const Duration(days: 30));
      case TipologiaIscrizione.PACCHETTO_ENTRATE:
        return DateTime(base.year, base.month + 3, base.day);
      case TipologiaIscrizione.ABBONAMENTO_MENSILE:
        return DateTime(base.year, base.month + 1, base.day);
      case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE:
        return DateTime(base.year, base.month + 3, base.day);
      case TipologiaIscrizione.ABBONAMENTO_SEMESTRALE:
        return DateTime(base.year, base.month + 6, base.day);
      case TipologiaIscrizione.ABBONAMENTO_ANNUALE:
        return DateTime(base.year + 1, base.month, base.day);
    }
  }

  /// Soglia di giorni per considerare un abbonamento in scadenza
  static const int GIORNI_SOGLIA_SCADENZA_ABBONAMENTO = 15;

  /// `fineIscrizione` futura e entro [giorniFinestraScadenzaKpi] da [reference] (default: ora).
  /// Allineato al KPI «In scadenza (prossimi 30 gg)» della dashboard.
  static bool isFineIscrizioneNeiProssimi30Giorni(
    Timestamp? fineIscrizione, {
    DateTime? reference,
  }) {
    if (fineIscrizione == null) return false;
    final now = reference ?? DateTime.now();
    final end = fineIscrizione.toDate();
    final limit = now.add(const Duration(days: giorniFinestraScadenzaKpi));
    return end.isAfter(now) && end.isBefore(limit);
  }

  /// Verifica se un abbonamento è in scadenza (≤ 15 giorni)
  static bool isAbbonamentoInScadenza(Timestamp? scadenza) {
    if (scadenza == null) return false;
    
    final oggi = DateTime.now();
    final dataScadenza = scadenza.toDate();
    final differenzaGiorni = dataScadenza.difference(oggi).inDays;
    
    return differenzaGiorni <= GIORNI_SOGLIA_SCADENZA_ABBONAMENTO && differenzaGiorni >= 0;
  }

  /// Verifica se un abbonamento è scaduto
  static bool isAbbonamentoScaduto(Timestamp? scadenza) {
    if (scadenza == null) return false;
    
    final oggi = DateTime.now();
    final dataScadenza = scadenza.toDate();
    
    return dataScadenza.isBefore(oggi);
  }

  /// Formatta la data di scadenza dell'abbonamento
  static String formatDataScadenza(Timestamp? scadenza) {
    if (scadenza == null) return 'Non impostato';
    
    final formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(scadenza.toDate());
  }

  /// Ottiene il colore appropriato per la data di scadenza
  static Color getColoreScadenza(Timestamp? scadenza) {
    if (scadenza == null) return Colors.grey;
    
    if (isAbbonamentoScaduto(scadenza)) {
      return Colors.red;
    } else if (isAbbonamentoInScadenza(scadenza)) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  /// Ottiene il testo di stato dell'abbonamento
  static String getStatoAbbonamento(Timestamp? scadenza) {
    if (scadenza == null) return 'Non impostato';
    
    if (isAbbonamentoScaduto(scadenza)) {
      return 'Scaduto';
    } else if (isAbbonamentoInScadenza(scadenza)) {
      final giorni = scadenza.toDate().difference(DateTime.now()).inDays;
      return 'Scade tra $giorni giorni';
    } else {
      return 'Valido';
    }
  }

  /// Calcola i giorni rimanenti alla scadenza
  static int getGiorniRimanenti(Timestamp? scadenza) {
    if (scadenza == null) return -1;
    
    final oggi = DateTime.now();
    final dataScadenza = scadenza.toDate();
    final differenzaGiorni = dataScadenza.difference(oggi).inDays;
    
    return differenzaGiorni;
  }
}
