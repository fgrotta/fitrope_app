import 'package:cloud_firestore/cloud_firestore.dart';

/// Famiglia di abbonamento: determina a quali tipologie di corso dà accesso.
enum SubscriptionFamily { OPEN, PT }

/// Modalità di addebito di un abbonamento.
/// - FREQUENCY: limite di ingressi a settimana (eventualmente illimitato).
/// - ENTRIES: numero fisso di ingressi che si consumano.
enum BillingMode { FREQUENCY, ENTRIES }

/// Abbonamento dell'utente. In v1 è mantenuto come snapshot denormalizzato in
/// `FitropeUser.activeSubscriptions` (scritto dalle Cloud Functions a partire da
/// PR3); la fonte di verità sarà la collezione `subscriptions`.
class UserSubscription {
  /// Id del documento sorgente nella collezione `subscriptions` (PR3+); null per
  /// snapshot senza riferimento.
  final String? id;
  final String planKey;
  final SubscriptionFamily family;
  final BillingMode billingMode;

  /// Tag dei corsi coperti (accesso). 1:1 con la famiglia (D2).
  final Set<String> courseTypeTags;

  /// Ingressi a settimana per FREQUENCY: 2, 3, oppure null = illimitato.
  final int? weeklyFrequency;

  /// Ingressi residui per ENTRIES.
  final int? remainingEntries;

  final Timestamp startDate;
  final Timestamp endDate;

  const UserSubscription({
    this.id,
    required this.planKey,
    required this.family,
    required this.billingMode,
    required this.courseTypeTags,
    this.weeklyFrequency,
    this.remainingEntries,
    required this.startDate,
    required this.endDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'planKey': planKey,
      'family': family.name,
      'billingMode': billingMode.name,
      'courseTypeTags': courseTypeTags.toList(),
      'weeklyFrequency': weeklyFrequency,
      'remainingEntries': remainingEntries,
      'startDate': startDate,
      'endDate': endDate,
    };
  }

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    final planKeyValue = json['planKey'];
    final familyValue = json['family'];
    final billingModeValue = json['billingMode'];
    if (planKeyValue is! String) {
      throw const FormatException('planKey mancante o non testuale');
    }
    if (familyValue is! String) {
      throw const FormatException('family mancante o non testuale');
    }
    if (billingModeValue is! String) {
      throw const FormatException('billingMode mancante o non testuale');
    }
    final family = SubscriptionFamily.values.where(
      (value) => value.name == familyValue,
    );
    final billingMode = BillingMode.values.where(
      (value) => value.name == billingModeValue,
    );
    if (family.isEmpty) {
      throw FormatException('family sconosciuta: $familyValue');
    }
    if (billingMode.isEmpty) {
      throw FormatException('billingMode sconosciuto: $billingModeValue');
    }
    final planShape = _knownPlanShape(planKeyValue);
    if (planShape == null) {
      throw FormatException('planKey sconosciuta: $planKeyValue');
    }
    if (planShape.$1 != family.single || planShape.$2 != billingMode.single) {
      throw FormatException(
        'planKey incoerente con family/billingMode: $planKeyValue',
      );
    }
    final rawTags = json['courseTypeTags'];
    if (rawTags is! List || rawTags.any((value) => value is! String)) {
      throw const FormatException('courseTypeTags mancante o non valido');
    }
    final courseTypeTags = rawTags.cast<String>().toSet();
    final expectedTag =
        family.single == SubscriptionFamily.OPEN ? 'Open' : 'Personal Trainer';
    if (rawTags.length != 1 || !courseTypeTags.contains(expectedTag)) {
      throw FormatException('courseTypeTags incoerente con family: $rawTags');
    }
    final weeklyFrequency = json['weeklyFrequency'];
    final remainingEntries = json['remainingEntries'];
    if (billingMode.single == BillingMode.FREQUENCY) {
      final expectedWeekly = planKeyValue.contains('_2x_')
          ? 2
          : planKeyValue.contains('_3x_')
              ? 3
              : null;
      if (weeklyFrequency != expectedWeekly || remainingEntries != null) {
        throw FormatException('limiti FREQUENCY incoerenti: $planKeyValue');
      }
    } else if (weeklyFrequency != null ||
        remainingEntries is! int ||
        remainingEntries < 0) {
      throw FormatException('crediti ENTRIES incoerenti: $planKeyValue');
    }
    return UserSubscription(
      id: json['id'] as String?,
      planKey: planKeyValue,
      family: family.single,
      billingMode: billingMode.single,
      courseTypeTags: courseTypeTags,
      weeklyFrequency: weeklyFrequency as int?,
      remainingEntries: remainingEntries as int?,
      startDate: json['startDate'] as Timestamp,
      endDate: json['endDate'] as Timestamp,
    );
  }
}

(SubscriptionFamily, BillingMode)? _knownPlanShape(String planKey) {
  if (RegExp(r'^open_(2x|3x|unlim)_(1|3|6|12)m$').hasMatch(planKey)) {
    return (SubscriptionFamily.OPEN, BillingMode.FREQUENCY);
  }
  if (RegExp(r'^open_10i_(1|3|6|12)m$').hasMatch(planKey)) {
    return (SubscriptionFamily.OPEN, BillingMode.ENTRIES);
  }
  if (RegExp(r'^pt_10i_(1|3|6|12)m$').hasMatch(planKey)) {
    return (SubscriptionFamily.PT, BillingMode.ENTRIES);
  }
  return null;
}
