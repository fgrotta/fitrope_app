// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

// Aggiornamento profilo DIFF-BASED (PR6): scrive su Firestore SOLO i campi
// effettivamente cambiati rispetto a [original]. È essenziale per le
// firestore.rules field-level: inviare il payload completo includerebbe nel
// `diff().affectedKeys()` anche le chiavi assenti nel doc (aggiunte) e i
// Timestamp ri-normalizzati, facendo fallire il salvataggio del proprio
// profilo (self → whitelist) o l'edit di un Trainer. Confrontando con
// [original] si inviano solo le chiavi davvero modificate.
//
// I campi server-owned (courses, waitlistCourses, activeSubscriptions,
// enrollmentConsumption, cancelledEnrollments) NON sono gestiti qui: li scrive
// solo il server (callable), e le rules li negano comunque al client.

bool _sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _sameTags(List<String> a, List<String> b) {
  final sa = a.toSet();
  final sb = b.toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}

/// Costruisce la mappa dei SOLI campi cambiati rispetto a [original], già
/// serializzati per Firestore. Funzione PURA (testabile senza I/O): è qui che
/// vive la logica che, sbagliata, romperebbe il salvataggio profilo sotto le
/// firestore.rules (vedi test/updateUser_test.dart).
///
/// Note di confronto:
/// - fineIscrizione/certificatoScadenza: per GIORNO — la UI le ri-serializza a
///   23:59, quindi un confronto per-istante darebbe un falso "cambiato" se nel
///   doc l'orario è diverso (es. utenti registrati).
/// - tipologiaCorsoTags: set-based (l'ordine dei FilterChip non conta).
/// - entrateDisponibili/entrateSettimanali: si scrivono solo se NON-null e
///   diversi — un campo numerico svuotato per errore (int.tryParse → null) NON
///   deve azzerare il credito (che governa l'eligibility).
Map<String, dynamic> buildUserUpdateDiff({
  required FitropeUser original,
  required String name,
  required String lastName,
  required String role,
  TipologiaIscrizione? tipologiaIscrizione,
  int? entrateDisponibili,
  int? entrateSettimanali,
  DateTime? fineIscrizione,
  bool? isActive,
  bool? isAnonymous,
  DateTime? certificatoScadenza,
  String? numeroTelefono,
  List<String>? tipologiaCorsoTags,
  bool? emailNotificationsEnabled,
  bool? pushNotificationsEnabled,
}) {
  final changed = <String, dynamic>{};

  if (name != original.name) changed['name'] = name;
  if (lastName != original.lastName) changed['lastName'] = lastName;
  if (role != original.role) changed['role'] = role;
  if (tipologiaIscrizione != original.tipologiaIscrizione) {
    changed['tipologiaIscrizione'] =
        tipologiaIscrizione?.toString().split('.').last;
  }
  if (entrateDisponibili != null &&
      entrateDisponibili != original.entrateDisponibili) {
    changed['entrateDisponibili'] = entrateDisponibili;
  }
  if (entrateSettimanali != null &&
      entrateSettimanali != original.entrateSettimanali) {
    changed['entrateSettimanali'] = entrateSettimanali;
  }
  if (!_sameDay(fineIscrizione, original.fineIscrizione?.toDate())) {
    changed['fineIscrizione'] = fineIscrizione != null
        ? Timestamp.fromDate(DateTime(fineIscrizione.year,
            fineIscrizione.month, fineIscrizione.day, 23, 59))
        : null;
  }
  if (isActive != null && isActive != original.isActive) {
    changed['isActive'] = isActive;
  }
  if (isAnonymous != null && isAnonymous != original.isAnonymous) {
    changed['isAnonymous'] = isAnonymous;
  }
  if (!_sameDay(certificatoScadenza, original.certificatoScadenza?.toDate())) {
    changed['certificatoScadenza'] = certificatoScadenza != null
        ? Timestamp.fromDate(DateTime(certificatoScadenza.year,
            certificatoScadenza.month, certificatoScadenza.day, 23, 59))
        : null;
  }
  if (numeroTelefono != original.numeroTelefono) {
    changed['numeroTelefono'] = numeroTelefono;
  }
  if (tipologiaCorsoTags != null &&
      !_sameTags(tipologiaCorsoTags, original.tipologiaCorsoTags)) {
    changed['tipologiaCorsoTags'] = tipologiaCorsoTags;
  }
  if (emailNotificationsEnabled != null &&
      emailNotificationsEnabled != original.emailNotificationsEnabled) {
    changed['emailNotificationsEnabled'] = emailNotificationsEnabled;
  }
  if (pushNotificationsEnabled != null &&
      pushNotificationsEnabled != original.pushNotificationsEnabled) {
    changed['pushNotificationsEnabled'] = pushNotificationsEnabled;
  }

  return changed;
}

Future<void> updateUser({
  required FitropeUser original,
  required String name,
  required String lastName,
  required String role,
  TipologiaIscrizione? tipologiaIscrizione,
  int? entrateDisponibili,
  int? entrateSettimanali,
  DateTime? fineIscrizione,
  bool? isActive,
  bool? isAnonymous,
  DateTime? certificatoScadenza,
  String? numeroTelefono,
  List<String>? tipologiaCorsoTags,
  bool? emailNotificationsEnabled,
  bool? pushNotificationsEnabled,
}) async {
  try {
    final changed = buildUserUpdateDiff(
      original: original,
      name: name,
      lastName: lastName,
      role: role,
      tipologiaIscrizione: tipologiaIscrizione,
      entrateDisponibili: entrateDisponibili,
      entrateSettimanali: entrateSettimanali,
      fineIscrizione: fineIscrizione,
      isActive: isActive,
      isAnonymous: isAnonymous,
      certificatoScadenza: certificatoScadenza,
      numeroTelefono: numeroTelefono,
      tipologiaCorsoTags: tipologiaCorsoTags,
      emailNotificationsEnabled: emailNotificationsEnabled,
      pushNotificationsEnabled: pushNotificationsEnabled,
    );

    if (changed.isEmpty) {
      print('updateUser: nessun campo modificato per ${original.uid}');
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(original.uid)
        .update(changed);

    invalidateAllUserCaches();
    print('User updated: ${original.uid} (${changed.keys.join(", ")})');
  } catch (e) {
    print('Error updating user: $e');
    rethrow;
  }
}
