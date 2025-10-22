import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Helper per la gestione degli abbonamenti
class AbbonamentoHelper {
  /// Soglia di giorni per considerare un abbonamento in scadenza
  static const int GIORNI_SOGLIA_SCADENZA_ABBONAMENTO = 15;

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
