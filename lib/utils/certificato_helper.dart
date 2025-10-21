import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Helper per la gestione dei certificati medici
class CertificatoHelper {
  /// Soglia di giorni per considerare un certificato in scadenza
  static const int GIORNI_SOGLIA_SCADENZA = 15;

  /// Verifica se un certificato è in scadenza (≤ 10 giorni)
  static bool isCertificatoInScadenza(Timestamp? scadenza) {
    if (scadenza == null) return false;
    
    final oggi = DateTime.now();
    final dataScadenza = scadenza.toDate();
    final differenzaGiorni = dataScadenza.difference(oggi).inDays;
    
    return differenzaGiorni <= GIORNI_SOGLIA_SCADENZA && differenzaGiorni >= 0;
  }

  /// Verifica se un certificato è scaduto
  static bool isCertificatoScaduto(Timestamp? scadenza) {
    if (scadenza == null) return false;
    
    final oggi = DateTime.now();
    final dataScadenza = scadenza.toDate();
    
    return dataScadenza.isBefore(oggi);
  }

  /// Formatta la data di scadenza del certificato
  static String formatDataScadenza(Timestamp? scadenza) {
    if (scadenza == null) return 'Non impostato';
    
    final formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(scadenza.toDate());
  }

  /// Ottiene il colore appropriato per la data di scadenza
  static Color getColoreScadenza(Timestamp? scadenza) {
    if (scadenza == null) return Colors.grey;
    
    if (isCertificatoScaduto(scadenza)) {
      return Colors.red;
    } else if (isCertificatoInScadenza(scadenza)) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  /// Ottiene il testo di stato del certificato
  static String getStatoCertificato(Timestamp? scadenza) {
    if (scadenza == null) return 'Non impostato';
    
    if (isCertificatoScaduto(scadenza)) {
      return 'Scaduto';
    } else if (isCertificatoInScadenza(scadenza)) {
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
